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

  Player? _player;
  VideoController? _controller;
  late MediaItem currentItem = widget.item;
  final subscriptions = <StreamSubscription<dynamic>>[];
  Timer? statusTimer;
  Timer? loadingHideTimer;
  Timer? loadingProgressTimer;
  Timer? controlsHideTimer;
  Timer? danmuRenderTimer;
  late final AnimationController danmuTicker;
  final danmuOverlayItems = ValueNotifier<List<RustDanmuRenderItem>>(const []);
  final danmuTextLayoutCache = <String, _DanmuTextLayout>{};
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
  bool softwareDecoderFallback = false;
  bool fullscreen = false;
  bool controlsLocked = false;
  bool episodePanelOpen = false;
  bool episodePanelClosing = false;
  bool danmuPanelOpen = false;
  bool danmuPanelClosing = false;
  bool buffering = false;
  bool loadingVisible = false;
  bool danmuLoading = false;
  VideoFitMode fitMode = VideoFitMode.contain;
  Tracks availableTracks = const Tracks();
  Track selectedTrack = const Track();
  double bufferingPercentage = 0;
  double loadingDisplayPercent = 0;
  double loadingTargetPercent = 0;
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
    )..repeat();
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
    setStateIfMounted(() {});
  }

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
        danmuStatus = '未配置弹幕 API';
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
    danmuTextLayoutCache.clear();
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
  }

  void startDanmuRenderTimer() {
    danmuRenderTimer?.cancel();
    danmuRenderTimer = Timer.periodic(const Duration(milliseconds: 1500), (_) {
      refreshVisibleDanmu();
    });
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

  void refreshVisibleDanmu() {
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
    if (!playing && danmuOverlayItems.value.isNotEmpty) {
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
        'max_items': 56,
      });
      if (!sameDanmuItems(danmuOverlayItems.value, items)) {
        danmuOverlayItems.value = items;
      }
    } catch (error) {
      widget.store
          .addDiagnosticLog('danmu visible failed: $error', category: 'danmu');
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
        syncDanmuClockFromPlayer(value);
        setStateIfMounted(() => position = value);
      }))
      ..add(player.stream.duration.listen((value) {
        setStateIfMounted(() => duration = value);
        widget.store.rememberDuration(currentItem.id, value);
      }))
      ..add(player.stream.playing.listen((value) {
        syncDanmuClock(currentDanmuPosition);
        setStateIfMounted(() => playing = value);
      }))
      ..add(player.stream.buffering.listen(handleBufferingChanged))
      ..add(player.stream.bufferingPercentage.listen(handleBufferingPercentage))
      ..add(player.stream.width.listen((value) {
        videoWidth = value;
        applyVideoOrientation();
      }))
      ..add(player.stream.height.listen((value) {
        videoHeight = value;
        applyVideoOrientation();
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
    if (resetCodecRetry) {
      transientCodecRetryCount = 0;
      softwareDecoderFallback = false;
    }
    try {
      attachStreams();
      setState(() {
        error = null;
        ready = false;
        buffering = true;
        loadingVisible = true;
        bufferingPercentage = 0;
        loadingDisplayPercent = 0;
        loadingTargetPercent = 0;
      });
      startLoadingProgressTimer();
      await applyRememberedOrientation();
      final source = widget.store.sources
          .firstWhere((value) => value.id == currentItem.sourceId);
      final saved = widget.store.progress[currentItem.id] ?? 0;
      if (saved > 0) {
        final savedPosition = Duration(milliseconds: saved);
        position = savedPosition;
        syncDanmuClock(savedPosition);
      }
      final uri = currentItem.type == SourceType.local
          ? Uri.file(currentItem.uri).toString()
          : currentItem.uri;
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
      openedOnce = true;
      if (attempt == openAttempt) {
        setStateIfMounted(() {
          ready = true;
          buffering = false;
        });
        syncDanmuClock(position);
        refreshVisibleDanmu();
        hideLoadingOverlay();
        scheduleControlsAutoHide();
      }
    } catch (e) {
      if (automaticRetry && canRetryTransientCodec(e)) {
        await retryTransientCodec(attempt);
        return;
      }
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

  @override
  void dispose() {
    widget.store.removeListener(handleStoreChanged);
    widget.store.updateProgress(currentItem.id, position, duration);
    statusTimer?.cancel();
    loadingHideTimer?.cancel();
    loadingProgressTimer?.cancel();
    controlsHideTimer?.cancel();
    danmuRenderTimer?.cancel();
    clearDanmuSession();
    danmuTicker.dispose();
    danmuOverlayItems.dispose();
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.manual,
        overlays: SystemUiOverlay.values);
    for (final subscription in subscriptions) {
      subscription.cancel();
    }
    _player?.dispose();
    super.dispose();
  }

  void setStateIfMounted(VoidCallback update) {
    if (mounted) setState(update);
  }

  void showLoadingOverlay() {
    loadingHideTimer?.cancel();
    if (!loadingVisible) {
      setStateIfMounted(() => loadingVisible = true);
    }
    startLoadingProgressTimer();
  }

  void hideLoadingOverlay() {
    loadingHideTimer?.cancel();
    loadingHideTimer = Timer(const Duration(milliseconds: 260), () {
      loadingProgressTimer?.cancel();
      setStateIfMounted(() => loadingVisible = false);
    });
  }

  void handleBufferingChanged(bool value) {
    syncDanmuClock(currentDanmuPosition);
    setStateIfMounted(() => buffering = value);
    if (value) {
      showLoadingOverlay();
    } else if (ready) {
      hideLoadingOverlay();
    }
  }

  void handleBufferingPercentage(double value) {
    if (!value.isFinite) return;
    final target = value.clamp(0, ready ? 99 : 96).toDouble();
    setStateIfMounted(() {
      bufferingPercentage = value;
      if (target > loadingTargetPercent) {
        loadingTargetPercent = target;
      }
    });
    if (loadingVisible) startLoadingProgressTimer();
  }

  void startLoadingProgressTimer() {
    if (loadingProgressTimer?.isActive ?? false) return;
    loadingProgressTimer =
        Timer.periodic(const Duration(milliseconds: 120), (_) {
      if (!mounted || !loadingVisible) return;
      setState(() {
        final softCeiling = ready ? 99.0 : 96.0;
        final target = math.max(
          loadingTargetPercent,
          math.min(softCeiling, loadingDisplayPercent + 1.2),
        );
        if (loadingDisplayPercent < target) {
          final gap = target - loadingDisplayPercent;
          loadingDisplayPercent += gap.clamp(0.35, 2.2).toDouble();
          if (loadingDisplayPercent > softCeiling) {
            loadingDisplayPercent = softCeiling;
          }
        }
      });
    });
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
    if (transientCodecRetryCount >= 2) softwareDecoderFallback = true;
    await Future<void>.delayed(const Duration(milliseconds: 450));
    if (!mounted || attempt != openAttempt) return;
    await player.stop();
    await init(automaticRetry: true, resetCodecRetry: false);
  }

  Future<void> handlePlayerError(Object value) async {
    final attempt = openAttempt;
    if (canRetryTransientCodec(value)) {
      await retryTransientCodec(attempt);
      return;
    }
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
    if (fullscreen || controlsLocked || episodePanelOpen || danmuPanelOpen) {
      return;
    }
    controlsHideTimer = Timer(const Duration(seconds: 5), () {
      if (!mounted || controlsLocked || episodePanelOpen || danmuPanelOpen) {
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
    syncDanmuClock(Duration.zero);
    clearDanmuOverlay();
    clearDanmuSession();
    setStateIfMounted(() {
      currentItem = item;
      position = Duration.zero;
      duration = Duration.zero;
      videoWidth = null;
      videoHeight = null;
      ready = false;
      buffering = true;
      loadingVisible = true;
      bufferingPercentage = 0;
      error = null;
      episodePanelOpen = false;
      episodePanelClosing = false;
      danmuPanelOpen = false;
      danmuPanelClosing = false;
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
    final percent = loadingDisplayPercent.clamp(0, 99).round();
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
    return Positioned(
      left: isLandscape ? 32 : 4,
      right: isLandscape ? 24 : 92,
      top: isLandscape ? 28 : 28,
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
      left: isLandscape ? 32 : 10,
      top: isLandscape ? math.max(96, constraints.maxHeight * 0.35) : 76,
      child: isLandscape
          ? Column(
              children: [buttons[0], const SizedBox(height: 28), buttons[1]])
          : Row(children: [buttons[0], const SizedBox(width: 6), buttons[1]]),
    );
  }

  Widget buildLockButton(BoxConstraints constraints, bool isLandscape) {
    return Positioned(
      right: isLandscape ? 34 : 12,
      top: controlsLocked
          ? (isLandscape ? math.max(82, constraints.maxHeight * 0.44) : 86)
          : (isLandscape ? math.max(104, constraints.maxHeight * 0.36) : 76),
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
                          title: const Text('启用弹幕',
                              style: TextStyle(color: Colors.white)),
                          value: config.enabled,
                          onChanged: (value) {
                            unawaited(widget.store.setDanmuConfig(
                                config.copyWith(enabled: value)));
                            if (value) unawaited(loadDanmuForCurrentItem());
                          },
                        ),
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
                        const SizedBox(height: 14),
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
            return RepaintBoundary(
              child: CustomPaint(
                painter: _DanmuOverlayPainter(
                  items: items,
                  config: config,
                  layoutCache: danmuTextLayoutCache,
                  positionProvider: () => currentDanmuPosition,
                  repaint: danmuTicker,
                ),
                isComplex: true,
                willChange: true,
                child: const SizedBox.expand(),
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
    final compact = !isLandscape || constraints.maxWidth < 740;
    final playButton = IconButton(
      color: Colors.white,
      iconSize: compact ? 38 : 46,
      padding: EdgeInsets.zero,
      constraints: BoxConstraints.tightFor(
          width: compact ? 46 : 54, height: compact ? 46 : 54),
      onPressed: togglePlayback,
      icon: Icon(playing ? Icons.pause : Icons.play_arrow,
          shadows: controlShadows),
    );
    final audioButton = controlIconButton(
        icon: Icons.graphic_eq,
        onPressed: showAudioTracks,
        size: compact ? 23 : 27);
    final subtitleButton = controlIconButton(
        icon: Icons.closed_caption_outlined,
        onPressed: showSubtitleTracks,
        size: compact ? 23 : 27);
    final episodeButton = controlIconButton(
      icon: Icons.format_list_bulleted_rounded,
      onPressed: openEpisodePanel,
      size: compact ? 24 : 28,
    );

    return Positioned(
      left: compact ? 12 : 56,
      right: compact ? 12 : 56,
      bottom: compact ? 10 : 14,
      child: IconTheme.merge(
        data: controlIconTheme,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                SizedBox(
                    width: compact ? 48 : 78,
                    child: statusText(formatDuration(position),
                        size: compact ? 11 : 15)),
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
                  width: compact ? 56 : 92,
                  child: Align(
                      alignment: Alignment.centerRight,
                      child: statusText(formatDuration(duration),
                          size: compact ? 11 : 15)),
                ),
              ],
            ),
            SizedBox(height: compact ? 6 : 12),
            if (compact) ...[
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  buildSeekButton(-10),
                  const SizedBox(width: 6),
                  playButton,
                  const SizedBox(width: 6),
                  buildSeekButton(10),
                ],
              ),
              const SizedBox(height: 4),
              Wrap(
                alignment: WrapAlignment.center,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 14,
                runSpacing: 2,
                children: [
                  statusText('1.0x', size: 12),
                  statusText(fitShortLabel, size: 12),
                  audioButton,
                  subtitleButton,
                  episodeButton,
                ],
              ),
            ] else
              Row(
                children: [
                  SizedBox(width: 60, child: statusText('1.0x', size: 14)),
                  SizedBox(
                      width: 60, child: statusText(fitShortLabel, size: 14)),
                  const Spacer(),
                  buildSeekButton(-10),
                  const SizedBox(width: 8),
                  playButton,
                  const SizedBox(width: 8),
                  buildSeekButton(10),
                  const Spacer(),
                  audioButton,
                  const SizedBox(width: 12),
                  subtitleButton,
                  const SizedBox(width: 12),
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
                  buildLockButton(constraints, isLandscape),
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

class _DanmuOverlayPainter extends CustomPainter {
  _DanmuOverlayPainter({
    required this.items,
    required this.config,
    required this.layoutCache,
    required this.positionProvider,
    required Listenable repaint,
  }) : super(repaint: repaint) {
    _runs = items
        .map((item) => _DanmuPaintRun(
              item: item,
              layout: _layoutFor(item),
            ))
        .toList(growable: false);
    _pruneLayoutCache();
  }

  final List<RustDanmuRenderItem> items;
  final DanmuConfig config;
  final Map<String, _DanmuTextLayout> layoutCache;
  final Duration Function() positionProvider;
  late final List<_DanmuPaintRun> _runs;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0 || _runs.isEmpty) return;
    final effectiveMs = positionProvider().inMilliseconds + config.offsetMs;
    for (final run in _runs) {
      final left = _itemLeft(run, effectiveMs, size.width);
      if (left == null) continue;
      run.layout.painter.paint(canvas, Offset(left, run.item.top));
    }
  }

  @override
  bool shouldRepaint(covariant _DanmuOverlayPainter oldDelegate) {
    return !identical(items, oldDelegate.items) ||
        config.visible != oldDelegate.config.visible ||
        config.fontSize != oldDelegate.config.fontSize ||
        config.opacity != oldDelegate.config.opacity ||
        config.speed != oldDelegate.config.speed ||
        config.offsetMs != oldDelegate.config.offsetMs;
  }

  _DanmuTextLayout _layoutFor(RustDanmuRenderItem item) {
    final key = _danmuTextLayoutKey(item, config);
    final cached = layoutCache[key];
    if (cached != null) return cached;
    final color = Color(0xFF000000 | item.color)
        .withValues(alpha: config.opacity.clamp(0.0, 1.0).toDouble());
    final painter = TextPainter(
      text: TextSpan(
        text: item.text,
        style: TextStyle(
          color: color,
          fontSize: config.fontSize,
          fontWeight: FontWeight.w700,
          shadows: const [
            Shadow(color: Colors.black87, blurRadius: 2, offset: Offset(0, 1)),
          ],
        ),
      ),
      maxLines: 1,
      textDirection: TextDirection.ltr,
      textScaler: TextScaler.noScaling,
    )..layout();
    final layout = _DanmuTextLayout(
      painter: painter,
      width: math.max(item.textWidth, painter.width),
    );
    layoutCache[key] = layout;
    return layout;
  }

  void _pruneLayoutCache() {
    if (layoutCache.length <= 180) return;
    final activeKeys =
        items.map((item) => _danmuTextLayoutKey(item, config)).toSet();
    layoutCache.removeWhere((key, _) => !activeKeys.contains(key));
  }

  double? _itemLeft(_DanmuPaintRun run, int effectiveMs, double viewportWidth) {
    final item = run.item;
    final elapsedMs = effectiveMs - item.timeMs;
    if (item.mode == 4 || item.mode == 5) {
      if (elapsedMs < 0 || elapsedMs > 3800) return null;
      return item.left;
    }
    final speed = config.speed.clamp(0.5, 2.0).toDouble();
    final travelMs = (9500 / speed).round();
    if (elapsedMs < 0 || elapsedMs > travelMs) return null;
    final progress = elapsedMs / travelMs;
    final width =
        run.layout.width <= 0 ? viewportWidth * 0.5 : run.layout.width;
    return viewportWidth - progress * (viewportWidth + width);
  }
}

class _DanmuPaintRun {
  const _DanmuPaintRun({required this.item, required this.layout});

  final RustDanmuRenderItem item;
  final _DanmuTextLayout layout;
}

class _DanmuTextLayout {
  const _DanmuTextLayout({required this.painter, required this.width});

  final TextPainter painter;
  final double width;
}

String _danmuTextLayoutKey(RustDanmuRenderItem item, DanmuConfig config) {
  return '${item.id}|${item.color}|${config.fontSize.toStringAsFixed(2)}|'
      '${config.opacity.toStringAsFixed(2)}|${item.text}';
}
