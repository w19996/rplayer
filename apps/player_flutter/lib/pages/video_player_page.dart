part of 'package:player_flutter/main.dart';

enum VideoFitMode { contain, cover, none, fill }

class VideoPlayerPage extends StatefulWidget {
  const VideoPlayerPage({required this.store, required this.item, super.key});

  final AppStore store;
  final MediaItem item;

  @override
  State<VideoPlayerPage> createState() => _VideoPlayerPageState();
}

class _VideoPlayerPageState extends State<VideoPlayerPage>
    with SingleTickerProviderStateMixin {
  static const Duration _danmuPositionSyncThreshold =
      Duration(milliseconds: 650);
  static const Duration _danmuVisibleRefreshInterval =
      Duration(milliseconds: 1500);
  static const int _danmuMaxVisibleItems = 36;
  static const int _danmuFixedVisibleMs = 3800;
  static const double _danmuBaseTravelMs = 9500;

  Player? _player;
  VideoController? _controller;
  late MediaItem currentItem = widget.item;
  final subscriptions = <StreamSubscription<dynamic>>[];
  Timer? statusTimer;
  Timer? loadingHideTimer;
  Timer? controlsHideTimer;
  Timer? danmuRenderTimer;
  late final AnimationController danmuTicker;
  final danmuOverlayItems = ValueNotifier<List<RustDanmuRenderItem>>(const []);
  Duration position = Duration.zero;
  Duration duration = Duration.zero;
  Duration danmuClockPosition = Duration.zero;
  DateTime danmuClockStamp = DateTime.now();
  Duration? dragPreviewPosition;
  double dragDistance = 0;
  Duration dragStartPosition = Duration.zero;
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
  bool softwareDecoderFallback = false;
  bool fullscreen = false;
  bool controlsLocked = false;
  bool episodePanelOpen = false;
  bool episodePanelClosing = false;
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
  VideoFitMode fitMode = VideoFitMode.contain;
  Tracks availableTracks = const Tracks();
  Track selectedTrack = const Track();
  double bufferingPercentage = 0;
  int transientCodecRetryCount = 0;
  int openAttempt = 0;
  int battery = -1;
  int? lastRxBytes;
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
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
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
      refreshVisibleDanmu();
    });
  }

  void syncDanmuTickerState() {
    if (!mounted) return;
    final config = widget.store.danmuConfig;
    final shouldAnimate = ready &&
        playing &&
        !buffering &&
        !seekingByDrag &&
        danmuSessionId > 0 &&
        config.available &&
        config.visible &&
        danmuOverlayItems.value.isNotEmpty;
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
    final config = widget.store.danmuConfig;
    if (!mounted ||
        !ready ||
        danmuSessionId <= 0 ||
        !config.available ||
        !config.visible ||
        danmuTotalCount <= 0) {
      clearDanmuOverlay();
      return;
    }
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
        setStateIfMounted(() => position = value);
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
        setStateIfMounted(() => duration = value);
        widget.store.rememberDuration(currentItem.id, value);
      }))
      ..add(player.stream.playing.listen((value) {
        if (!ready) {
          logVideoLoading('playing ignored before ready: $value');
          return;
        }
        syncDanmuClock(currentDanmuPosition);
        setStateIfMounted(() => playing = value);
        syncDanmuTickerState();
      }))
      ..add(player.stream.buffering.listen(handleBufferingChanged))
      ..add(player.stream.bufferingPercentage.listen(handleBufferingPercentage))
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
      attachStreams();
      await attachMpvLoadingProperties();
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
      });
      await applyRememberedOrientation();
      final source = widget.store.sources
          .firstWhere((value) => value.id == currentItem.sourceId);
      if (saved > 0) {
        final savedPosition = Duration(milliseconds: saved);
        syncDanmuClock(savedPosition);
      }
      final uri = currentItem.type == SourceType.local
          ? Uri.file(currentItem.uri).toString()
          : currentItem.uri;
      updateLoadingPercent(
          math.max(initialBufferingPercentage, 12), 'open start');
      logVideoLoading(
          'open start attempt=$attempt item=${currentItem.id} uri=$uri saved=${saved}ms');
      await configureDecoder();
      if (openedOnce) {
        await player.stop();
        await Future<void>.delayed(const Duration(milliseconds: 120));
      }
      await player.open(
        Media(
          uri,
          httpHeaders: source.headers.isEmpty ? null : source.headers,
          start: saved > 0 ? Duration(milliseconds: saved) : null,
        ),
      );
      logVideoLoading(
          'open returned attempt=$attempt stateBuffering=${player.state.buffering} statePlaying=${player.state.playing} width=${player.state.width} height=${player.state.height} position=${player.state.position.inMilliseconds}ms duration=${player.state.duration.inMilliseconds}ms');
      openedOnce = true;
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

  Future<void> configureDecoder() async {
    try {
      final native = player.platform as dynamic;
      await native.setProperty(
          'hwdec', softwareDecoderFallback ? 'no' : 'auto-safe');
      await native.setProperty('vd-lavc-threads', '0');
      await native.setProperty('video-sync', 'audio');
      await native.setProperty('framedrop', 'vo');
    } catch (_) {
      // Non-native platforms or older media_kit backends may not expose mpv properties.
    }
  }

  Future<void> attachMpvLoadingProperties() async {
    if (mpvLoadingPropertiesAttached) return;
    mpvLoadingPropertiesAttached = true;
    try {
      final native = player.platform as dynamic;
      var observedAny = false;
      await native.observeProperty(
        'vo-configured',
        (String value) async {
          final configured = mpvBoolValue(value);
          logVideoLoading('mpv vo-configured: $value');
          if (!mounted) return;
          setStateIfMounted(() => voConfigured = configured);
          if (configured) updateLoadingPercent(82, 'vo configured');
          maybeMarkPlaybackReady();
        },
      );
      observedAny = true;
      await native.observeProperty(
        'paused-for-cache',
        (String value) async {
          final paused = mpvBoolValue(value);
          logVideoLoading('mpv paused-for-cache: $value');
          if (!mounted) return;
          setStateIfMounted(() => pausedForCache = paused);
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

  @override
  void dispose() {
    widget.store.removeListener(handleStoreChanged);
    widget.store.updateProgress(currentItem.id, position, duration);
    statusTimer?.cancel();
    loadingHideTimer?.cancel();
    controlsHideTimer?.cancel();
    danmuRenderTimer?.cancel();
    clearDanmuSession();
    danmuTicker.dispose();
    danmuOverlayItems.dispose();
    danmuSearchController.dispose();
    danmuSearchEpisodeController.dispose();
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.manual,
        overlays: SystemUiOverlay.values);
    for (final subscription in subscriptions) {
      subscription.cancel();
    }
    unawaited(unobserveMpvLoadingProperties());
    _player?.dispose();
    super.dispose();
  }

  void setStateIfMounted(VoidCallback update) {
    if (mounted) setState(update);
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
    final percent = value.clamp(0, 100).toDouble();
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
    if (!mounted || ready || error != null) return;
    if (attempt != null && attempt != openAttempt) return;
    if (!mediaOpenCompleted || buffering || pausedForCache) return;
    if (mpvLoadingPropertiesUsable && !voConfigured) return;
    if (!hasRenderableVideo) return;
    if (!playbackPositionConfirmed) return;
    final state = player.state;
    setState(() {
      ready = true;
      playing = state.playing;
      position = state.position;
      if (state.duration > Duration.zero) duration = state.duration;
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

  Future<void> retryTransientCodec(int attempt) async {
    transientCodecRetryCount++;
    softwareDecoderFallback = true;
    logVideoLoading(
        'transient codec retry: sourceAttempt=$attempt retry=$transientCodecRetryCount softwareFallback=$softwareDecoderFallback');
    await Future<void>.delayed(const Duration(milliseconds: 450));
    if (!mounted || attempt != openAttempt) return;
    await player.stop();
    await init(automaticRetry: true, resetCodecRetry: false);
  }

  Future<void> handlePlayerError(Object value) async {
    final attempt = openAttempt;
    if (canRetryTransientCodec(value)) {
      logVideoLoading('player stream error retryable attempt=$attempt: $value');
      await retryTransientCodec(attempt);
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
    await widget.store.rememberFolderOrientation(currentItem, landscape);
    await SystemChrome.setPreferredOrientations(
      landscape
          ? [DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]
          : [DeviceOrientation.portraitUp, DeviceOrientation.portraitDown],
    );
  }

  Future<void> applyRememberedOrientation() async {
    final remembered =
        widget.store.folderOrientations[mediaFolderKey(currentItem)];
    if (remembered == null) {
      orientationLocked = false;
      return;
    }
    orientationLocked = true;
    await SystemChrome.setPreferredOrientations(
      remembered == 'landscape'
          ? [DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]
          : [DeviceOrientation.portraitUp, DeviceOrientation.portraitDown],
    );
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
    setStateIfMounted(
        () => dragPreviewPosition = Duration(milliseconds: nextMs.toInt()));
  }

  Future<void> endSeekDrag() async {
    if (controlsLocked) return;
    final target = seekingByDrag ? dragPreviewPosition : null;
    seekingByDrag = false;
    setStateIfMounted(() => dragPreviewPosition = null);
    if (target != null && duration > Duration.zero) {
      syncDanmuClock(target);
      clearDanmuOverlay();
      await player.seek(target);
    }
    syncDanmuTickerState();
    scheduleControlsAutoHide();
  }

  void togglePlayback() {
    if (controlsLocked) return;
    markControlsInteraction();
    syncDanmuClock(currentDanmuPosition);
    playing ? player.pause() : player.play();
  }

  BoxFit get videoFit => switch (fitMode) {
        VideoFitMode.contain => BoxFit.contain,
        VideoFitMode.cover => BoxFit.cover,
        VideoFitMode.none => BoxFit.none,
        VideoFitMode.fill => BoxFit.fill,
      };

  Future<void> toggleFullscreen() async {
    if (controlsLocked) return;
    final next = !fullscreen;
    setStateIfMounted(() => fullscreen = next);
    if (next) {
      controlsHideTimer?.cancel();
    } else {
      scheduleControlsAutoHide();
    }
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  void scheduleControlsAutoHide() {
    controlsHideTimer?.cancel();
    if (fullscreen ||
        controlsLocked ||
        episodePanelOpen ||
        danmuPanelOpen ||
        danmuSearchPanelOpen) {
      return;
    }
    controlsHideTimer = Timer(const Duration(seconds: 5), () {
      if (!mounted ||
          controlsLocked ||
          episodePanelOpen ||
          danmuPanelOpen ||
          danmuSearchPanelOpen) {
        return;
      }
      setState(() => fullscreen = true);
    });
  }

  void markControlsInteraction() {
    if (!fullscreen &&
        !controlsLocked &&
        !episodePanelOpen &&
        !danmuPanelOpen) {
      scheduleControlsAutoHide();
    }
  }

  void setFitMode(VideoFitMode value) {
    setStateIfMounted(() => fitMode = value);
    scheduleControlsAutoHide();
  }

  Future<void> showFitModes() async {
    controlsHideTimer?.cancel();
    Widget option(VideoFitMode mode, String label) {
      final selected = fitMode == mode;
      return ListTile(
        title: Text(label, style: const TextStyle(color: Colors.white)),
        trailing:
            selected ? const Icon(Icons.check, color: Colors.white) : null,
        onTap: () => Navigator.pop(context, mode),
      );
    }

    final selected = await showModalBottomSheet<VideoFitMode>(
      context: context,
      backgroundColor: const Color(0xEE1F1F25),
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const ListTile(
                title: Text('画面尺寸',
                    style: TextStyle(
                        color: Colors.white, fontWeight: FontWeight.w700))),
            option(VideoFitMode.contain, '内容居中'),
            option(VideoFitMode.cover, '居中裁切'),
            option(VideoFitMode.none, '原始尺寸'),
            option(VideoFitMode.fill, '铺满屏幕'),
          ],
        ),
      ),
    );
    if (selected != null) setFitMode(selected);
    if (selected == null) scheduleControlsAutoHide();
  }

  void startStatusTimer() {
    updatePlayerStatus();
    statusTimer =
        Timer.periodic(const Duration(seconds: 1), (_) => updatePlayerStatus());
  }

  Future<void> updatePlayerStatus() async {
    if (!Platform.isAndroid) return;
    try {
      final status =
          await appChannel.invokeMapMethod<String, dynamic>('playerStatus');
      if (status == null) return;
      final rx = (status['rxBytes'] as num?)?.toInt();
      final previous = lastRxBytes;
      lastRxBytes = rx;
      final nextBattery = (status['battery'] as num?)?.toInt();
      setStateIfMounted(() {
        if (nextBattery != null && nextBattery >= 0) {
          battery = nextBattery.clamp(0, 100);
        }
        charging = status['charging'] == true;
        network = status['network'] as String? ?? network;
        if (rx != null && previous != null && rx >= previous) {
          networkSpeed = formatNetworkSpeed(rx - previous);
        }
      });
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

  Future<void> seekRelative(int seconds) async {
    if (controlsLocked) return;
    if (duration == Duration.zero) return;
    markControlsInteraction();
    final nextMs = (position.inMilliseconds + seconds * 1000)
        .clamp(0, duration.inMilliseconds);
    final target = Duration(milliseconds: nextMs.toInt());
    syncDanmuClock(target);
    clearDanmuOverlay();
    await player.seek(target);
  }

  Future<void> rotateScreen(BuildContext context) async {
    if (controlsLocked) return;
    markControlsInteraction();
    final size = MediaQuery.sizeOf(context);
    final landscape = size.width > size.height;
    orientationLocked = true;
    await widget.store.rememberFolderOrientation(currentItem, !landscape);
    await SystemChrome.setPreferredOrientations(
      landscape
          ? [DeviceOrientation.portraitUp, DeviceOrientation.portraitDown]
          : [DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight],
    );
  }

  void toggleLock() {
    final unlocking = controlsLocked;
    setStateIfMounted(() {
      controlsLocked = !controlsLocked;
      if (controlsLocked) {
        controlsHideTimer?.cancel();
        fullscreen = true;
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
        fullscreen = false;
        scheduleControlsAutoHide();
      }
    });
    if (unlocking) scheduleControlsAutoHide();
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
    if (playing) player.pause();
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
      if (shouldResume) player.play();
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

  Future<void> showAudioTracks() async {
    controlsHideTimer?.cancel();
    final tracks = availableTracks.audio;
    final selected = await showModalBottomSheet<AudioTrack>(
      context: context,
      backgroundColor: const Color(0xEE1F1F25),
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const ListTile(
                title: Text('音轨',
                    style: TextStyle(
                        color: Colors.white, fontWeight: FontWeight.w700))),
            for (final track in tracks)
              ListTile(
                title: Text(trackLabel(track, '音轨'),
                    style: const TextStyle(color: Colors.white)),
                trailing: track == selectedTrack.audio
                    ? const Icon(Icons.check, color: Colors.white)
                    : null,
                onTap: () => Navigator.pop(context, track),
              ),
          ],
        ),
      ),
    );
    if (selected != null) await player.setAudioTrack(selected);
    scheduleControlsAutoHide();
  }

  Future<void> showSubtitleTracks() async {
    controlsHideTimer?.cancel();
    final tracks = availableTracks.subtitle;
    final selected = await showModalBottomSheet<SubtitleTrack>(
      context: context,
      backgroundColor: const Color(0xEE1F1F25),
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const ListTile(
                title: Text('字幕',
                    style: TextStyle(
                        color: Colors.white, fontWeight: FontWeight.w700))),
            for (final track in tracks)
              ListTile(
                title: Text(trackLabel(track, '字幕'),
                    style: const TextStyle(color: Colors.white)),
                trailing: track == selectedTrack.subtitle
                    ? const Icon(Icons.check, color: Colors.white)
                    : null,
                onTap: () => Navigator.pop(context, track),
              ),
          ],
        ),
      ),
    );
    if (selected != null) await player.setSubtitleTrack(selected);
    scheduleControlsAutoHide();
  }

  List<MediaItem> get episodeItems {
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
    if (stored != null && stored > 0) return stored;
    final filePosition = dbFileForItem(item)?.positionMs;
    return filePosition != null && filePosition > 0 ? filePosition : 0;
  }

  int rememberedDurationMsFor(MediaItem item) {
    final stored = widget.store.durations[item.id];
    if (stored != null && stored > 0) return stored;
    final fileDuration = dbFileForItem(item)?.durationMs;
    return fileDuration != null && fileDuration > 0 ? fileDuration : 0;
  }

  LibraryFileEntry? get currentDbFile => dbFileForItem(currentItem);

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

  Future<void> playEpisode(MediaItem item) async {
    if (item.id == currentItem.id) {
      closeEpisodePanel();
      return;
    }
    controlsHideTimer?.cancel();
    await widget.store.updateProgress(currentItem.id, position, duration);
    final saved = rememberedPositionMsFor(item);
    final rememberedDuration = rememberedDurationMsFor(item);
    syncDanmuClock(saved > 0 ? Duration(milliseconds: saved) : Duration.zero);
    clearDanmuOverlay();
    clearDanmuSession();
    setStateIfMounted(() {
      currentItem = item;
      position = saved > 0 ? Duration(milliseconds: saved) : Duration.zero;
      duration = rememberedDuration > 0
          ? Duration(milliseconds: rememberedDuration)
          : Duration.zero;
      videoWidth = null;
      videoHeight = null;
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

  List<Shadow> get controlShadows => const [
        Shadow(color: Color(0xCC000000), blurRadius: 8, offset: Offset(0, 1)),
        Shadow(color: Color(0x99000000), blurRadius: 18, offset: Offset(0, 2)),
      ];

  IconThemeData get controlIconTheme =>
      const IconThemeData(color: Colors.white, shadows: [
        Shadow(color: Color(0xCC000000), blurRadius: 8, offset: Offset(0, 1)),
        Shadow(color: Color(0x99000000), blurRadius: 18, offset: Offset(0, 2)),
      ]);

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
            boxShadow: const [
              BoxShadow(color: Color(0x66000000), blurRadius: 6)
            ],
          ),
          child: Align(
            alignment: Alignment.centerLeft,
            child: FractionallySizedBox(
              widthFactor: level / 100,
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
              const SizedBox(width: 8),
              buildBatteryIndicator(),
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
          IconButton(
            color: Colors.white,
            onPressed: openDanmuPanel,
            icon: shadowIcon(Icons.chat_bubble_outline,
                size: isLandscape ? 24 : 21),
            padding: EdgeInsets.zero,
            constraints: BoxConstraints.tightFor(
                width: isLandscape ? 36 : 34, height: isLandscape ? 36 : 34),
          ),
        ],
      ),
    );
  }

  Widget buildSideTools(
      BuildContext context, BoxConstraints constraints, bool isLandscape) {
    final safeTop = MediaQuery.paddingOf(context).top;
    final buttons = [
      controlIconButton(
          icon: Icons.screen_rotation_alt_outlined,
          onPressed: () => rotateScreen(context),
          size: isLandscape ? 24 : 21),
      controlIconButton(
          icon: Icons.fit_screen_outlined,
          onPressed: showFitModes,
          size: isLandscape ? 24 : 21),
    ];
    return Positioned(
      left: isLandscape ? 32 : 20,
      top: isLandscape
          ? math.max(96, constraints.maxHeight * 0.34)
          : safeTop + 92,
      child: isLandscape
          ? Column(
              children: [buttons[0], const SizedBox(height: 28), buttons[1]])
          : Row(children: [buttons[0], const SizedBox(width: 22), buttons[1]]),
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
                          min: -10,
                          max: 10,
                          divisions: 40,
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
                  if (width <= 0) return const SizedBox.shrink();
                  return Stack(
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
                  );
                },
              ),
            );
          },
        ),
      ),
    );
  }

  Widget buildSeekButton(int seconds) {
    return IconButton(
      color: Colors.white,
      onPressed: () => seekRelative(seconds),
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints.tightFor(width: 38, height: 38),
      icon: Stack(
        alignment: Alignment.center,
        children: [
          shadowIcon(seconds < 0 ? Icons.replay_10 : Icons.forward_10,
              size: 34),
        ],
      ),
    );
  }

  Widget buildBottomControls(
      BuildContext context, BoxConstraints constraints, bool isLandscape) {
    final safeBottom = MediaQuery.paddingOf(context).bottom;
    final compact = !isLandscape;
    final denseLandscape = isLandscape && constraints.maxWidth < 740;
    final playButton = IconButton(
      color: Colors.white,
      iconSize: compact ? 40 : (denseLandscape ? 40 : 46),
      padding: EdgeInsets.zero,
      constraints: BoxConstraints.tightFor(
        width: compact ? 50 : (denseLandscape ? 48 : 54),
        height: compact ? 50 : (denseLandscape ? 48 : 54),
      ),
      onPressed: togglePlayback,
      icon: Icon(playing ? Icons.pause : Icons.play_arrow,
          shadows: controlShadows),
    );
    final audioButton = controlIconButton(
        icon: Icons.graphic_eq,
        onPressed: showAudioTracks,
        size: compact || denseLandscape ? 24 : 27);
    final subtitleButton = controlIconButton(
        icon: Icons.closed_caption_outlined,
        onPressed: showSubtitleTracks,
        size: compact || denseLandscape ? 24 : 27);
    final episodeButton = controlIconButton(
      icon: Icons.format_list_bulleted_rounded,
      onPressed: openEpisodePanel,
      size: compact || denseLandscape ? 25 : 28,
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
                    width: compact ? 52 : (denseLandscape ? 58 : 78),
                    child: statusText(formatDuration(position),
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
                      value: position.inMilliseconds
                          .clamp(0, duration.inMilliseconds)
                          .toDouble(),
                      max: duration.inMilliseconds
                          .toDouble()
                          .clamp(1, double.infinity),
                      onChanged: (value) {
                        markControlsInteraction();
                        final target = Duration(milliseconds: value.toInt());
                        syncDanmuClock(target);
                        clearDanmuOverlay();
                        player.seek(target);
                      },
                    ),
                  ),
                ),
                SizedBox(
                  width: compact ? 58 : (denseLandscape ? 64 : 92),
                  child: Align(
                      alignment: Alignment.centerRight,
                      child: statusText(formatDuration(duration),
                          size: compact ? 12 : (denseLandscape ? 13 : 15))),
                ),
              ],
            ),
            SizedBox(height: compact ? 10 : (denseLandscape ? 8 : 12)),
            if (compact) ...[
              SizedBox(
                height: 52,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    buildSeekButton(-10),
                    const SizedBox(width: 18),
                    playButton,
                    const SizedBox(width: 18),
                    buildSeekButton(10),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                height: 38,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    SizedBox(
                        width: 48,
                        child: Center(child: statusText('1.0x', size: 13))),
                    SizedBox(
                        width: 48,
                        child:
                            Center(child: statusText(fitShortLabel, size: 13))),
                    audioButton,
                    subtitleButton,
                    episodeButton,
                  ],
                ),
              ),
            ] else
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  SizedBox(
                      width: denseLandscape ? 48 : 60,
                      child: Center(
                          child: statusText('1.0x',
                              size: denseLandscape ? 13 : 14))),
                  SizedBox(
                      width: denseLandscape ? 48 : 60,
                      child: Center(
                          child: statusText(fitShortLabel,
                              size: denseLandscape ? 13 : 14))),
                  const Spacer(),
                  buildSeekButton(-10),
                  SizedBox(width: denseLandscape ? 6 : 8),
                  playButton,
                  SizedBox(width: denseLandscape ? 6 : 8),
                  buildSeekButton(10),
                  const Spacer(),
                  audioButton,
                  SizedBox(width: denseLandscape ? 8 : 12),
                  subtitleButton,
                  SizedBox(width: denseLandscape ? 8 : 12),
                  episodeButton,
                ],
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final isLandscape = constraints.maxWidth >= constraints.maxHeight;
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onHorizontalDragStart: beginSeekDrag,
            onHorizontalDragUpdate: (details) =>
                updateSeekDrag(details, constraints.maxWidth),
            onHorizontalDragEnd: (_) => endSeekDrag(),
            onHorizontalDragCancel: () {
              seekingByDrag = false;
              setStateIfMounted(() => dragPreviewPosition = null);
              scheduleControlsAutoHide();
            },
            onTap: toggleFullscreen,
            onDoubleTap: togglePlayback,
            child: Stack(
              fit: StackFit.expand,
              children: [
                Center(
                  child: Video(
                    controller: controller,
                    fit: videoFit,
                    controls: NoVideoControls,
                  ),
                ),
                buildDanmuOverlay(),
                if (error == null && loadingVisible) buildLoadingOverlay(),
                if (error != null)
                  ErrorView(message: '$error', onRetry: init, dark: true),
                if (!fullscreen && !controlsLocked)
                  Positioned(
                      left: 0,
                      right: 0,
                      top: 0,
                      child: buildStatusOverlay(isLandscape)),
                if (!fullscreen && !controlsLocked)
                  buildTitleOverlay(context, isLandscape),
                if (!fullscreen && !controlsLocked)
                  buildSideTools(context, constraints, isLandscape),
                if (!fullscreen || controlsLocked)
                  buildLockButton(context, constraints, isLandscape),
                if (!fullscreen &&
                    !controlsLocked &&
                    dragPreviewPosition != null)
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
                if (!fullscreen && !controlsLocked)
                  buildBottomControls(context, constraints, isLandscape),
                if (episodePanelOpen)
                  buildEpisodePanel(constraints, isLandscape),
                if (danmuPanelOpen) buildDanmuPanel(constraints, isLandscape),
                if (danmuSearchPanelOpen)
                  buildDanmuSearchPanel(constraints, isLandscape),
              ],
            ),
          );
        },
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
