part of 'package:player_flutter/main.dart';

enum VideoFitMode { contain, cover, none, fill }

enum VerticalControlKind { volume, brightness }

bool isLibmpvDolbyVisionTrack(String? profile, String? level) =>
    (num.tryParse(profile?.trim() ?? '') ?? 0) > 0 ||
    (num.tryParse(level?.trim() ?? '') ?? 0) > 0;

bool shouldUseMedia3OnAndroid(bool isTvboxPlayback, bool isDolbyVision) =>
    isTvboxPlayback || isDolbyVision;

int networkBytesPerSecond(int byteDelta, int elapsedMilliseconds) =>
    byteDelta <= 0 || elapsedMilliseconds <= 0
        ? 0
        : byteDelta * 1000 ~/ elapsedMilliseconds;

class VideoPlayerPage extends StatefulWidget {
  const VideoPlayerPage(
      {required this.store,
      required this.item,
      this.playback,
      this.episodes,
      this.playbackResolver,
      super.key});

  final AppStore store;
  final MediaItem item;
  final RemotePlayback? playback;
  final List<MediaItem>? episodes;
  final Future<RemotePlayback> Function(MediaItem)? playbackResolver;

  @override
  State<VideoPlayerPage> createState() => _VideoPlayerPageState();
}

class _VideoPlayerPageState extends State<VideoPlayerPage>
    with SingleTickerProviderStateMixin {
  static const Duration _danmuPositionSyncThreshold =
      Duration(milliseconds: 120);
  static const Duration _danmuVisibleRefreshInterval =
      Duration(milliseconds: 1500);
  static const int _danmuMaxVisibleItems = 36;
  static const int _danmuFixedVisibleMs = 3800;
  static const double _danmuBaseTravelMs = 9500;
  static const double _verticalControlSensitivity = 1.35;
  static const double _verticalControlEdgeDeadZoneRatio = 0.14;
  static const List<double> _playbackRates = [
    0.25,
    0.5,
    0.75,
    1.0,
    1.25,
    1.5,
    1.75,
    2.0,
  ];

  Player? _player;
  VideoController? _controller;
  bool backendSelected = !Platform.isAndroid;
  bool usingMedia3 = false;
  bool media3Ended = false;
  String media3Subtitle = '';
  final Map<String, bool> dolbyVisionCache = {};
  late MediaItem currentItem = widget.item;
  final subscriptions = <StreamSubscription<dynamic>>[];
  Timer? statusTimer;
  Timer? loadingHideTimer;
  Timer? controlsHideTimer;
  Timer? danmuRenderTimer;
  Timer? verticalControlOverlayTimer;
  Timer? landscapeSensorTimer;
  late final AnimationController danmuTicker;
  final danmuOverlayItems = ValueNotifier<List<RustDanmuRenderItem>>(const []);
  final controlsVisible = ValueNotifier<bool>(true);
  final controlsRevision = ValueNotifier<int>(0);
  int lastThrottledControlsNotifyMs = 0;
  Duration position = Duration.zero;
  Duration duration = Duration.zero;
  Duration danmuClockPosition = Duration.zero;
  DateTime danmuClockStamp = DateTime.now();
  Duration? dragPreviewPosition;
  double dragDistance = 0;
  Duration dragStartPosition = Duration.zero;
  VerticalControlKind? verticalControlKind;
  double playbackVolume = 100;
  double playbackRate = 1.0;
  String? verticalControlLabel;
  double verticalControlLevel = 0;
  int? videoWidth;
  int? videoHeight;
  bool playing = false;
  bool ready = false;
  bool orientationLocked = false;
  bool seekingByDrag = false;
  bool streamsAttached = false;
  bool openedOnce = false;
  bool mediaOpenCompleted = false;
  bool playbackPositionConfirmed = false;
  bool mpvLoadingPropertiesAttached = false;
  bool mpvLoadingPropertiesUsable = false;
  bool voConfigured = false;
  bool pausedForCache = false;
  String? lastLoggedVoConfiguredValue;
  String? lastLoggedPausedForCacheValue;
  bool softwareDecoderFallback = false;
  bool fullscreen = false;
  bool controlsLocked = false;
  bool episodePanelOpen = false;
  bool episodePanelClosing = false;
  bool autoAdvancingEpisode = false;
  bool danmuPanelOpen = false;
  bool danmuPanelClosing = false;
  bool danmuSearchPanelOpen = false;
  bool danmuSearchPanelClosing = false;
  bool danmuSearchLoading = false;
  bool danmuSearchStarted = false;
  bool resumeAfterDanmuSearch = false;
  bool buffering = false;
  bool loadingVisible = false;
  bool danmuLoading = false;
  bool inPictureInPicture = false;
  bool playbackWindowFullscreen = false;
  bool windowFocusLost = false;
  bool multiWindowActive = false;
  bool competingWindowActive = false;
  VideoFitMode fitMode = VideoFitMode.contain;
  Tracks availableTracks = const Tracks();
  Track selectedTrack = const Track();
  double bufferingPercentage = 0;
  double? lastLoggedBufferingPercent;
  int transientCodecRetryCount = 0;
  int openAttempt = 0;
  int battery = -1;
  int? lastRxBytes;
  int? lastRxSampleMs;
  String network = 'NET';
  String networkSpeed = '0 KB/s';
  bool charging = false;
  LibraryShowDetail? libraryDetail;
  int danmuSessionId = 0;
  int danmuTotalCount = 0;
  String danmuStatus = '未加载';
  int danmuLoadId = 0;
  String danmuSearchError = '';
  String? selectingDanmuEpisodeId;
  String lastDanmuVisualSignature = '';
  List<DanmuSearchResult> danmuSearchResults = const [];
  late final TextEditingController danmuSearchController;
  late final TextEditingController danmuSearchEpisodeController;
  Object? error;

  Player get player => _player ??= Player(
        configuration: const PlayerConfiguration(
          logLevel: MPVLogLevel.warn,
          bufferSize: 64 * 1024 * 1024,
        ),
      );

  VideoController get controller => _controller ??= VideoController(player);

  Future<void> media3Command(String action, [Object? value]) async {
    await appChannel.invokeMethod<void>('media3Command', {
      'action': action,
      if (value != null) 'value': value,
    });
  }

  Future<void> seekPlayback(Duration target) => usingMedia3
      ? media3Command('seek', target.inMilliseconds)
      : player.seek(target);

  Future<void> playPlayback() =>
      usingMedia3 ? media3Command('play') : player.play();

  Future<void> pausePlayback() =>
      usingMedia3 ? media3Command('pause') : player.pause();

  Future<void> stopPlayback() =>
      usingMedia3 ? media3Command('stop') : player.stop();

  Future<void> setPlaybackVolume(double value) => usingMedia3
      ? media3Command('volume', value / 100)
      : player.setVolume(value);

  Future<void> setPlaybackSpeed(double value) =>
      usingMedia3 ? media3Command('rate', value) : player.setRate(value);

  @override
  void initState() {
    super.initState();
    danmuTicker = AnimationController(
      vsync: this,
      duration: const Duration(hours: 24),
    );
    danmuSearchController = TextEditingController();
    danmuSearchEpisodeController = TextEditingController();
    lastDanmuVisualSignature = danmuVisualSignature(widget.store.danmuConfig);
    widget.store.addListener(handleStoreChanged);
    appChannel.setMethodCallHandler(handleAppChannelCall);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    unawaited(setNativePlaybackPipEnabled(true));
    unawaited(setNativePlaybackPipPlaybackState(playing));
    startStatusTimer();
    startDanmuRenderTimer();
    unawaited(loadCurrentLibraryDetail());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) init();
    });
  }

  void handleStoreChanged() {
    final signature = danmuVisualSignature(widget.store.danmuConfig);
    if (lastDanmuVisualSignature.isNotEmpty &&
        lastDanmuVisualSignature != signature) {
      if (ready) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) refreshVisibleDanmu(force: true);
        });
      }
    }
    lastDanmuVisualSignature = signature;
    setStateIfMounted(() {});
    syncDanmuTickerState();
  }

  String danmuVisualSignature(DanmuConfig config) =>
      '${config.fontSize}:${config.opacity}:${config.speed}:${config.offsetMs}:${config.maxLines}:${config.topPadding}:${config.visible}:${config.enabled}';

  Future<void> loadCurrentLibraryDetail() async {
    final groupKey = mediaFolderKey(currentItem);
    try {
      final detail = await widget.store.loadLibraryShowDetail(groupKey);
      if (!mounted || mediaFolderKey(currentItem) != groupKey) return;
      setState(() => libraryDetail = detail);
      unawaited(loadDanmuForCurrentItem());
    } catch (_) {
      if (mounted && mediaFolderKey(currentItem) == groupKey) {
        setState(() => libraryDetail = null);
      }
    }
  }

  Future<void> loadDanmuForCurrentItem() async {
    final config = widget.store.danmuConfig;
    final file = currentDbFile;
    final title = file?.showTitle?.trim().isNotEmpty == true
        ? file!.showTitle!.trim()
        : mediaGroupDisplayTitle(currentItem);
    final season = file?.seasonNumber ?? currentItem.season;
    final episode = file?.episodeNumber ?? currentItem.episode;
    final sourceFileName = file?.filename ?? mediaIdentityFileName(currentItem);
    final fileNames = buildDanmuMatchFileNames(
      title: title,
      sourceFileName: sourceFileName,
      season: season,
      episode: episode,
    );
    final loadId = ++danmuLoadId;
    if (!config.available) {
      clearDanmuSession();
      setStateIfMounted(() {
        danmuLoading = false;
        danmuTotalCount = 0;
        danmuStatus = '未配置弹幕服务';
      });
      clearDanmuOverlay();
      return;
    }
    setStateIfMounted(() {
      danmuLoading = true;
      danmuStatus = '正在匹配弹幕...';
    });
    widget.store.addDiagnosticLog(
      'danmu load context: item=${currentItem.id}, title=$title, sourceFile=$sourceFileName, season=$season, episode=$episode, candidates=${jsonEncode(fileNames)}, matchBodies=${jsonEncode(fileNames.map((name) => {
            'fileName': name
          }).toList())}, requestBase=${config.requestBaseUrl}',
      category: 'danmu',
    );
    try {
      final result = await DanmuService(
        config,
        log: (message) =>
            widget.store.addDiagnosticLog(message, category: 'danmu'),
      ).loadSession(
        title: title,
        fileNames: fileNames,
        season: season,
        episode: episode,
      );
      if (!mounted || loadId != danmuLoadId) return;
      clearDanmuSession();
      setState(() {
        danmuSessionId = result.sessionId;
        danmuTotalCount = result.count;
        danmuStatus = result.count == 0 ? '没有匹配到弹幕' : '已加载 ${result.count} 条';
        danmuLoading = false;
      });
      clearDanmuOverlay();
      if (ready) refreshVisibleDanmu();
    } catch (error) {
      if (!mounted || loadId != danmuLoadId) return;
      widget.store
          .addDiagnosticLog('danmu load failed: $error', category: 'danmu');
      clearDanmuSession();
      setState(() {
        danmuTotalCount = 0;
        danmuStatus = '弹幕加载失败：$error';
        danmuLoading = false;
      });
      clearDanmuOverlay();
    }
  }

  void clearDanmuSession() {
    final sessionId = danmuSessionId;
    if (sessionId <= 0) return;
    danmuSessionId = 0;
    try {
      RustCoreService.instance.danmuClear(sessionId);
      widget.store.addDiagnosticLog('danmu session cleared: $sessionId',
          category: 'danmu');
    } catch (error) {
      widget.store.addDiagnosticLog('danmu session clear failed: $error',
          category: 'danmu');
    }
  }

  void clearDanmuOverlay() {
    if (danmuOverlayItems.value.isNotEmpty) {
      danmuOverlayItems.value = const [];
    }
    syncDanmuTickerState();
  }

  void startDanmuRenderTimer() {
    danmuRenderTimer?.cancel();
    danmuRenderTimer = Timer.periodic(_danmuVisibleRefreshInterval, (_) {
      if (shouldRefreshDanmuOverlay) refreshVisibleDanmu();
    });
  }

  bool get canShowDanmuOverlay {
    final config = widget.store.danmuConfig;
    return ready &&
        danmuSessionId > 0 &&
        config.available &&
        config.visible &&
        danmuTotalCount > 0;
  }

  bool get shouldRefreshDanmuOverlay =>
      canShowDanmuOverlay && playing && !buffering && !seekingByDrag;

  void syncDanmuTickerState() {
    if (!mounted) return;
    final shouldAnimate =
        shouldRefreshDanmuOverlay && danmuOverlayItems.value.isNotEmpty;
    if (shouldAnimate) {
      if (!danmuTicker.isAnimating) danmuTicker.repeat();
    } else if (danmuTicker.isAnimating) {
      danmuTicker.stop(canceled: false);
    }
  }

  void syncDanmuClock(Duration value) {
    danmuClockPosition = value;
    danmuClockStamp = DateTime.now();
  }

  void syncDanmuClockFromPlayer(Duration value) {
    if (!ready || !playing || buffering || seekingByDrag) {
      syncDanmuClock(value);
      return;
    }
    final driftMs = value.inMilliseconds - currentDanmuPosition.inMilliseconds;
    if (driftMs.abs() > _danmuPositionSyncThreshold.inMilliseconds) {
      syncDanmuClock(value);
    }
  }

  Duration get currentDanmuPosition {
    if (!ready || !playing || buffering || seekingByDrag) {
      return danmuClockPosition;
    }
    final elapsed = DateTime.now().difference(danmuClockStamp);
    final milliseconds =
        danmuClockPosition.inMilliseconds + elapsed.inMilliseconds;
    final maxMilliseconds = duration.inMilliseconds;
    if (maxMilliseconds > 0) {
      return Duration(
          milliseconds: milliseconds.clamp(0, maxMilliseconds).toInt());
    }
    return Duration(milliseconds: math.max(0, milliseconds).toInt());
  }

  void refreshVisibleDanmu({bool force = false}) {
    if (!mounted || !canShowDanmuOverlay) {
      clearDanmuOverlay();
      return;
    }
    final config = widget.store.danmuConfig;
    if (!force && !playing && danmuOverlayItems.value.isNotEmpty) {
      return;
    }
    final size = MediaQuery.sizeOf(context);
    final renderPosition = currentDanmuPosition;
    try {
      final items = RustCoreService.instance.danmuVisible({
        'session_id': danmuSessionId,
        'position_ms': renderPosition.inMilliseconds,
        'width': size.width,
        'height': size.height,
        'font_size': config.fontSize,
        'speed': config.speed,
        'offset_ms': config.offsetMs,
        'max_items': _danmuMaxVisibleItems,
        'max_lines': config.maxLines,
        'top_padding': 0.0,
      });
      if (!sameDanmuItems(danmuOverlayItems.value, items)) {
        danmuOverlayItems.value = items;
      }
      syncDanmuTickerState();
    } catch (error) {
      widget.store
          .addDiagnosticLog('danmu visible failed: $error', category: 'danmu');
      syncDanmuTickerState();
    }
  }

  bool sameDanmuItems(
      List<RustDanmuRenderItem> left, List<RustDanmuRenderItem> right) {
    if (identical(left, right)) return true;
    if (left.length != right.length) return false;
    for (var index = 0; index < left.length; index++) {
      final a = left[index];
      final b = right[index];
      if (a.id != b.id ||
          a.mode != b.mode ||
          a.color != b.color ||
          a.text != b.text ||
          a.timeMs != b.timeMs ||
          (a.top - b.top).abs() > 0.5 ||
          (a.mode != 1 && (a.left - b.left).abs() > 0.5) ||
          (a.textWidth - b.textWidth).abs() > 0.5) {
        return false;
      }
    }
    return true;
  }

  void attachStreams() {
    if (streamsAttached) return;
    streamsAttached = true;
    subscriptions
      ..add(player.stream.position.listen((value) {
        if (!ready) {
          if (mediaOpenCompleted &&
              !buffering &&
              hasRenderableVideo &&
              value >= Duration.zero) {
            setStateIfMounted(() {
              position = value;
              playbackPositionConfirmed = true;
            });
            syncDanmuClock(value);
            updateLoadingPercent(94, 'position confirmed');
            logVideoLoading(
                'position accepted before ready: ${value.inMilliseconds}ms');
            maybeMarkPlaybackReady();
            return;
          }
          logVideoLoading(
              'position ignored before ready: ${value.inMilliseconds}ms');
          return;
        }
        syncDanmuClockFromPlayer(value);
        position = value;
        notifyControlsChanged(throttle: true);
      }))
      ..add(player.stream.duration.listen((value) {
        if (!ready) {
          if (value > Duration.zero && value != duration) {
            setStateIfMounted(() => duration = value);
            widget.store.rememberDuration(currentItem.id, value);
            updateLoadingPercent(58, 'duration accepted');
            logVideoLoading(
                'duration accepted before ready: ${value.inMilliseconds}ms');
            return;
          }
          logVideoLoading(
              'duration ignored before ready: ${value.inMilliseconds}ms');
          return;
        }
        duration = value;
        notifyControlsChanged();
        widget.store.rememberDuration(currentItem.id, value);
      }))
      ..add(player.stream.playing.listen((value) {
        playing = value;
        unawaited(setNativePlaybackPipPlaybackState(value));
        if (!ready) {
          logVideoLoading('playing ignored before ready: $value');
          return;
        }
        syncDanmuClock(currentDanmuPosition);
        notifyControlsChanged();
        syncDanmuTickerState();
      }))
      ..add(player.stream.buffering.listen(handleBufferingChanged))
      ..add(player.stream.bufferingPercentage.listen(handleBufferingPercentage))
      ..add(player.stream.completed.listen(handlePlaybackCompleted))
      ..add(player.stream.volume.listen((value) {
        playbackVolume = value.clamp(0, 100).toDouble();
      }))
      ..add(player.stream.rate.listen((value) {
        playbackRate = value;
        notifyControlsChanged();
      }))
      ..add(player.stream.width.listen((value) {
        videoWidth = value;
        applyVideoOrientation();
        if (hasRenderableVideo) updateLoadingPercent(74, 'video size');
        maybeMarkPlaybackReady();
      }))
      ..add(player.stream.height.listen((value) {
        videoHeight = value;
        applyVideoOrientation();
        if (hasRenderableVideo) updateLoadingPercent(74, 'video size');
        maybeMarkPlaybackReady();
      }))
      ..add(player.stream.tracks
          .listen((value) => setStateIfMounted(() => availableTracks = value)))
      ..add(player.stream.track
          .listen((value) => setStateIfMounted(() => selectedTrack = value)))
      ..add(player.stream.log.listen((value) {
        final message =
            'mpv ${value.prefix} ${value.level}: ${value.text.trim()}';
        logVideoLoading(message);
      }))
      ..add(player.stream.error.listen(handlePlayerError));
  }

  Future<void> init(
      {bool automaticRetry = true, bool resetCodecRetry = true}) async {
    final attempt = ++openAttempt;
    final saved = rememberedPositionMsFor(currentItem);
    final rememberedDuration = rememberedDurationMsFor(currentItem);
    if (resetCodecRetry) {
      transientCodecRetryCount = 0;
      softwareDecoderFallback = false;
    }
    final initialBufferingPercentage =
        resetCodecRetry ? 0.0 : bufferingPercentage.clamp(0, 100).toDouble();
    try {
      setState(() {
        error = null;
        ready = false;
        mediaOpenCompleted = false;
        playbackPositionConfirmed = false;
        voConfigured = false;
        pausedForCache = false;
        playing = true;
        buffering = true;
        loadingVisible = true;
        position = saved > 0 ? Duration(milliseconds: saved) : Duration.zero;
        duration = rememberedDuration > 0
            ? Duration(milliseconds: rememberedDuration)
            : Duration.zero;
        bufferingPercentage = initialBufferingPercentage;
        videoWidth = null;
        videoHeight = null;
        backendSelected = !Platform.isAndroid;
      });
      await applyRememberedOrientation();
      if (saved > 0) {
        final savedPosition = Duration(milliseconds: saved);
        syncDanmuClock(savedPosition);
      }
      final playback = !openedOnce && currentItem.id == widget.item.id
          ? widget.playback ?? await resolvePlayback(currentItem)
          : await resolvePlayback(currentItem);
      final uri = playback.uri;
      final previousUsingMedia3 = usingMedia3;
      final isTvboxPlayback = currentItem.sourceId == 'tvbox';
      var detectedDolbyVision = dolbyVisionCache[currentItem.id];
      final needsDolbyVisionDetection =
          !isTvboxPlayback && detectedDolbyVision == null;
      if (previousUsingMedia3) {
        await appChannel.invokeMethod<void>('media3Release');
      }
      if (!mounted || attempt != openAttempt) return;
      setState(() {
        usingMedia3 = Platform.isAndroid &&
            shouldUseMedia3OnAndroid(
              isTvboxPlayback,
              detectedDolbyVision == true,
            );
        backendSelected = !Platform.isAndroid || !needsDolbyVisionDetection;
        mpvLoadingPropertiesUsable = false;
        media3Ended = false;
        media3Subtitle = '';
      });
      updateLoadingPercent(
          math.max(initialBufferingPercentage, 12), 'open start');
      logVideoLoading(
          'open start attempt=$attempt backend=${usingMedia3 ? 'media3' : 'libmpv'} item=${currentItem.id} uri=$uri saved=${saved}ms');
      if (usingMedia3) {
        await appChannel.invokeMethod<void>('media3Open', {
          'uri': uri,
          'headers': playback.headers,
          'startMs': saved,
        });
        await media3Command('fit', fitMode.name);
        if (attempt == openAttempt) {
          setStateIfMounted(() => mediaOpenCompleted = true);
          updateLoadingPercent(42, 'media3 prepared');
        }
        return;
      }
      attachStreams();
      await attachMpvLoadingProperties();
      await configureDecoder();
      if (openedOnce) {
        await player.stop();
        await Future<void>.delayed(const Duration(milliseconds: 120));
      }
      await player.open(
        Media(
          uri,
          httpHeaders: playback.headers.isEmpty ? null : playback.headers,
          start: saved > 0 ? Duration(milliseconds: saved) : null,
        ),
        play: !needsDolbyVisionDetection,
      );
      logVideoLoading(
          'open returned attempt=$attempt stateBuffering=${player.state.buffering} statePlaying=${player.state.playing} width=${player.state.width} height=${player.state.height} position=${player.state.position.inMilliseconds}ms duration=${player.state.duration.inMilliseconds}ms');
      openedOnce = true;
      if (needsDolbyVisionDetection) {
        detectedDolbyVision = await inspectLibmpvDolbyVision(attempt);
        if (detectedDolbyVision != null) {
          dolbyVisionCache[currentItem.id] = detectedDolbyVision;
        }
        if (!mounted || attempt != openAttempt) return;
        if (Platform.isAndroid && detectedDolbyVision == true) {
          await player.stop();
          setState(() {
            usingMedia3 = true;
            backendSelected = true;
          });
          logVideoLoading(
              'backend switch attempt=$attempt backend=media3 reason=libmpv-dolby-vision');
          await appChannel.invokeMethod<void>('media3Open', {
            'uri': uri,
            'headers': playback.headers,
            'startMs': saved,
          });
          await media3Command('fit', fitMode.name);
          if (attempt == openAttempt) {
            setStateIfMounted(() => mediaOpenCompleted = true);
            updateLoadingPercent(42, 'media3 prepared');
          }
          return;
        }
        setState(() => backendSelected = true);
        await player.play();
        logVideoLoading(
            'backend selected attempt=$attempt backend=libmpv detected=$detectedDolbyVision');
      }
      if (attempt == openAttempt) {
        setStateIfMounted(() {
          buffering = player.state.buffering;
          mediaOpenCompleted = true;
        });
        updateLoadingPercent(42, 'open returned');
        maybeMarkPlaybackReady(attempt: attempt);
      }
    } catch (e) {
      if (automaticRetry && canRetryTransientCodec(e)) {
        logVideoLoading('open transient codec retry attempt=$attempt error=$e');
        await retryTransientCodec(attempt);
        return;
      }
      logVideoLoading('open failed attempt=$attempt error=$e');
      if (attempt == openAttempt) setStateIfMounted(() => error = e);
    }
  }

  Future<bool?> inspectLibmpvDolbyVision(int attempt) async {
    try {
      final native = player.platform as dynamic;
      var stableVideoReads = 0;
      for (var read = 0; read < 150; read++) {
        if (attempt != openAttempt) return null;
        final count = int.tryParse(
                (await native.getProperty('track-list/count'))?.toString() ??
                    '') ??
            0;
        var videoReady = false;
        final tracks = <Map<String, String>>[];
        for (var index = 0; index < count; index++) {
          final type = (await native.getProperty('track-list/$index/type'))
                  ?.toString()
                  .trim() ??
              '';
          if (type != 'video') continue;
          final codec = (await native.getProperty('track-list/$index/codec'))
                  ?.toString()
                  .trim() ??
              '';
          final profile = (await native
                      .getProperty('track-list/$index/dolby-vision-profile'))
                  ?.toString()
                  .trim() ??
              '';
          final level =
              (await native.getProperty('track-list/$index/dolby-vision-level'))
                      ?.toString()
                      .trim() ??
                  '';
          tracks.add({
            'index': '$index',
            'codec': codec,
            'profile': profile,
            'level': level,
          });
          if (isLibmpvDolbyVisionTrack(profile, level)) {
            logVideoLoading(
                'libmpv metadata inspector: detected=true tracks=${jsonEncode(tracks)}');
            return true;
          }
          videoReady |= codec.isNotEmpty;
        }
        stableVideoReads = videoReady ? stableVideoReads + 1 : 0;
        if (stableVideoReads >= 5) {
          logVideoLoading(
              'libmpv metadata inspector: detected=false tracks=${jsonEncode(tracks)}');
          return false;
        }
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      logVideoLoading('libmpv metadata inspector timed out');
      return null;
    } catch (error) {
      logVideoLoading('libmpv metadata inspector failed: $error');
      return null;
    }
  }

  Future<void> configureDecoder() async {
    if (usingMedia3) return;
    try {
      final native = player.platform as dynamic;
      for (final entry in mpvAdvancedOptions(
        preset: widget.store.mpvAdvancedPreset,
        deviceClass: currentDeviceClass,
        softwareDecoderFallback: softwareDecoderFallback,
        customOptions: widget.store.effectiveMpvAdvancedOptions(),
      ).entries) {
        await native.setProperty(entry.key, entry.value);
      }
      await applyPlaybackLoadMode(reduced: competingWindowActive);
    } catch (_) {
      // Non-native platforms or older media_kit backends may not expose mpv properties.
    }
  }

  Future<void> applyPlaybackLoadMode({required bool reduced}) async {
    if (usingMedia3) return;
    try {
      final native = player.platform as dynamic;
      final options = widget.store.effectiveMpvAdvancedOptions();
      await native.setProperty(
        'video-sync',
        options['video-sync'] ?? 'audio',
      );
      await native.setProperty(
        'framedrop',
        options['framedrop'] ?? 'vo',
      );
    } catch (_) {
      // Best-effort: playback must keep working if mpv properties are unavailable.
    }
  }

  Future<void> attachMpvLoadingProperties() async {
    if (usingMedia3) return;
    if (mpvLoadingPropertiesAttached) return;
    mpvLoadingPropertiesAttached = true;
    try {
      final native = player.platform as dynamic;
      var observedAny = false;
      await native.observeProperty(
        'vo-configured',
        (String value) async {
          final configured = mpvBoolValue(value);
          if (lastLoggedVoConfiguredValue != value) {
            lastLoggedVoConfiguredValue = value;
            logVideoLoading('mpv vo-configured: $value');
          }
          if (!mounted) return;
          if (voConfigured != configured) {
            setStateIfMounted(() => voConfigured = configured);
          }
          if (configured) updateLoadingPercent(82, 'vo configured');
          maybeMarkPlaybackReady();
        },
      );
      observedAny = true;
      await native.observeProperty(
        'paused-for-cache',
        (String value) async {
          final paused = mpvBoolValue(value);
          if (lastLoggedPausedForCacheValue != value) {
            lastLoggedPausedForCacheValue = value;
            logVideoLoading('mpv paused-for-cache: $value');
          }
          if (!mounted) return;
          if (pausedForCache != paused) {
            setStateIfMounted(() => pausedForCache = paused);
          }
          if (!paused) updateLoadingPercent(88, 'cache resumed');
          maybeMarkPlaybackReady();
        },
      );
      observedAny = true;
      if (mounted && observedAny) {
        final currentVoConfigured = await native.getProperty('vo-configured');
        final currentPausedForCache =
            await native.getProperty('paused-for-cache');
        logVideoLoading(
            'mpv loading initial: vo-configured=$currentVoConfigured paused-for-cache=$currentPausedForCache');
        setStateIfMounted(() {
          mpvLoadingPropertiesUsable = true;
          voConfigured = mpvBoolValue(currentVoConfigured);
          pausedForCache = mpvBoolValue(currentPausedForCache);
        });
      }
    } catch (error) {
      if (mounted) {
        setStateIfMounted(() {
          mpvLoadingPropertiesUsable = false;
          pausedForCache = false;
        });
      }
      logVideoLoading('mpv loading property observe unavailable: $error');
    }
  }

  Future<void> unobserveMpvLoadingProperties() async {
    if (!mpvLoadingPropertiesAttached) return;
    try {
      final instance = _player;
      if (instance == null) return;
      final native = instance.platform as dynamic;
      await native.unobserveProperty('vo-configured');
      await native.unobserveProperty('paused-for-cache');
    } catch (_) {}
  }

  Future<void> saveCurrentProgress() async {
    if (!shouldPersistPlaybackProgress(
      ready: ready,
      positionConfirmed: playbackPositionConfirmed,
      positionMs: position.inMilliseconds,
    )) {
      logVideoLoading(
          'progress save skipped: ready=$ready confirmed=$playbackPositionConfirmed position=${position.inMilliseconds}ms duration=${duration.inMilliseconds}ms');
      return;
    }
    await widget.store.updateProgress(currentItem.id, position, duration);
  }

  @override
  void dispose() {
    widget.store.removeListener(handleStoreChanged);
    unawaited(saveCurrentProgress());
    statusTimer?.cancel();
    loadingHideTimer?.cancel();
    controlsHideTimer?.cancel();
    danmuRenderTimer?.cancel();
    verticalControlOverlayTimer?.cancel();
    landscapeSensorTimer?.cancel();
    clearDanmuSession();
    danmuTicker.dispose();
    danmuOverlayItems.dispose();
    controlsVisible.dispose();
    controlsRevision.dispose();
    danmuSearchController.dispose();
    danmuSearchEpisodeController.dispose();
    unawaited(setPlaybackWindowFullscreen(false));
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.manual,
        overlays: SystemUiOverlay.values);
    appChannel.setMethodCallHandler(null);
    unawaited(setNativePlaybackPipEnabled(false));
    unawaited(setNativePlaybackOrientationMode('off'));
    if (Platform.isAndroid) {
      unawaited(appChannel.invokeMethod<void>('media3Release'));
    }
    for (final subscription in subscriptions) {
      subscription.cancel();
    }
    unawaited(unobserveMpvLoadingProperties());
    _player?.dispose();
    super.dispose();
  }

  Future<void> setNativePlaybackOrientationMode(String mode) async {
    if (!Platform.isAndroid) return;
    try {
      await appChannel.invokeMethod<void>(
        'setPlaybackOrientationMode',
        {'mode': mode},
      );
    } catch (error) {
      widget.store.addDiagnosticLog(
          'native playback orientation failed: $mode $error',
          category: 'player');
    }
  }

  Future<void> setNativePlaybackPipEnabled(bool enabled) async {
    if (!Platform.isAndroid) return;
    try {
      await appChannel.invokeMethod<void>(
        'setPlaybackPipEnabled',
        {'enabled': enabled},
      );
    } catch (error) {
      widget.store.addDiagnosticLog(
          'native playback pip failed: $enabled $error',
          category: 'player');
    }
  }

  Future<void> setNativePlaybackPipPlaybackState(bool isPlaying) async {
    if (!Platform.isAndroid) return;
    try {
      await appChannel.invokeMethod<void>(
        'setPlaybackPipPlaybackState',
        {'playing': isPlaying},
      );
    } catch (error) {
      widget.store.addDiagnosticLog(
          'native playback pip state failed: $isPlaying $error',
          category: 'player');
    }
  }

  Future<dynamic> handleAppChannelCall(MethodCall call) async {
    switch (call.method) {
      case 'media3StateChanged':
        if (usingMedia3 && call.arguments is Map) {
          handleMedia3State(Map<String, dynamic>.from(call.arguments as Map));
        }
        return null;
      case 'media3Diagnostic':
        widget.store.addDiagnosticLog(
          'media3 ${call.arguments}',
          category: 'player',
        );
        return null;
      case 'pipModeChanged':
        final arguments = call.arguments;
        final enabled = arguments == true ||
            arguments is Map && arguments['enabled'] == true;
        handlePictureInPictureModeChanged(enabled);
        return null;
      case 'pipTogglePlayback':
        await togglePlaybackFromPip();
        return null;
      case 'windowFocusChanged':
        final arguments = call.arguments;
        final focused = arguments == true ||
            arguments is Map && arguments['focused'] == true;
        windowFocusLost = !focused;
        await applyCompetingWindowMode('window focus');
        return null;
      case 'multiWindowModeChanged':
        final arguments = call.arguments;
        final enabled = arguments == true ||
            arguments is Map && arguments['enabled'] == true;
        multiWindowActive = enabled;
        await applyCompetingWindowMode('multi-window');
        return null;
      default:
        throw MissingPluginException(call.method);
    }
  }

  void handleMedia3State(Map<String, dynamic> state) {
    if (!mounted || !usingMedia3) return;
    final nextPosition =
        Duration(milliseconds: (state['positionMs'] as num?)?.toInt() ?? 0);
    final nextDuration =
        Duration(milliseconds: (state['durationMs'] as num?)?.toInt() ?? 0);
    final nextPlaying = state['playing'] == true;
    final nextBuffering = state['buffering'] == true;
    final firstFrame = state['firstFrame'] == true;
    final nextWidth = (state['width'] as num?)?.toInt() ?? 0;
    final nextHeight = (state['height'] as num?)?.toInt() ?? 0;
    final nextSubtitle = state['subtitle'] as String? ?? '';
    final dimensionsChanged = nextWidth > 0 &&
        nextHeight > 0 &&
        (videoWidth != nextWidth || videoHeight != nextHeight);
    final subtitleChanged = media3Subtitle != nextSubtitle;
    final durationChanged =
        nextDuration > Duration.zero && duration != nextDuration;

    position = nextPosition;
    if (durationChanged) {
      duration = nextDuration;
      widget.store.rememberDuration(currentItem.id, nextDuration);
    }
    if (playing != nextPlaying) {
      playing = nextPlaying;
      unawaited(setNativePlaybackPipPlaybackState(nextPlaying));
      syncDanmuClock(currentDanmuPosition);
      syncDanmuTickerState();
    }
    if (dimensionsChanged) {
      videoWidth = nextWidth;
      videoHeight = nextHeight;
      unawaited(applyVideoOrientation());
      updateLoadingPercent(74, 'media3 video size');
    }
    if (firstFrame) {
      playbackPositionConfirmed = true;
      voConfigured = true;
      updateLoadingPercent(94, 'media3 first frame');
    }
    if (buffering != nextBuffering) {
      handleBufferingChanged(nextBuffering);
    }
    handleBufferingPercentage(
        (state['bufferingPercent'] as num?)?.toDouble() ?? 0);
    updateMedia3Tracks(state['tracks']);
    if (subtitleChanged) media3Subtitle = nextSubtitle;

    final nextError = state['error'] as String?;
    if (nextError != null && nextError.isNotEmpty && error != nextError) {
      logVideoLoading('media3 player error: $nextError');
      setStateIfMounted(() => error = nextError);
    }
    final ended = state['ended'] == true;
    if (ended && !media3Ended) unawaited(handlePlaybackCompleted(true));
    media3Ended = ended;
    maybeMarkPlaybackReady();
    if (ready) {
      syncDanmuClockFromPlayer(nextPosition);
      notifyControlsChanged(throttle: true);
    }
    if (dimensionsChanged || subtitleChanged) setStateIfMounted(() {});
  }

  void updateMedia3Tracks(Object? value) {
    if (value is! Map) return;
    final data = Map<String, dynamic>.from(value);
    List<Map<String, dynamic>> maps(String key) =>
        (data[key] as List? ?? const [])
            .whereType<Map>()
            .map((item) => Map<String, dynamic>.from(item))
            .toList();
    final audio = [
      for (final item in maps('audio'))
        AudioTrack(
          item['id'] as String,
          item['title'] as String?,
          item['language'] as String?,
          codec: item['codec'] as String?,
        ),
    ];
    final subtitles = [
      for (final item in maps('subtitle'))
        SubtitleTrack(
          item['id'] as String,
          item['title'] as String?,
          item['language'] as String?,
          codec: item['codec'] as String?,
        ),
    ];
    final nextTracks = Tracks(audio: audio, subtitle: subtitles);
    final audioId = data['selectedAudio'] as String? ?? 'auto';
    final subtitleId = data['selectedSubtitle'] as String? ?? 'no';
    AudioTrack selectedAudio() => audio.firstWhere(
          (track) => track.id == audioId,
          orElse: () => const AudioTrack('auto', null, null),
        );
    SubtitleTrack selectedSubtitle() => subtitles.firstWhere(
          (track) => track.id == subtitleId,
          orElse: () => const SubtitleTrack('no', null, null),
        );
    final nextSelected = Track(
      audio: selectedAudio(),
      subtitle: selectedSubtitle(),
    );
    if (nextTracks == availableTracks && nextSelected == selectedTrack) return;
    setStateIfMounted(() {
      availableTracks = nextTracks;
      selectedTrack = nextSelected;
    });
  }

  Future<void> applyCompetingWindowMode(String reason) async {
    if (!mounted || inPictureInPicture) return;
    final active = windowFocusLost || multiWindowActive;
    if (active == competingWindowActive) return;
    competingWindowActive = active;
    syncDanmuClock(currentDanmuPosition);
    syncDanmuTickerState();
    logVideoLoading(
        '$reason ${active ? 'active' : 'cleared'}: ${active ? 'reduce' : 'restore'} playback load');
    await applyPlaybackLoadMode(reduced: active);
  }

  void handlePictureInPictureModeChanged(bool enabled) {
    controlsHideTimer?.cancel();
    verticalControlOverlayTimer?.cancel();
    if (enabled) {
      windowFocusLost = false;
      multiWindowActive = false;
      competingWindowActive = false;
      unawaited(applyPlaybackLoadMode(reduced: false));
      setControlsVisible(false);
    }
    setStateIfMounted(() {
      inPictureInPicture = enabled;
      if (enabled) {
        episodePanelOpen = false;
        episodePanelClosing = false;
        danmuPanelOpen = false;
        danmuPanelClosing = false;
        danmuSearchPanelOpen = false;
        danmuSearchPanelClosing = false;
        loadingVisible = false;
        dragPreviewPosition = null;
        seekingByDrag = false;
        verticalControlKind = null;
        verticalControlLabel = null;
      }
    });
    syncDanmuTickerState();
  }

  void setStateIfMounted(VoidCallback update) {
    if (mounted) setState(update);
  }

  void notifyControlsChanged({bool throttle = false}) {
    if (mounted && controlsVisible.value) {
      if (throttle) {
        final nowMs = DateTime.now().millisecondsSinceEpoch;
        if (nowMs - lastThrottledControlsNotifyMs < 200) return;
        lastThrottledControlsNotifyMs = nowMs;
      }
      controlsRevision.value++;
    }
  }

  void logVideoLoading(String message) {
    widget.store.addDiagnosticLog(message, category: 'player');
  }

  void showLoadingOverlay() {
    loadingHideTimer?.cancel();
    if (!loadingVisible) {
      setStateIfMounted(() => loadingVisible = true);
    }
  }

  void hideLoadingOverlay() {
    loadingHideTimer?.cancel();
    loadingHideTimer = Timer(const Duration(milliseconds: 260), () {
      setStateIfMounted(() => loadingVisible = false);
    });
  }

  void handleBufferingChanged(bool value) {
    logVideoLoading(
        'buffering changed: $value ready=$ready openCompleted=$mediaOpenCompleted width=$videoWidth height=$videoHeight');
    syncDanmuClock(currentDanmuPosition);
    setStateIfMounted(() => buffering = value);
    if (!value) updateLoadingPercent(86, 'buffering false');
    syncDanmuTickerState();
    if (value) {
      showLoadingOverlay();
    } else if (ready) {
      hideLoadingOverlay();
    } else {
      maybeMarkPlaybackReady();
    }
  }

  void handleBufferingPercentage(double value) {
    if (!value.isFinite) return;
    final percent = value.clamp(0, 100).toDouble().roundToDouble();
    final previous = lastLoggedBufferingPercent;
    if (previous == percent) return;
    if (previous != null &&
        (percent - previous).abs() < 10 &&
        percent != 0 &&
        percent != 100) {
      return;
    }
    lastLoggedBufferingPercent = percent;
    logVideoLoading('cache buffering percent: ${percent.toStringAsFixed(1)}');
  }

  bool get hasRenderableVideo =>
      (videoWidth ?? 0) > 0 && (videoHeight ?? 0) > 0;

  bool mpvBoolValue(Object? value) {
    final text = '$value'.trim().toLowerCase();
    return text == 'yes' || text == 'true' || text == '1';
  }

  void updateLoadingPercent(double value, String reason) {
    if (!mounted || ready) return;
    final next = value.clamp(0, 99).toDouble();
    if (next <= bufferingPercentage) return;
    setStateIfMounted(() => bufferingPercentage = next);
    logVideoLoading('loading milestone: ${next.toStringAsFixed(1)} $reason');
  }

  void maybeMarkPlaybackReady({int? attempt}) {
    if (!mounted || ready) return;
    if (attempt != null && attempt != openAttempt) return;
    if (!mediaOpenCompleted || buffering || pausedForCache) return;
    if (mpvLoadingPropertiesUsable && !voConfigured) return;
    if (!hasRenderableVideo) return;
    if (!playbackPositionConfirmed) return;
    final currentError = error;
    if (currentError != null &&
        !(isRecoverableNetworkReadError(currentError) && playbackLooksAlive)) {
      return;
    }
    final state = usingMedia3 ? null : player.state;
    setState(() {
      error = null;
      ready = true;
      if (state != null) {
        playing = state.playing;
        position = state.position;
        if (state.duration > Duration.zero) duration = state.duration;
      }
      bufferingPercentage = 100;
    });
    logVideoLoading(
        'ready: playing=$playing position=${position.inMilliseconds}ms duration=${duration.inMilliseconds}ms width=$videoWidth height=$videoHeight buffer=${bufferingPercentage.toStringAsFixed(1)}');
    syncDanmuClock(position);
    refreshVisibleDanmu();
    syncDanmuTickerState();
    hideLoadingOverlay();
    scheduleControlsAutoHide();
  }

  bool isTransientCodecError(Object value) {
    final text = value.toString().toLowerCase();
    return text.contains('could not open codec') ||
        text.contains('failed to initialize a decoder');
  }

  bool canRetryTransientCodec(Object value) =>
      isTransientCodecError(value) && transientCodecRetryCount < 2;

  bool isRecoverableNetworkReadError(Object value) {
    final text = value.toString().toLowerCase();
    return text.contains('ffurl_read returned') ||
        text.contains('tcp:') ||
        text.contains('connection timed out') ||
        text.contains('operation timed out');
  }

  bool get playbackLooksAlive {
    final state = usingMedia3 ? null : player.state;
    final hasPosition = position > Duration.zero ||
        (state != null && state.position > Duration.zero);
    return hasRenderableVideo &&
        (ready || playing || (state?.playing ?? false) || hasPosition);
  }

  Future<void> retryTransientCodec(int attempt) async {
    transientCodecRetryCount++;
    softwareDecoderFallback = true;
    logVideoLoading(
        'transient codec retry: sourceAttempt=$attempt retry=$transientCodecRetryCount softwareFallback=$softwareDecoderFallback');
    await Future<void>.delayed(const Duration(milliseconds: 450));
    if (!mounted || attempt != openAttempt) return;
    await stopPlayback();
    await init(automaticRetry: true, resetCodecRetry: false);
  }

  Future<void> handlePlayerError(Object value) async {
    final attempt = openAttempt;
    if (canRetryTransientCodec(value)) {
      logVideoLoading('player stream error retryable attempt=$attempt: $value');
      await retryTransientCodec(attempt);
      return;
    }
    if (isRecoverableNetworkReadError(value) && playbackLooksAlive) {
      logVideoLoading(
          'player stream recoverable during active playback attempt=$attempt: $value');
      if (attempt == openAttempt && error != null) {
        setStateIfMounted(() => error = null);
      }
      return;
    }
    logVideoLoading('player stream error attempt=$attempt: $value');
    if (attempt == openAttempt) setStateIfMounted(() => error = value);
  }

  Future<void> applyVideoOrientation() async {
    if (orientationLocked) return;
    final width = videoWidth;
    final height = videoHeight;
    if (width == null || height == null || width <= 0 || height <= 0) return;

    orientationLocked = true;
    final landscape = width >= height;
    if (landscape) {
      await applyLandscapeVideoOrientation();
    } else {
      landscapeSensorTimer?.cancel();
      await setNativePlaybackOrientationMode('portrait');
      await SystemChrome.setPreferredOrientations(
          [DeviceOrientation.portraitUp]);
    }
    unawaited(widget.store.rememberFolderOrientation(currentItem, landscape));
  }

  Future<void> applyRememberedOrientation() async {
    final remembered =
        widget.store.folderOrientations[mediaFolderKey(currentItem)];
    orientationLocked = false;
    if (remembered == 'landscape') {
      await applyLandscapeVideoOrientation();
    } else {
      landscapeSensorTimer?.cancel();
      await setNativePlaybackOrientationMode('portrait');
      await SystemChrome.setPreferredOrientations(
          [DeviceOrientation.portraitUp]);
    }
  }

  Future<void> applyLandscapeVideoOrientation() async {
    landscapeSensorTimer?.cancel();
    await setNativePlaybackOrientationMode('landscape');
    await SystemChrome.setPreferredOrientations(
        [DeviceOrientation.landscapeLeft]);
  }

  void beginSeekDrag(DragStartDetails details) {
    if (controlsLocked) return;
    markControlsInteraction();
    final anchor = currentDanmuPosition;
    syncDanmuClock(anchor);
    dragDistance = 0;
    dragStartPosition = anchor;
    seekingByDrag = false;
  }

  void updateSeekDrag(DragUpdateDetails details, double width) {
    if (controlsLocked) return;
    if (duration == Duration.zero || width <= 0) return;
    dragDistance += details.delta.dx;
    if (!seekingByDrag && dragDistance.abs() < 18) return;
    seekingByDrag = true;
    syncDanmuTickerState();
    final maxSeekMs =
        (duration.inMilliseconds * 0.18).clamp(5000, 120000).toInt();
    final offsetMs = (dragDistance / width * maxSeekMs).round();
    final nextMs = (dragStartPosition.inMilliseconds + offsetMs)
        .clamp(0, duration.inMilliseconds);
    dragPreviewPosition = Duration(milliseconds: nextMs.toInt());
    notifyControlsChanged();
  }

  Future<void> endSeekDrag() async {
    if (controlsLocked) return;
    final target = seekingByDrag ? dragPreviewPosition : null;
    seekingByDrag = false;
    dragPreviewPosition = null;
    notifyControlsChanged();
    if (target != null && duration > Duration.zero) {
      syncDanmuClock(target);
      clearDanmuOverlay();
      await seekPlayback(target);
    }
    syncDanmuTickerState();
    scheduleControlsAutoHide();
  }

  void beginSliderSeek(double value) {
    if (controlsLocked || duration == Duration.zero) return;
    markControlsInteraction();
    syncDanmuClock(currentDanmuPosition);
    setStateIfMounted(() {
      seekingByDrag = true;
      dragPreviewPosition = Duration(milliseconds: value.round());
    });
    syncDanmuTickerState();
    notifyControlsChanged();
  }

  void updateSliderSeek(double value) {
    if (controlsLocked || duration == Duration.zero) return;
    markControlsInteraction();
    setStateIfMounted(() {
      seekingByDrag = true;
      dragPreviewPosition = Duration(milliseconds: value.round());
    });
    notifyControlsChanged(throttle: true);
  }

  Future<void> endSliderSeek(double value) async {
    if (controlsLocked || duration == Duration.zero) return;
    final target = Duration(milliseconds: value.round());
    setStateIfMounted(() {
      seekingByDrag = false;
      dragPreviewPosition = null;
    });
    notifyControlsChanged();
    syncDanmuClock(target);
    clearDanmuOverlay();
    await seekPlayback(target);
    syncDanmuTickerState();
    scheduleControlsAutoHide();
  }

  bool get verticalControlAvailable =>
      !inPictureInPicture &&
      !controlsLocked &&
      !episodePanelOpen &&
      !danmuPanelOpen &&
      !danmuSearchPanelOpen;

  bool verticalControlPointAllowed(Offset localPosition, Size size) {
    if (!verticalControlAvailable || size.width <= 0 || size.height <= 0) {
      return false;
    }
    final deadZone =
        (size.height * _verticalControlEdgeDeadZoneRatio).clamp(56.0, 120.0);
    return localPosition.dy >= deadZone &&
        localPosition.dy <= size.height - deadZone;
  }

  void beginVerticalControlDrag(DragStartDetails details, Size size) {
    if (!verticalControlPointAllowed(details.localPosition, size)) return;
    verticalControlKind = details.localPosition.dx < size.width / 2
        ? VerticalControlKind.volume
        : VerticalControlKind.brightness;
    markControlsInteraction();
    unawaited(applyVerticalControlDelta(verticalControlKind!, 0));
  }

  void updateVerticalControlDrag(DragUpdateDetails details, double height) {
    final kind = verticalControlKind;
    if (kind == null || !verticalControlAvailable || height <= 0) return;
    final delta = (-details.delta.dy / height * _verticalControlSensitivity)
        .clamp(-0.16, 0.16)
        .toDouble();
    if (delta == 0) return;
    unawaited(applyVerticalControlDelta(kind, delta));
  }

  void endVerticalControlDrag() {
    verticalControlKind = null;
  }

  Future<void> applyVerticalControlDelta(
      VerticalControlKind kind, double delta) async {
    if (kind == VerticalControlKind.volume) {
      final next = (delta == 0 ? playbackVolume : playbackVolume + delta * 100)
          .clamp(0, 100)
          .toDouble();
      playbackVolume = next;
      await setPlaybackVolume(next);
      if (!mounted) return;
      showVerticalControlOverlay(kind, next / 100);
      return;
    }
    if (!Platform.isAndroid) return;
    try {
      final result = await appChannel.invokeMapMethod<String, dynamic>(
        'adjustPlaybackControl',
        {'kind': kind.name, 'delta': delta},
      );
      if (!mounted || result == null) return;
      final value = (result['value'] as num?)?.toDouble();
      if (value == null) return;
      showVerticalControlOverlay(kind, value.clamp(0.0, 1.0).toDouble());
    } catch (error) {
      widget.store.addDiagnosticLog('playback vertical control failed: $error',
          category: 'player');
    }
  }

  void showVerticalControlOverlay(VerticalControlKind kind, double level) {
    verticalControlOverlayTimer?.cancel();
    setStateIfMounted(() {
      verticalControlLabel = kind == VerticalControlKind.volume ? '音量' : '亮度';
      verticalControlLevel = level;
    });
    verticalControlOverlayTimer = Timer(const Duration(milliseconds: 700), () {
      if (!mounted) return;
      setState(() => verticalControlLabel = null);
    });
  }

  void togglePlayback() {
    if (controlsLocked) return;
    markControlsInteraction();
    syncDanmuClock(currentDanmuPosition);
    unawaited(setNativePlaybackPipPlaybackState(!playing));
    unawaited(playing ? pausePlayback() : playPlayback());
  }

  Future<void> togglePlaybackFromPip() async {
    syncDanmuClock(currentDanmuPosition);
    final nextPlaying = !playing;
    if (playing) {
      await pausePlayback();
    } else {
      await playPlayback();
    }
    unawaited(setNativePlaybackPipPlaybackState(nextPlaying));
  }

  BoxFit get videoFit => switch (fitMode) {
        VideoFitMode.contain => BoxFit.contain,
        VideoFitMode.cover => BoxFit.cover,
        VideoFitMode.none => BoxFit.none,
        VideoFitMode.fill => BoxFit.fill,
      };

  Future<void> toggleFullscreen() async {
    final nextVisible = fullscreen;
    setControlsVisible(nextVisible);
    if (!nextVisible) {
      controlsHideTimer?.cancel();
    } else {
      scheduleControlsAutoHide();
    }
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  Future<void> togglePlaybackFullscreen() async {
    if (Platform.isWindows) {
      await setPlaybackWindowFullscreen(!playbackWindowFullscreen);
      return;
    }
    await toggleFullscreen();
  }

  Future<void> setPlaybackWindowFullscreen(bool enabled) async {
    if (!Platform.isWindows) return;
    try {
      final active = await appChannel.invokeMethod<bool>(
            'setFullscreen',
            enabled,
          ) ??
          enabled;
      setStateIfMounted(() => playbackWindowFullscreen = active);
      notifyControlsChanged();
    } catch (_) {}
  }

  Future<void> handleEscapePressed() async {
    if (Platform.isWindows && playbackWindowFullscreen) {
      await setPlaybackWindowFullscreen(false);
      return;
    }
    if (fullscreen) {
      await toggleFullscreen();
      return;
    }
    if (mounted) Navigator.of(context).maybePop();
  }

  void setControlsVisible(bool visible) {
    fullscreen = !visible;
    if (controlsVisible.value != visible) {
      controlsVisible.value = visible;
    }
    if (visible) unawaited(updatePlayerStatus());
  }

  void scheduleControlsAutoHide() {
    controlsHideTimer?.cancel();
    if (fullscreen ||
        episodePanelOpen ||
        danmuPanelOpen ||
        danmuSearchPanelOpen) {
      return;
    }
    controlsHideTimer = Timer(const Duration(seconds: 5), () {
      if (!mounted ||
          episodePanelOpen ||
          danmuPanelOpen ||
          danmuSearchPanelOpen) {
        return;
      }
      setControlsVisible(false);
    });
  }

  void markControlsInteraction() {
    if (!fullscreen && !episodePanelOpen && !danmuPanelOpen) {
      scheduleControlsAutoHide();
    }
  }

  void setFitMode(VideoFitMode value) {
    setStateIfMounted(() => fitMode = value);
    if (usingMedia3) unawaited(media3Command('fit', value.name));
    scheduleControlsAutoHide();
  }

  Future<void> showFitModes(BuildContext anchorContext) async {
    final selected = await showControlMenu<VideoFitMode>(
      anchorContext: anchorContext,
      selectedValue: fitMode,
      options: const [
        (value: VideoFitMode.contain, label: '内容居中'),
        (value: VideoFitMode.cover, label: '居中裁切'),
        (value: VideoFitMode.none, label: '原始尺寸'),
        (value: VideoFitMode.fill, label: '铺满屏幕'),
      ],
    );
    if (selected != null) setFitMode(selected);
    scheduleControlsAutoHide();
  }

  void startStatusTimer() {
    updatePlayerStatus();
    statusTimer =
        Timer.periodic(const Duration(seconds: 5), (_) => updatePlayerStatus());
  }

  Future<void> updatePlayerStatus() async {
    if (!Platform.isAndroid) return;
    if (!controlsVisible.value || controlsLocked) return;
    try {
      final status =
          await appChannel.invokeMapMethod<String, dynamic>('playerStatus');
      if (status == null) return;
      final rx = (status['rxBytes'] as num?)?.toInt();
      final previous = lastRxBytes;
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      final previousSampleMs = lastRxSampleMs;
      lastRxBytes = rx;
      lastRxSampleMs = nowMs;
      final nextBattery = (status['battery'] as num?)?.toInt();
      if (nextBattery != null && nextBattery >= 0) {
        battery = nextBattery.clamp(0, 100);
      }
      charging = status['charging'] == true;
      network = status['network'] as String? ?? network;
      if (rx != null &&
          previous != null &&
          rx >= previous &&
          previousSampleMs != null) {
        networkSpeed = formatNetworkSpeed(
            networkBytesPerSecond(rx - previous, nowMs - previousSampleMs));
      }
      notifyControlsChanged();
    } catch (_) {
      // Status decoration is best-effort; playback should never depend on it.
    }
  }

  String formatNetworkSpeed(int bytesPerSecond) {
    if (bytesPerSecond < 1024) return '$bytesPerSecond B/s';
    final kb = bytesPerSecond / 1024;
    if (kb < 1024) return '${kb.toStringAsFixed(0)} KB/s';
    return '${(kb / 1024).toStringAsFixed(1)} MB/s';
  }

  String get clockText {
    final now = DateTime.now();
    return '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
  }

  String get fitShortLabel => switch (fitMode) {
        VideoFitMode.contain => '原画',
        VideoFitMode.cover => '裁切',
        VideoFitMode.none => '原始',
        VideoFitMode.fill => '铺满',
      };

  String playbackRateLabel(double rate) {
    final text = rate.toStringAsFixed(2).replaceFirst(RegExp(r'0$'), '');
    return '${text}x';
  }

  Future<void> setPlaybackRate(double rate) async {
    setStateIfMounted(() => playbackRate = rate);
    await setPlaybackSpeed(rate);
    scheduleControlsAutoHide();
  }

  Future<void> showPlaybackRates(BuildContext anchorContext) async {
    final selected = await showControlMenu<double>(
      anchorContext: anchorContext,
      selectedValue: playbackRate,
      options: [
        for (final rate in _playbackRates)
          (value: rate, label: playbackRateLabel(rate)),
      ],
    );
    if (selected != null) await setPlaybackRate(selected);
    scheduleControlsAutoHide();
  }

  Future<void> seekRelative(int seconds) async {
    if (controlsLocked) return;
    if (duration == Duration.zero) return;
    markControlsInteraction();
    final nextMs = (position.inMilliseconds + seconds * 1000)
        .clamp(0, duration.inMilliseconds);
    final target = Duration(milliseconds: nextMs.toInt());
    syncDanmuClock(target);
    clearDanmuOverlay();
    await seekPlayback(target);
  }

  Future<void> rotateScreen(BuildContext context) async {
    if (controlsLocked) return;
    markControlsInteraction();
    orientationLocked = false;
    await applyVideoOrientation();
  }

  void toggleLock() {
    setStateIfMounted(() {
      controlsLocked = !controlsLocked;
      if (controlsLocked) {
        controlsHideTimer?.cancel();
        episodePanelOpen = false;
        episodePanelClosing = false;
        danmuPanelOpen = false;
        danmuPanelClosing = false;
        danmuSearchPanelOpen = false;
        danmuSearchPanelClosing = false;
        resumeAfterDanmuSearch = false;
        dragPreviewPosition = null;
        seekingByDrag = false;
      } else {
        episodePanelOpen = false;
        danmuPanelOpen = false;
        danmuSearchPanelOpen = false;
      }
    });
    setControlsVisible(true);
    scheduleControlsAutoHide();
  }

  void openEpisodePanel() {
    if (controlsLocked) return;
    controlsHideTimer?.cancel();
    setStateIfMounted(() {
      episodePanelOpen = true;
      episodePanelClosing = false;
      danmuPanelOpen = false;
      danmuPanelClosing = false;
      danmuSearchPanelOpen = false;
      danmuSearchPanelClosing = false;
      resumeAfterDanmuSearch = false;
    });
  }

  void closeEpisodePanel() {
    if (!episodePanelOpen || episodePanelClosing) return;
    setStateIfMounted(() => episodePanelClosing = true);
    Future<void>.delayed(const Duration(milliseconds: 220), () {
      if (!mounted || !episodePanelClosing) return;
      setState(() {
        episodePanelOpen = false;
        episodePanelClosing = false;
      });
      scheduleControlsAutoHide();
    });
  }

  void openDanmuPanel() {
    if (controlsLocked) return;
    controlsHideTimer?.cancel();
    setStateIfMounted(() {
      danmuPanelOpen = true;
      danmuPanelClosing = false;
      episodePanelOpen = false;
      episodePanelClosing = false;
    });
  }

  void closeDanmuPanel() {
    if (!danmuPanelOpen || danmuPanelClosing) return;
    setStateIfMounted(() => danmuPanelClosing = true);
    Future<void>.delayed(const Duration(milliseconds: 220), () {
      if (!mounted || !danmuPanelClosing) return;
      setState(() {
        danmuPanelOpen = false;
        danmuPanelClosing = false;
      });
      scheduleControlsAutoHide();
    });
  }

  String get danmuSearchDefaultKeyword {
    final file = currentDbFile;
    final showTitle = file?.showTitle?.trim();
    if (showTitle != null && showTitle.isNotEmpty) return showTitle;
    return mediaGroupDisplayTitle(currentItem);
  }

  int? get danmuSearchDefaultEpisode =>
      currentDbFile?.episodeNumber ?? currentItem.episode;

  int? get manualDanmuSearchEpisode {
    final text = danmuSearchEpisodeController.text.trim();
    if (text.isEmpty) return null;
    return int.tryParse(text);
  }

  void openDanmuSearchPanel() {
    if (controlsLocked) return;
    final config = widget.store.danmuConfig;
    if (!config.available) {
      setStateIfMounted(() => danmuStatus = '请先在我的页面启用并配置弹幕设置');
      return;
    }
    controlsHideTimer?.cancel();
    final defaultKeyword = danmuSearchDefaultKeyword;
    resumeAfterDanmuSearch = playing;
    if (playing) unawaited(pausePlayback());
    setStateIfMounted(() {
      danmuSearchController.text = defaultKeyword;
      danmuSearchEpisodeController.text =
          danmuSearchDefaultEpisode?.toString() ?? '';
      danmuSearchPanelOpen = true;
      danmuSearchPanelClosing = false;
      danmuSearchError = '';
      danmuSearchResults = const [];
      danmuSearchStarted = false;
      selectingDanmuEpisodeId = null;
    });
  }

  void closeDanmuSearchPanel({bool restorePlayback = true}) {
    if (!danmuSearchPanelOpen || danmuSearchPanelClosing) return;
    final shouldResume = restorePlayback && resumeAfterDanmuSearch;
    setStateIfMounted(() => danmuSearchPanelClosing = true);
    Future<void>.delayed(const Duration(milliseconds: 220), () {
      if (!mounted || !danmuSearchPanelClosing) return;
      setState(() {
        danmuSearchPanelOpen = false;
        danmuSearchPanelClosing = false;
        danmuSearchLoading = false;
        danmuSearchStarted = false;
        selectingDanmuEpisodeId = null;
        resumeAfterDanmuSearch = false;
      });
      if (shouldResume) unawaited(playPlayback());
      scheduleControlsAutoHide();
    });
  }

  Future<void> searchDanmuManually() async {
    final keyword = danmuSearchController.text.trim();
    if (keyword.isEmpty) {
      setStateIfMounted(() {
        danmuSearchResults = const [];
        danmuSearchError = '请输入要搜索的片名';
      });
      return;
    }
    setStateIfMounted(() {
      danmuSearchStarted = true;
      danmuSearchLoading = true;
      danmuSearchError = '';
      selectingDanmuEpisodeId = null;
    });
    try {
      final results = await DanmuService(
        widget.store.danmuConfig,
        log: (message) =>
            widget.store.addDiagnosticLog(message, category: 'danmu'),
      ).search(keyword, episode: manualDanmuSearchEpisode);
      if (!mounted) return;
      setState(() {
        danmuSearchResults = results;
        danmuSearchLoading = false;
        danmuSearchError = results.isEmpty ? '没有找到可用弹幕' : '';
      });
    } catch (error) {
      if (!mounted) return;
      widget.store.addDiagnosticLog('danmu manual search failed: $error',
          category: 'danmu');
      setState(() {
        danmuSearchResults = const [];
        danmuSearchLoading = false;
        danmuSearchError = '搜索失败：$error';
      });
    }
  }

  Future<void> selectDanmuSearchResult(DanmuSearchResult result) async {
    if (selectingDanmuEpisodeId != null) return;
    final loadId = ++danmuLoadId;
    final file = currentDbFile;
    final sourceFileName = file?.filename ?? mediaIdentityFileName(currentItem);
    final season = file?.seasonNumber ?? currentItem.season;
    final episode =
        result.episodeNumber ?? file?.episodeNumber ?? currentItem.episode;
    final manualFileNames = buildManualDanmuMatchFileNames(
      result: result,
      sourceFileName: sourceFileName,
      season: season,
      episode: episode,
    );
    setStateIfMounted(() {
      selectingDanmuEpisodeId = result.episodeId;
      danmuLoading = true;
      danmuStatus = '正在加载选中的弹幕...';
    });
    try {
      final service = DanmuService(
        widget.store.danmuConfig,
        log: (message) =>
            widget.store.addDiagnosticLog(message, category: 'danmu'),
      );
      final trimmedEpisodeId = result.episodeId.trim();
      final canLoadDirectly = RegExp(r'^\d+$').hasMatch(trimmedEpisodeId) ||
          trimmedEpisodeId.startsWith('http://') ||
          trimmedEpisodeId.startsWith('https://');
      var loadResult = const RustDanmuLoadResult(
        sessionId: 0,
        count: 0,
        matchedEpisodeId: '',
        matchedTitle: '',
        matchedEpisode: '',
        logs: [],
      );
      if (canLoadDirectly) {
        widget.store.addDiagnosticLog(
          'danmu manual direct comment: episodeId=${result.episodeId}',
          category: 'danmu',
        );
        loadResult = await service.loadSession(
          title: result.animeTitle,
          fileNames: manualFileNames,
          season: season,
          episode: episode,
          episodeId: result.episodeId,
          episodeTitle: result.episodeTitle,
        );
      }
      if (loadResult.count == 0 && canLoadDirectly) {
        final keyword = danmuSearchController.text.trim();
        if (keyword.isNotEmpty) {
          widget.store.addDiagnosticLog(
            'danmu manual direct empty, refresh search candidates: keyword=$keyword episode=$episode',
            category: 'danmu',
          );
          final freshResults = await service.search(keyword, episode: episode);
          for (final candidate in freshResults.take(6)) {
            final candidateEpisodeId = candidate.episodeId.trim();
            if (candidateEpisodeId.isEmpty ||
                candidateEpisodeId == trimmedEpisodeId) {
              continue;
            }
            final candidateCanLoadDirectly =
                RegExp(r'^\d+$').hasMatch(candidateEpisodeId) ||
                    candidateEpisodeId.startsWith('http://') ||
                    candidateEpisodeId.startsWith('https://');
            if (!candidateCanLoadDirectly) continue;
            widget.store.addDiagnosticLog(
              'danmu manual retry direct comment: episodeId=${candidate.episodeId}',
              category: 'danmu',
            );
            loadResult = await service.loadSession(
              title: candidate.animeTitle,
              fileNames: buildManualDanmuMatchFileNames(
                result: candidate,
                sourceFileName: sourceFileName,
                season: season,
                episode: episode,
              ),
              season: season,
              episode: episode,
              episodeId: candidate.episodeId,
              episodeTitle: candidate.episodeTitle,
            );
            if (loadResult.count > 0) break;
          }
        }
      }
      if (loadResult.count == 0) {
        widget.store.addDiagnosticLog(
          'danmu manual direct empty, fallback to match: episodeId=${result.episodeId}',
          category: 'danmu',
        );
        loadResult = await service.loadSession(
          title: result.animeTitle,
          fileNames: manualFileNames,
          season: season,
          episode: episode,
        );
      }
      if (loadResult.count == 0 && !manualFileNames.contains(sourceFileName)) {
        loadResult = await service.loadSession(
          title: result.animeTitle,
          fileNames: [sourceFileName],
          season: season,
          episode: episode,
        );
      }
      if (loadResult.count == 0 && !canLoadDirectly) {
        widget.store.addDiagnosticLog(
          'danmu manual skipped direct comment for non-numeric episodeId=${result.episodeId}',
          category: 'danmu',
        );
      }
      if (!mounted || loadId != danmuLoadId) return;
      if (loadResult.count == 0) {
        setState(() {
          danmuLoading = false;
          selectingDanmuEpisodeId = null;
          danmuSearchError = '选中的弹幕为空，已保留当前弹幕';
          danmuStatus = danmuSessionId > 0 ? '已保留当前弹幕' : '选中的弹幕为空';
        });
        syncDanmuTickerState();
        return;
      }
      clearDanmuSession();
      setState(() {
        danmuSessionId = loadResult.sessionId;
        danmuTotalCount = loadResult.count;
        danmuStatus =
            loadResult.count == 0 ? '选中的弹幕为空' : '已加载 ${loadResult.count} 条';
        danmuLoading = false;
        selectingDanmuEpisodeId = null;
      });
      clearDanmuOverlay();
      if (ready) refreshVisibleDanmu(force: true);
      closeDanmuSearchPanel();
    } catch (error) {
      if (!mounted || loadId != danmuLoadId) return;
      widget.store.addDiagnosticLog('danmu manual load failed: $error',
          category: 'danmu');
      setState(() {
        danmuLoading = false;
        selectingDanmuEpisodeId = null;
        danmuSearchError = '加载失败：$error';
        danmuStatus = '弹幕加载失败';
      });
    }
  }

  List<String> buildManualDanmuMatchFileNames({
    required DanmuSearchResult result,
    required String sourceFileName,
    int? season,
    int? episode,
  }) {
    final title = result.animeTitle.trim();
    final episodeTitle = result.episodeTitle.trim();
    final candidates = <String>[
      if (title.isNotEmpty && season != null && episode != null)
        '$title.S${season.toString().padLeft(2, '0')}E${episode.toString().padLeft(2, '0')}',
      if (title.isNotEmpty && episode != null) '$title 第 $episode 集',
      if (title.isNotEmpty && episodeTitle.isNotEmpty) '$title $episodeTitle',
      result.displayTitle,
      sourceFileName,
    ];
    return LinkedHashSet<String>.of(candidates.map((value) => value.trim()))
        .where((value) => value.isNotEmpty)
        .toList(growable: false);
  }

  Widget controlIconButton({
    required IconData icon,
    required VoidCallback onPressed,
    double size = 24,
  }) {
    return IconButton(
      color: Colors.white,
      onPressed: onPressed,
      icon: shadowIcon(icon, size: size),
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints.tightFor(width: 38, height: 38),
    );
  }

  Future<T?> showControlMenu<T>({
    required BuildContext anchorContext,
    required List<({String label, T value})> options,
    required T selectedValue,
  }) {
    controlsHideTimer?.cancel();
    final overlay =
        Overlay.of(anchorContext).context.findRenderObject() as RenderBox;
    final box = anchorContext.findRenderObject() as RenderBox;
    final topLeft = box.localToGlobal(Offset.zero, ancestor: overlay);
    final bottomRight = box.localToGlobal(
        Offset(box.size.width, box.size.height),
        ancestor: overlay);
    final menuWidth = math.max(220.0, math.min(336.0, overlay.size.width - 32));
    final entries = <PopupMenuEntry<T>>[];
    for (var index = 0; index < options.length; index++) {
      final option = options[index];
      if (index > 0) entries.add(const PopupMenuDivider(height: 1));
      entries.add(
        PopupMenuItem<T>(
          value: option.value,
          height: 54,
          child: Row(
            children: [
              Expanded(
                child: Text(
                  option.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontSize: 16),
                ),
              ),
              if (option.value == selectedValue)
                const Icon(Icons.check, color: Colors.white, size: 22),
            ],
          ),
        ),
      );
    }
    return showMenu<T>(
      context: context,
      position: RelativeRect.fromRect(
        Rect.fromPoints(topLeft, bottomRight),
        Offset.zero & overlay.size,
      ),
      constraints: BoxConstraints.tightFor(width: menuWidth),
      color: const Color(0xEE4A4A4A),
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      items: entries,
    );
  }

  String trackLabel(dynamic track, String fallback) {
    final title = track.title as String?;
    final language = track.language as String?;
    final id = track.id as String;
    if (id == 'auto') return '自动';
    if (id == 'no') return '关闭';
    final parts = [
      if (title != null && title.trim().isNotEmpty) title.trim(),
      if (language != null && language.trim().isNotEmpty) language.trim(),
      if ((title == null || title.trim().isEmpty) &&
          (language == null || language.trim().isEmpty))
        '$fallback $id',
    ];
    return parts.join(' · ');
  }

  Future<void> showAudioTracks(BuildContext anchorContext) async {
    final tracks = availableTracks.audio;
    if (tracks.isEmpty) {
      scheduleControlsAutoHide();
      return;
    }
    final selected = await showControlMenu<AudioTrack>(
      anchorContext: anchorContext,
      selectedValue: selectedTrack.audio,
      options: [
        for (final track in tracks)
          (value: track, label: trackLabel(track, '音轨')),
      ],
    );
    if (selected != null) {
      if (usingMedia3) {
        await media3Command('audioTrack', selected.id);
      } else {
        await player.setAudioTrack(selected);
      }
    }
    scheduleControlsAutoHide();
  }

  Future<void> showSubtitleTracks(BuildContext anchorContext) async {
    final tracks = availableTracks.subtitle;
    if (tracks.isEmpty) {
      scheduleControlsAutoHide();
      return;
    }
    final selected = await showControlMenu<SubtitleTrack>(
      anchorContext: anchorContext,
      selectedValue: selectedTrack.subtitle,
      options: [
        for (final track in tracks)
          (value: track, label: trackLabel(track, '字幕')),
      ],
    );
    if (selected != null) {
      if (usingMedia3) {
        await media3Command('subtitleTrack', selected.id);
      } else {
        await player.setSubtitleTrack(selected);
      }
    }
    scheduleControlsAutoHide();
  }

  List<MediaItem> get episodeItems {
    if (widget.episodes != null) return widget.episodes!;
    final folderKey = mediaFolderKey(currentItem);
    final items = widget.store.items
        .where((item) =>
            item.sourceId == currentItem.sourceId &&
            mediaFolderKey(item) == folderKey)
        .toList();
    items.sort((a, b) {
      final left = dbFileForItem(a);
      final right = dbFileForItem(b);
      final leftEpisode = left?.episodeNumber ?? inferredEpisodeNumber(a);
      final rightEpisode = right?.episodeNumber ?? inferredEpisodeNumber(b);
      if (leftEpisode != null && rightEpisode != null) {
        return leftEpisode.compareTo(rightEpisode);
      }
      return a.title.toLowerCase().compareTo(b.title.toLowerCase());
    });
    return items;
  }

  Future<RemotePlayback> resolvePlayback(MediaItem item) =>
      widget.playbackResolver?.call(item) ??
      playbackForItem(widget.store, item);

  LibraryFileEntry? dbFileForItem(MediaItem item) {
    final detail = libraryDetail;
    if (detail == null) return null;
    for (final file in detail.files) {
      if (file.itemId == item.id) return file;
    }
    return null;
  }

  int rememberedPositionMsFor(MediaItem item) {
    final stored = widget.store.progress[item.id];
    final duration = rememberedDurationMsFor(item);
    if (stored != null && stored > 0) {
      return resumablePlaybackPositionMs(stored, duration);
    }
    final filePosition = dbFileForItem(item)?.positionMs;
    return filePosition != null && filePosition > 0
        ? resumablePlaybackPositionMs(filePosition, duration)
        : 0;
  }

  int rememberedDurationMsFor(MediaItem item) {
    final stored = widget.store.durations[item.id];
    if (stored != null && stored > 0) return stored;
    final fileDuration = dbFileForItem(item)?.durationMs;
    return fileDuration != null && fileDuration > 0 ? fileDuration : 0;
  }

  LibraryFileEntry? get currentDbFile => dbFileForItem(currentItem);

  MediaItem? get nextEpisodeItem {
    final items = episodeItems;
    final index = items.indexWhere((item) => item.id == currentItem.id);
    if (index < 0 || index + 1 >= items.length) return null;
    return items[index + 1];
  }

  String playbackTitleFor(MediaItem item) {
    final file = dbFileForItem(item);
    if (file == null) return item.title;
    return dbPlaybackTitle(file, fallback: item.title);
  }

  String episodePanelTitle(MediaItem item) {
    final file = dbFileForItem(item);
    if (file == null) return item.title;
    final title = dbEpisodeTitle(file, fallback: item.title);
    final episode = file.episodeNumber;
    return episode == null ? title : '$episode. $title';
  }

  String get episodePanelSeasonLabel {
    final file = currentDbFile ?? libraryDetail?.representative;
    if (file == null) return '剧集';
    return dbSeasonLabel(file);
  }

  Future<void> handlePlaybackCompleted(bool completed) async {
    if (!completed || autoAdvancingEpisode || !mediaOpenCompleted) return;
    if (!ready || !playbackPositionConfirmed) {
      logVideoLoading(
          'playback completed ignored before ready: ready=$ready confirmed=$playbackPositionConfirmed position=${position.inMilliseconds}ms duration=${duration.inMilliseconds}ms');
      return;
    }
    final next = nextEpisodeItem;
    final completedPosition = duration > Duration.zero ? duration : position;
    setStateIfMounted(() {
      position = completedPosition;
      playing = false;
    });
    if (next == null) {
      logVideoLoading('playback completed: no next episode');
      await widget.store
          .updateProgress(currentItem.id, completedPosition, duration);
      notifyControlsChanged();
      syncDanmuTickerState();
      return;
    }

    autoAdvancingEpisode = true;
    logVideoLoading(
        'playback completed: auto next from ${currentItem.id} to ${next.id}');
    try {
      await playEpisode(next, resume: false);
    } finally {
      autoAdvancingEpisode = false;
    }
  }

  Future<void> playEpisode(MediaItem item, {bool resume = true}) async {
    if (item.id == currentItem.id) {
      closeEpisodePanel();
      return;
    }
    controlsHideTimer?.cancel();
    await saveCurrentProgress();
    final saved = resume ? rememberedPositionMsFor(item) : 0;
    final rememberedDuration = resume ? rememberedDurationMsFor(item) : 0;
    syncDanmuClock(saved > 0 ? Duration(milliseconds: saved) : Duration.zero);
    clearDanmuOverlay();
    clearDanmuSession();
    landscapeSensorTimer?.cancel();
    setStateIfMounted(() {
      currentItem = item;
      position = saved > 0 ? Duration(milliseconds: saved) : Duration.zero;
      duration = rememberedDuration > 0
          ? Duration(milliseconds: rememberedDuration)
          : Duration.zero;
      videoWidth = null;
      videoHeight = null;
      orientationLocked = false;
      ready = false;
      mediaOpenCompleted = false;
      playbackPositionConfirmed = false;
      voConfigured = false;
      pausedForCache = false;
      playing = true;
      buffering = true;
      loadingVisible = true;
      bufferingPercentage = 0;
      error = null;
      episodePanelOpen = false;
      episodePanelClosing = false;
      danmuPanelOpen = false;
      danmuPanelClosing = false;
      danmuSearchPanelOpen = false;
      danmuSearchPanelClosing = false;
      resumeAfterDanmuSearch = false;
      danmuTotalCount = 0;
      danmuStatus = '未加载';
      selectedTrack = const Track();
      availableTracks = const Tracks();
    });
    unawaited(loadCurrentLibraryDetail());
    await init();
  }

  List<Shadow> get controlShadows => const [];

  IconThemeData get controlIconTheme =>
      const IconThemeData(color: Colors.white, shadows: []);

  TextStyle get controlTextStyle =>
      TextStyle(color: Colors.white, shadows: controlShadows);

  Widget statusText(String value,
      {double size = 14, FontWeight weight = FontWeight.w600}) {
    return Text(value,
        style: controlTextStyle.copyWith(fontSize: size, fontWeight: weight));
  }

  Widget shadowIcon(IconData icon, {double size = 24}) {
    return Icon(icon, size: size, color: Colors.white, shadows: controlShadows);
  }

  Widget buildLoadingOverlay() {
    final percent = bufferingPercentage.clamp(0, 100).round();
    return IgnorePointer(
      child: Center(
        child: DecoratedBox(
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                  color: Color(0x66000000), blurRadius: 18, spreadRadius: 2),
            ],
          ),
          child: SizedBox(
            width: 62,
            height: 62,
            child: Stack(
              alignment: Alignment.center,
              children: [
                const SizedBox(
                  width: 50,
                  height: 50,
                  child: CircularProgressIndicator(
                    strokeWidth: 4,
                    strokeCap: StrokeCap.round,
                    color: Colors.white,
                  ),
                ),
                Text('$percent%',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        shadows: [
                          Shadow(color: Color(0xCC000000), blurRadius: 8)
                        ])),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget buildBatteryIndicator() {
    final level = battery < 0 ? 0 : battery.clamp(0, 100);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 27,
          height: 14,
          padding: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            border: Border.all(color: Colors.white, width: 1.5),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Align(
            alignment: Alignment.centerLeft,
            child: FractionallySizedBox(
              widthFactor: level / 100,
              heightFactor: 1,
              child: DecoratedBox(
                decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(2)),
              ),
            ),
          ),
        ),
        const SizedBox(width: 2),
        Container(
          width: 2,
          height: 6,
          decoration: BoxDecoration(
              color: Colors.white, borderRadius: BorderRadius.circular(2)),
        ),
        if (charging) ...[
          const SizedBox(width: 4),
          shadowIcon(Icons.bolt, size: 14),
        ],
      ],
    );
  }

  Widget buildStatusOverlay(bool isLandscape) {
    return SafeArea(
      bottom: false,
      child: SizedBox(
        height: isLandscape ? 26 : 24,
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: isLandscape ? 18 : 12),
          child: Row(
            children: [
              SizedBox(
                  width: isLandscape ? 110 : 54,
                  child: statusText(clockText,
                      size: isLandscape ? 14 : 12, weight: FontWeight.w700)),
              const Spacer(),
              if (isLandscape) ...[
                statusText(networkSpeed, size: 12),
                const SizedBox(width: 10),
              ],
              shadowIcon(Icons.signal_cellular_alt,
                  size: isLandscape ? 16 : 14),
              const SizedBox(width: 6),
              statusText(network,
                  size: isLandscape ? 13 : 11, weight: FontWeight.w700),
              if (Platform.isAndroid) ...[
                const SizedBox(width: 8),
                buildBatteryIndicator(),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget buildTitleOverlay(BuildContext context, bool isLandscape) {
    final safeTop = MediaQuery.paddingOf(context).top;
    return Positioned(
      left: isLandscape ? 32 : 12,
      right: isLandscape ? 32 : 112,
      top: safeTop + (isLandscape ? 28 : 34),
      child: Row(
        children: [
          IconButton(
            color: Colors.white,
            onPressed: () => Navigator.of(context).maybePop(),
            icon: shadowIcon(Icons.chevron_left, size: isLandscape ? 30 : 24),
            padding: EdgeInsets.zero,
            constraints: BoxConstraints.tightFor(
                width: isLandscape ? 36 : 36, height: isLandscape ? 36 : 36),
          ),
          Expanded(
            child: Text(
              playbackTitleFor(currentItem),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  color: Colors.white,
                  fontSize: isLandscape ? 16 : 14,
                  fontWeight: FontWeight.w700,
                  shadows: controlShadows),
            ),
          ),
        ],
      ),
    );
  }

  Widget buildLockButton(
      BuildContext context, BoxConstraints constraints, bool isLandscape) {
    final safeTop = MediaQuery.paddingOf(context).top;
    return Positioned(
      right: isLandscape ? 34 : 22,
      top: controlsLocked
          ? (isLandscape
              ? math.max(82, constraints.maxHeight * 0.44)
              : safeTop + 90)
          : (isLandscape
              ? math.max(104, constraints.maxHeight * 0.36)
              : safeTop + 92),
      child: controlIconButton(
        icon: controlsLocked ? Icons.lock_outline : Icons.lock_open_outlined,
        onPressed: toggleLock,
        size: isLandscape ? 26 : 22,
      ),
    );
  }

  Widget buildEpisodePanel(BoxConstraints constraints, bool isLandscape) {
    final items = episodeItems;
    final panelWidth = (constraints.maxWidth * (isLandscape ? 0.46 : 0.92))
        .clamp(280.0, isLandscape ? 520.0 : constraints.maxWidth)
        .toDouble();
    return Positioned.fill(
      child: Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              onTap: closeEpisodePanel,
              child: const ColoredBox(color: Color(0x66000000)),
            ),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TweenAnimationBuilder<Offset>(
              tween: Tween(
                begin: const Offset(1, 0),
                end: episodePanelClosing ? const Offset(1, 0) : Offset.zero,
              ),
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              builder: (context, offset, child) => FractionalTranslation(
                translation: offset,
                child: child,
              ),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {},
                onDoubleTap: () {},
                child: Container(
                  width: panelWidth,
                  height: double.infinity,
                  padding: EdgeInsets.fromLTRB(
                      isLandscape ? 14 : 14, 12, isLandscape ? 18 : 14, 14),
                  decoration: const BoxDecoration(
                    color: Color(0xE81F1F24),
                    border: Border(left: BorderSide(color: Color(0x55FFFFFF))),
                  ),
                  child: SafeArea(
                    left: false,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('$episodePanelSeasonLabel（共 ${items.length} 集）',
                            style: TextStyle(
                                color: Colors.white70,
                                fontSize: isLandscape ? 14 : 12)),
                        SizedBox(height: isLandscape ? 14 : 12),
                        Expanded(
                          child: ListView.separated(
                            itemCount: items.length,
                            separatorBuilder: (_, __) =>
                                SizedBox(height: isLandscape ? 10 : 7),
                            itemBuilder: (context, index) {
                              final item = items[index];
                              final selected = item.id == currentItem.id;
                              return InkWell(
                                borderRadius: BorderRadius.circular(9),
                                onTap: () => playEpisode(item),
                                child: Container(
                                  padding: EdgeInsets.symmetric(
                                      horizontal: isLandscape ? 14 : 10,
                                      vertical: isLandscape ? 10 : 9),
                                  decoration: BoxDecoration(
                                    color: selected
                                        ? const Color(0x22FFFFFF)
                                        : Colors.transparent,
                                    borderRadius: BorderRadius.circular(9),
                                    border: Border.all(
                                        color: selected
                                            ? Colors.white
                                            : Colors.white38,
                                        width: selected ? 2 : 1),
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(
                                          selected
                                              ? Icons.play_circle_fill
                                              : Icons.play_circle_outline,
                                          color: Colors.white,
                                          size: 21),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Text(
                                          episodePanelTitle(item),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                              color: Colors.white,
                                              fontSize: isLandscape ? 15 : 13),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget buildDanmuPanel(BoxConstraints constraints, bool isLandscape) {
    final panelWidth = (constraints.maxWidth * (isLandscape ? 0.42 : 0.92))
        .clamp(280.0, isLandscape ? 500.0 : constraints.maxWidth)
        .toDouble();
    final config = widget.store.danmuConfig;
    return Positioned.fill(
      child: Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              onTap: closeDanmuPanel,
              child: const ColoredBox(color: Color(0x66000000)),
            ),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TweenAnimationBuilder<Offset>(
              tween: Tween(
                begin: const Offset(1, 0),
                end: danmuPanelClosing ? const Offset(1, 0) : Offset.zero,
              ),
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              builder: (context, offset, child) => FractionalTranslation(
                translation: offset,
                child: child,
              ),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {},
                onDoubleTap: () {},
                child: Container(
                  width: panelWidth,
                  height: double.infinity,
                  padding: EdgeInsets.fromLTRB(
                      isLandscape ? 14 : 14, 12, isLandscape ? 18 : 14, 14),
                  decoration: const BoxDecoration(
                    color: Color(0xE81F1F24),
                    border: Border(left: BorderSide(color: Color(0x55FFFFFF))),
                  ),
                  child: SafeArea(
                    left: false,
                    child: ListView(
                      children: [
                        Row(
                          children: [
                            const Expanded(
                              child: Text(
                                '弹幕设置',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 18,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                            IconButton(
                              color: Colors.white,
                              onPressed: closeDanmuPanel,
                              icon: const Icon(Icons.close),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Text(
                          danmuStatus,
                          style: const TextStyle(
                              color: Colors.white70, fontSize: 12),
                        ),
                        const SizedBox(height: 12),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('显示弹幕',
                              style: TextStyle(color: Colors.white)),
                          value: config.visible,
                          onChanged: (value) => unawaited(widget.store
                              .setDanmuConfig(config.copyWith(visible: value))),
                        ),
                        _DanmuPanelSlider(
                          label: '字号',
                          value: config.fontSize,
                          min: 12,
                          max: 28,
                          divisions: 16,
                          display: config.fontSize.toStringAsFixed(0),
                          onChanged: (value) => unawaited(widget.store
                              .setDanmuConfig(
                                  config.copyWith(fontSize: value))),
                        ),
                        _DanmuPanelSlider(
                          label: '透明度',
                          value: config.opacity,
                          min: 0.3,
                          max: 1,
                          divisions: 7,
                          display: '${(config.opacity * 100).round()}%',
                          onChanged: (value) => unawaited(widget.store
                              .setDanmuConfig(config.copyWith(opacity: value))),
                        ),
                        _DanmuPanelSlider(
                          label: '速度',
                          value: config.speed,
                          min: 0.6,
                          max: 1.8,
                          divisions: 12,
                          display: '${config.speed.toStringAsFixed(1)}x',
                          onChanged: (value) => unawaited(widget.store
                              .setDanmuConfig(config.copyWith(speed: value))),
                        ),
                        _DanmuPanelSlider(
                          label: '时间偏移',
                          value: config.offsetMs / 1000,
                          min: -60,
                          max: 60,
                          divisions: 120,
                          display:
                              '${(config.offsetMs / 1000).toStringAsFixed(1)}s',
                          onChanged: (value) =>
                              unawaited(widget.store.setDanmuConfig(
                            config.copyWith(offsetMs: (value * 1000).round()),
                          )),
                        ),
                        _DanmuPanelSlider(
                          label: '滚动行数',
                          value: config.maxLines.toDouble(),
                          min: 1,
                          max: 14,
                          divisions: 13,
                          display: '${config.maxLines} 行',
                          onChanged: (value) =>
                              unawaited(widget.store.setDanmuConfig(
                            config.copyWith(maxLines: value.round()),
                          )),
                        ),
                        _DanmuPanelSlider(
                          label: '顶部位置',
                          value: config.topPadding,
                          min: -120,
                          max: 220,
                          divisions: 34,
                          display: '${config.topPadding.round()} px',
                          onChanged: (value) =>
                              unawaited(widget.store.setDanmuConfig(
                            config.copyWith(topPadding: value),
                          )),
                        ),
                        const SizedBox(height: 14),
                        OutlinedButton.icon(
                          onPressed:
                              config.available ? openDanmuSearchPanel : null,
                          icon: const Icon(Icons.search),
                          label: const Text('搜索弹幕'),
                        ),
                        const SizedBox(height: 10),
                        FilledButton.icon(
                          onPressed:
                              danmuLoading ? null : loadDanmuForCurrentItem,
                          icon: danmuLoading
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child:
                                      CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.refresh),
                          label: Text(danmuLoading ? '加载中' : '重新匹配弹幕'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget buildDanmuSearchPanel(BoxConstraints constraints, bool isLandscape) {
    final panelWidth = (constraints.maxWidth * (isLandscape ? 0.52 : 0.96))
        .clamp(320.0, isLandscape ? 620.0 : constraints.maxWidth)
        .toDouble();
    return Positioned.fill(
      child: Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              onTap: closeDanmuSearchPanel,
              child: const ColoredBox(color: Color(0x8A000000)),
            ),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TweenAnimationBuilder<Offset>(
              tween: Tween(
                begin: const Offset(1, 0),
                end: danmuSearchPanelClosing ? const Offset(1, 0) : Offset.zero,
              ),
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              builder: (context, offset, child) => FractionalTranslation(
                translation: offset,
                child: child,
              ),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {},
                onDoubleTap: () {},
                child: Container(
                  width: panelWidth,
                  height: double.infinity,
                  padding: EdgeInsets.fromLTRB(
                      isLandscape ? 16 : 14, 12, isLandscape ? 20 : 14, 14),
                  decoration: const BoxDecoration(
                    color: Color(0xF21F1F24),
                    border: Border(left: BorderSide(color: Color(0x55FFFFFF))),
                  ),
                  child: SafeArea(
                    left: false,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            const Expanded(
                              child: Text(
                                '搜索弹幕',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 18,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                            IconButton(
                              color: Colors.white,
                              onPressed: closeDanmuSearchPanel,
                              icon: const Icon(Icons.close),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        TextField(
                          controller: danmuSearchController,
                          style: const TextStyle(color: Colors.white),
                          textInputAction: TextInputAction.search,
                          onSubmitted: (_) => searchDanmuManually(),
                          decoration: InputDecoration(
                            hintText: '输入片名搜索',
                            hintStyle: const TextStyle(color: Colors.white54),
                            prefixIcon:
                                const Icon(Icons.search, color: Colors.white70),
                            suffixIcon: danmuSearchLoading
                                ? const Padding(
                                    padding: EdgeInsets.all(12),
                                    child: SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    ),
                                  )
                                : IconButton(
                                    color: Colors.white70,
                                    onPressed: searchDanmuManually,
                                    icon: const Icon(Icons.arrow_forward),
                                  ),
                            filled: true,
                            fillColor: const Color(0x22FFFFFF),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide:
                                  const BorderSide(color: Color(0x33FFFFFF)),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide:
                                  const BorderSide(color: Color(0x33FFFFFF)),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide:
                                  const BorderSide(color: Color(0xAAFFFFFF)),
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            SizedBox(
                              width: 118,
                              child: TextField(
                                controller: danmuSearchEpisodeController,
                                keyboardType: TextInputType.number,
                                style: const TextStyle(color: Colors.white),
                                textInputAction: TextInputAction.search,
                                onSubmitted: (_) => searchDanmuManually(),
                                decoration: InputDecoration(
                                  labelText: '集数',
                                  labelStyle:
                                      const TextStyle(color: Colors.white54),
                                  hintText: '全部',
                                  hintStyle:
                                      const TextStyle(color: Colors.white38),
                                  filled: true,
                                  fillColor: const Color(0x22FFFFFF),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8),
                                    borderSide: const BorderSide(
                                        color: Color(0x33FFFFFF)),
                                  ),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8),
                                    borderSide: const BorderSide(
                                        color: Color(0x33FFFFFF)),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8),
                                    borderSide: const BorderSide(
                                        color: Color(0xAAFFFFFF)),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            OutlinedButton.icon(
                              onPressed: () {
                                danmuSearchEpisodeController.clear();
                              },
                              icon: const Icon(Icons.format_list_bulleted),
                              label: const Text('全部集'),
                            ),
                            FilledButton.icon(
                              onPressed: danmuSearchLoading
                                  ? null
                                  : searchDanmuManually,
                              icon: const Icon(Icons.search),
                              label: const Text('搜索'),
                            ),
                          ],
                        ),
                        if (danmuSearchError.isNotEmpty) ...[
                          const SizedBox(height: 10),
                          Text(
                            danmuSearchError,
                            style: const TextStyle(
                                color: Color(0xFFFFC4C4), fontSize: 12),
                          ),
                        ],
                        const SizedBox(height: 12),
                        Expanded(
                          child: danmuSearchResults.isEmpty
                              ? Center(
                                  child: Text(
                                    danmuSearchLoading
                                        ? '正在搜索...'
                                        : danmuSearchStarted
                                            ? '没有搜索结果'
                                            : '点击搜索开始',
                                    style:
                                        const TextStyle(color: Colors.white54),
                                  ),
                                )
                              : ListView.separated(
                                  itemCount: danmuSearchResults.length,
                                  separatorBuilder: (_, __) => const Divider(
                                    color: Color(0x22FFFFFF),
                                    height: 1,
                                  ),
                                  itemBuilder: (context, index) {
                                    final result = danmuSearchResults[index];
                                    final selecting = selectingDanmuEpisodeId ==
                                        result.episodeId;
                                    return Material(
                                      color: Colors.transparent,
                                      child: InkWell(
                                        onTap: selecting
                                            ? null
                                            : () => unawaited(
                                                  selectDanmuSearchResult(
                                                      result),
                                                ),
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(
                                              vertical: 12),
                                          child: Row(
                                            children: [
                                              Expanded(
                                                child: Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                    Text(
                                                      result.displayTitle,
                                                      maxLines: 2,
                                                      overflow:
                                                          TextOverflow.ellipsis,
                                                      style: const TextStyle(
                                                        color: Colors.white,
                                                        fontWeight:
                                                            FontWeight.w700,
                                                      ),
                                                    ),
                                                    const SizedBox(height: 4),
                                                    Text(
                                                      'ID ${result.episodeId}',
                                                      maxLines: 1,
                                                      overflow:
                                                          TextOverflow.ellipsis,
                                                      style: const TextStyle(
                                                        color: Colors.white54,
                                                        fontSize: 12,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                              const SizedBox(width: 12),
                                              selecting
                                                  ? const SizedBox(
                                                      width: 18,
                                                      height: 18,
                                                      child:
                                                          CircularProgressIndicator(
                                                        strokeWidth: 2,
                                                      ),
                                                    )
                                                  : const Icon(
                                                      Icons.chevron_right,
                                                      color: Colors.white70,
                                                    ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    );
                                  },
                                ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget buildDanmuOverlay() {
    final config = widget.store.danmuConfig;
    return Positioned.fill(
      child: IgnorePointer(
        child: ValueListenableBuilder<List<RustDanmuRenderItem>>(
          valueListenable: danmuOverlayItems,
          builder: (context, items, _) {
            if (!config.available || !config.visible || items.isEmpty) {
              return const SizedBox.shrink();
            }
            return ClipRect(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final width = constraints.maxWidth;
                  final height = constraints.maxHeight;
                  if (width <= 0 || height <= 0) {
                    return const SizedBox.shrink();
                  }
                  return RepaintBoundary(
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        for (final item in items)
                          _DanmuItemView(
                            key: ValueKey(
                              '${item.id}:${item.timeMs}:${item.mode}:${item.text}:${config.fontSize}:${config.topPadding}',
                            ),
                            item: item,
                            config: config,
                            viewportWidth: width,
                            ticker: danmuTicker,
                            positionProvider: () => currentDanmuPosition,
                          ),
                      ],
                    ),
                  );
                },
              ),
            );
          },
        ),
      ),
    );
  }

  Widget buildVerticalControlOverlay() {
    final label = verticalControlLabel;
    if (label == null) return const SizedBox.shrink();
    final percent = (verticalControlLevel * 100).round().clamp(0, 100);
    final icon =
        label == '音量' ? Icons.volume_up_rounded : Icons.brightness_6_rounded;
    return IgnorePointer(
      child: Center(
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: const Color(0xCC000000),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, color: Colors.white, size: 30),
                const SizedBox(height: 8),
                Text(
                  '$label $percent%',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget buildSeekButton(int seconds) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: Color(0x22000000),
        shape: BoxShape.circle,
      ),
      child: IconButton(
        color: Colors.white,
        onPressed: () => seekRelative(seconds),
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints.tightFor(width: 42, height: 42),
        icon: Stack(
          alignment: Alignment.center,
          children: [
            shadowIcon(
                seconds < 0
                    ? Icons.replay_10_rounded
                    : Icons.forward_10_rounded,
                size: 32),
          ],
        ),
      ),
    );
  }

  Widget buildBottomControls(
      BuildContext context, BoxConstraints constraints, bool isLandscape) {
    final safeBottom = MediaQuery.paddingOf(context).bottom;
    final compact = !isLandscape;
    final denseLandscape = isLandscape && constraints.maxWidth < 740;
    final leftTimeWidth = compact ? 46.0 : (denseLandscape ? 50.0 : 56.0);
    final rightTimeWidth = compact ? 50.0 : (denseLandscape ? 56.0 : 64.0);
    final playButtonSize = compact ? 52.0 : (denseLandscape ? 50.0 : 56.0);
    final displayedPosition = dragPreviewPosition ?? position;
    final iconSize = compact || denseLandscape ? 24.0 : 27.0;
    final smallIconSize = compact || denseLandscape ? 22.0 : 24.0;
    final episodeIconSize = compact || denseLandscape ? 25.0 : 28.0;
    final playButton = DecoratedBox(
      decoration: const BoxDecoration(
        color: Color(0x22000000),
        shape: BoxShape.circle,
      ),
      child: IconButton(
        color: Colors.white,
        iconSize: compact ? 38 : (denseLandscape ? 38 : 44),
        padding: EdgeInsets.zero,
        constraints: BoxConstraints.tightFor(
          width: playButtonSize,
          height: playButtonSize,
        ),
        onPressed: togglePlayback,
        icon: Icon(
          playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
          shadows: controlShadows,
        ),
      ),
    );
    final audioButton = Builder(
      builder: (buttonContext) => controlIconButton(
          icon: Icons.graphic_eq,
          onPressed: () => unawaited(showAudioTracks(buttonContext)),
          size: iconSize),
    );
    final subtitleButton = Builder(
      builder: (buttonContext) => controlIconButton(
          icon: Icons.closed_caption_outlined,
          onPressed: () => unawaited(showSubtitleTracks(buttonContext)),
          size: iconSize),
    );
    final episodeButton = Transform.translate(
      offset: Offset((38 - episodeIconSize) / 2, 0),
      child: controlIconButton(
        icon: Icons.format_list_bulleted_rounded,
        onPressed: openEpisodePanel,
        size: episodeIconSize,
      ),
    );
    final rotateButton = controlIconButton(
        icon: Icons.screen_rotation_alt_outlined,
        onPressed: () => rotateScreen(context),
        size: smallIconSize);
    final fitButton = Builder(
      builder: (buttonContext) => controlIconButton(
          icon: Icons.fit_screen_outlined,
          onPressed: () => unawaited(showFitModes(buttonContext)),
          size: smallIconSize),
    );
    final fullscreenButton = controlIconButton(
        icon:
            playbackWindowFullscreen ? Icons.fullscreen_exit : Icons.fullscreen,
        onPressed: togglePlaybackFullscreen,
        size: compact || denseLandscape ? 23 : 25);
    final danmuButton = controlIconButton(
        icon: Icons.chat_bubble_outline,
        onPressed: openDanmuPanel,
        size: smallIconSize);
    final sideSlotWidth = compact ? 48.0 : (denseLandscape ? 50.0 : 56.0);
    Widget sideSlot(Widget child, {Alignment alignment = Alignment.center}) =>
        SizedBox(
          width: sideSlotWidth,
          child: Align(alignment: alignment, child: child),
        );
    final centerControls = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        buildSeekButton(-10),
        SizedBox(width: compact ? 18 : (denseLandscape ? 6 : 8)),
        playButton,
        SizedBox(width: compact ? 18 : (denseLandscape ? 6 : 8)),
        buildSeekButton(10),
      ],
    );
    final leftControls = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        sideSlot(
          Builder(
            builder: (buttonContext) => GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => unawaited(showPlaybackRates(buttonContext)),
              child: Align(
                alignment: Alignment.centerLeft,
                child: statusText(playbackRateLabel(playbackRate),
                    size: compact ? 13 : (denseLandscape ? 13 : 14)),
              ),
            ),
          ),
          alignment: Alignment.centerLeft,
        ),
        sideSlot(statusText(fitShortLabel,
            size: compact ? 13 : (denseLandscape ? 13 : 14))),
        if (!isDesktopPlatform) sideSlot(rotateButton),
        sideSlot(fitButton),
        if (!isMobilePlatform) sideSlot(fullscreenButton),
      ],
    );
    final rightControls = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        sideSlot(danmuButton),
        sideSlot(audioButton),
        sideSlot(subtitleButton),
        sideSlot(episodeButton, alignment: Alignment.centerRight),
      ],
    );

    return Positioned(
      left: compact ? 16 : 56,
      right: compact ? 16 : 56,
      bottom: safeBottom + (compact ? 12 : 16),
      child: IconTheme.merge(
        data: controlIconTheme,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                SizedBox(
                    width: leftTimeWidth,
                    child: statusText(formatDuration(displayedPosition),
                        size: compact ? 12 : (denseLandscape ? 13 : 15))),
                Expanded(
                  child: SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 2.5,
                      activeTrackColor: Colors.white,
                      inactiveTrackColor: Colors.white54,
                      thumbColor: Colors.white,
                      overlayColor: const Color(0x33FFFFFF),
                    ),
                    child: Slider(
                      value: displayedPosition.inMilliseconds
                          .clamp(0, duration.inMilliseconds)
                          .toDouble(),
                      max: duration.inMilliseconds
                          .toDouble()
                          .clamp(1, double.infinity),
                      onChangeStart: beginSliderSeek,
                      onChanged: updateSliderSeek,
                      onChangeEnd: (value) => unawaited(endSliderSeek(value)),
                    ),
                  ),
                ),
                SizedBox(
                  width: rightTimeWidth,
                  child: Align(
                      alignment: Alignment.centerRight,
                      child: statusText(formatDuration(duration),
                          size: compact ? 12 : (denseLandscape ? 13 : 15))),
                ),
              ],
            ),
            SizedBox(height: compact ? 10 : (denseLandscape ? 8 : 12)),
            if (compact) ...[
              SizedBox(height: 52, child: Center(child: centerControls)),
              const SizedBox(height: 10),
              SizedBox(
                height: 38,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Row(
                    children: [
                      leftControls,
                      const SizedBox(width: 18),
                      rightControls,
                    ],
                  ),
                ),
              ),
            ] else
              SizedBox(
                height: 56,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Align(alignment: Alignment.centerLeft, child: leftControls),
                    Align(alignment: Alignment.center, child: centerControls),
                    Align(
                        alignment: Alignment.centerRight, child: rightControls),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget buildControlsOverlay(
      BuildContext context, BoxConstraints constraints, bool isLandscape) {
    return ValueListenableBuilder<bool>(
      valueListenable: controlsVisible,
      child: ValueListenableBuilder<int>(
        valueListenable: controlsRevision,
        builder: (context, _, __) {
          return Stack(
            fit: StackFit.expand,
            children: [
              if (!controlsLocked)
                Positioned(
                    left: 0,
                    right: 0,
                    top: 0,
                    child: RepaintBoundary(
                        child: buildStatusOverlay(isLandscape))),
              if (!controlsLocked) buildTitleOverlay(context, isLandscape),
              buildLockButton(context, constraints, isLandscape),
              if (!controlsLocked && dragPreviewPosition != null)
                Center(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: const Color(0xCC000000),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 18, vertical: 10),
                      child: Text(
                        formatDuration(dragPreviewPosition!),
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                ),
              if (!controlsLocked)
                buildBottomControls(context, constraints, isLandscape),
            ],
          );
        },
      ),
      builder: (context, visible, controlsChild) {
        return IgnorePointer(
          ignoring: !visible,
          child: TickerMode(
            enabled: visible,
            child: Visibility(
              visible: visible,
              maintainState: true,
              maintainAnimation: true,
              maintainSize: true,
              maintainSemantics: false,
              maintainInteractivity: false,
              child: controlsChild ?? const SizedBox.shrink(),
            ),
          ),
        );
      },
    );
  }

  Widget buildVideoOutput() {
    if (!backendSelected) return const SizedBox.expand();
    if (usingMedia3) {
      return const AndroidView(
        viewType: 'rplayer/media3_texture',
        hitTestBehavior: PlatformViewHitTestBehavior.transparent,
      );
    }
    return Center(
      child: Video(
        controller: controller,
        fit: videoFit,
        controls: NoVideoControls,
      ),
    );
  }

  Widget buildMedia3SubtitleOverlay() {
    if (!usingMedia3 || media3Subtitle.isEmpty) {
      return const SizedBox.shrink();
    }
    return Align(
      alignment: const Alignment(0, 0.72),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: const Color(0x99000000),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Text(
              media3Subtitle,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white, fontSize: 18),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.escape): () =>
              unawaited(handleEscapePressed()),
        },
        child: Focus(
          autofocus: true,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final isLandscape = constraints.maxWidth >= constraints.maxHeight;
              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onHorizontalDragStart:
                    inPictureInPicture ? null : beginSeekDrag,
                onHorizontalDragUpdate: inPictureInPicture
                    ? null
                    : (details) =>
                        updateSeekDrag(details, constraints.maxWidth),
                onHorizontalDragEnd:
                    inPictureInPicture ? null : (_) => endSeekDrag(),
                onHorizontalDragCancel: inPictureInPicture
                    ? null
                    : () {
                        seekingByDrag = false;
                        dragPreviewPosition = null;
                        notifyControlsChanged();
                        scheduleControlsAutoHide();
                      },
                onVerticalDragStart: inPictureInPicture
                    ? null
                    : (details) =>
                        beginVerticalControlDrag(details, constraints.biggest),
                onVerticalDragUpdate: inPictureInPicture
                    ? null
                    : (details) => updateVerticalControlDrag(
                        details, constraints.maxHeight),
                onVerticalDragEnd:
                    inPictureInPicture ? null : (_) => endVerticalControlDrag(),
                onVerticalDragCancel:
                    inPictureInPicture ? null : endVerticalControlDrag,
                onTap: inPictureInPicture ? null : toggleFullscreen,
                onDoubleTap: inPictureInPicture || controlsLocked
                    ? null
                    : togglePlayback,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    buildVideoOutput(),
                    buildMedia3SubtitleOverlay(),
                    buildDanmuOverlay(),
                    if (!inPictureInPicture && error == null && loadingVisible)
                      buildLoadingOverlay(),
                    if (!inPictureInPicture && error != null)
                      ErrorView(message: '$error', onRetry: init, dark: true),
                    if (!inPictureInPicture) buildVerticalControlOverlay(),
                    if (!inPictureInPicture)
                      buildControlsOverlay(context, constraints, isLandscape),
                    if (!inPictureInPicture && episodePanelOpen)
                      buildEpisodePanel(constraints, isLandscape),
                    if (!inPictureInPicture && danmuPanelOpen)
                      buildDanmuPanel(constraints, isLandscape),
                    if (!inPictureInPicture && danmuSearchPanelOpen)
                      buildDanmuSearchPanel(constraints, isLandscape),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _DanmuPanelSlider extends StatelessWidget {
  const _DanmuPanelSlider({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.display,
    required this.onChanged,
    this.divisions,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final int? divisions;
  final String display;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: Text(label, style: const TextStyle(color: Colors.white)),
            ),
            Text(display, style: const TextStyle(color: Colors.white70)),
          ],
        ),
        Slider(
          value: value.clamp(min, max),
          min: min,
          max: max,
          divisions: divisions,
          onChanged: onChanged,
        ),
      ],
    );
  }
}

class _DanmuItemView extends StatelessWidget {
  const _DanmuItemView({
    required this.item,
    required this.config,
    required this.viewportWidth,
    required this.ticker,
    required this.positionProvider,
    super.key,
  });

  final RustDanmuRenderItem item;
  final DanmuConfig config;
  final double viewportWidth;
  final Listenable ticker;
  final Duration Function() positionProvider;

  @override
  Widget build(BuildContext context) {
    final child = RepaintBoundary(
      child: Text(
        item.text,
        maxLines: 1,
        softWrap: false,
        overflow: TextOverflow.visible,
        textScaler: TextScaler.noScaling,
        style: TextStyle(
          color: Color(0xFF000000 | item.color).withValues(
            alpha: config.opacity.clamp(0.0, 1.0).toDouble(),
          ),
          fontSize: config.fontSize,
          fontWeight: FontWeight.w500,
          shadows: const [
            Shadow(
              color: Colors.black87,
              blurRadius: 2,
              offset: Offset(0, 1),
            ),
          ],
        ),
      ),
    );

    return Positioned(
      left: 0,
      top: item.top + config.topPadding,
      child: AnimatedBuilder(
        animation: ticker,
        child: child,
        builder: (context, child) {
          final left = itemLeft();
          if (left == null) return const SizedBox.shrink();
          return Transform.translate(
            offset: Offset(left, 0),
            child: child,
          );
        },
      ),
    );
  }

  double? itemLeft() {
    final effectiveMs = positionProvider().inMilliseconds + config.offsetMs;
    final elapsedMs = effectiveMs - item.timeMs;
    if (item.mode == 4 || item.mode == 5) {
      if (elapsedMs < 0 ||
          elapsedMs > _VideoPlayerPageState._danmuFixedVisibleMs) {
        return null;
      }
      return item.left;
    }
    final speed = config.speed.clamp(0.5, 2.0).toDouble();
    final travelMs = (_VideoPlayerPageState._danmuBaseTravelMs / speed).round();
    if (elapsedMs < 0 || elapsedMs > travelMs) return null;
    final progress = elapsedMs / travelMs;
    final width = item.textWidth <= 0 ? viewportWidth * 0.5 : item.textWidth;
    return viewportWidth - progress * (viewportWidth + width);
  }
}
