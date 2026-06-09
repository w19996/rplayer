part of 'package:player_flutter/main.dart';

enum VideoFitMode { contain, cover, none, fill }

class VideoPlayerPage extends StatefulWidget {
  const VideoPlayerPage({required this.store, required this.item, super.key});

  final AppStore store;
  final MediaItem item;

  @override
  State<VideoPlayerPage> createState() => _VideoPlayerPageState();
}

class _VideoPlayerPageState extends State<VideoPlayerPage> {
  Player? _player;
  VideoController? _controller;
  late MediaItem currentItem = widget.item;
  final subscriptions = <StreamSubscription<dynamic>>[];
  Timer? statusTimer;
  Timer? loadingHideTimer;
  Timer? loadingProgressTimer;
  Duration position = Duration.zero;
  Duration duration = Duration.zero;
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
  bool buffering = false;
  bool loadingVisible = false;
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
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    startStatusTimer();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) init();
    });
  }

  void attachStreams() {
    if (streamsAttached) return;
    streamsAttached = true;
    subscriptions
      ..add(player.stream.position
          .listen((value) => setStateIfMounted(() => position = value)))
      ..add(player.stream.duration.listen((value) {
        setStateIfMounted(() => duration = value);
        widget.store.rememberDuration(currentItem.id, value);
      }))
      ..add(player.stream.playing
          .listen((value) => setStateIfMounted(() => playing = value)))
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
      await widget.store.updateProgress(currentItem.id, position, duration);
      final source = widget.store.sources
          .firstWhere((value) => value.id == currentItem.sourceId);
      final saved = widget.store.progress[currentItem.id] ?? 0;
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
        hideLoadingOverlay();
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
    widget.store.updateProgress(currentItem.id, position, duration);
    statusTimer?.cancel();
    loadingHideTimer?.cancel();
    loadingProgressTimer?.cancel();
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
    dragDistance = 0;
    dragStartPosition = position;
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
        () => dragPreviewPosition = Duration(milliseconds: nextMs));
  }

  Future<void> endSeekDrag() async {
    if (controlsLocked) return;
    final target = seekingByDrag ? dragPreviewPosition : null;
    seekingByDrag = false;
    setStateIfMounted(() => dragPreviewPosition = null);
    if (target != null && duration > Duration.zero) {
      await player.seek(target);
    }
  }

  void togglePlayback() {
    if (controlsLocked) return;
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
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  void setFitMode(VideoFitMode value) {
    setStateIfMounted(() => fitMode = value);
  }

  Future<void> showFitModes() async {
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
    final nextMs = (position.inMilliseconds + seconds * 1000)
        .clamp(0, duration.inMilliseconds);
    await player.seek(Duration(milliseconds: nextMs));
  }

  Future<void> rotateScreen(BuildContext context) async {
    if (controlsLocked) return;
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
    setStateIfMounted(() {
      controlsLocked = !controlsLocked;
      if (controlsLocked) {
        fullscreen = true;
        episodePanelOpen = false;
        dragPreviewPosition = null;
        seekingByDrag = false;
      } else {
        fullscreen = false;
      }
    });
  }

  Widget controlIconButton({
    required IconData icon,
    required VoidCallback onPressed,
    double size = 28,
  }) {
    return IconButton(
      color: Colors.white,
      onPressed: onPressed,
      icon: shadowIcon(icon, size: size),
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints.tightFor(width: 42, height: 42),
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
  }

  Future<void> showSubtitleTracks() async {
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
  }

  List<MediaItem> get episodeItems {
    final folderKey = mediaFolderKey(currentItem);
    final items = widget.store.items
        .where((item) =>
            item.sourceId == currentItem.sourceId &&
            mediaFolderKey(item) == folderKey)
        .toList();
    items
        .sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
    return items;
  }

  Future<void> playEpisode(MediaItem item) async {
    if (item.id == currentItem.id) {
      setStateIfMounted(() => episodePanelOpen = false);
      return;
    }
    await widget.store.updateProgress(currentItem.id, position, duration);
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
      selectedTrack = const Track();
      availableTracks = const Tracks();
    });
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
            width: 70,
            height: 70,
            child: Stack(
              alignment: Alignment.center,
              children: [
                const SizedBox(
                  width: 58,
                  height: 58,
                  child: CircularProgressIndicator(
                    strokeWidth: 5,
                    strokeCap: StrokeCap.round,
                    color: Colors.white,
                  ),
                ),
                Text('$percent%',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
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
                  width: isLandscape ? 120 : 58,
                  child: statusText(clockText,
                      size: isLandscape ? 15 : 13, weight: FontWeight.w700)),
              const Spacer(),
              if (isLandscape) ...[
                statusText(networkSpeed, size: 13),
                const SizedBox(width: 12),
              ],
              shadowIcon(Icons.signal_cellular_alt,
                  size: isLandscape ? 18 : 15),
              const SizedBox(width: 6),
              statusText(network,
                  size: isLandscape ? 14 : 12, weight: FontWeight.w700),
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
      left: isLandscape ? 44 : 4,
      right: isLandscape ? 24 : 92,
      top: isLandscape ? 36 : 28,
      child: Row(
        children: [
          IconButton(
            color: Colors.white,
            onPressed: () => Navigator.of(context).maybePop(),
            icon: shadowIcon(Icons.chevron_left, size: isLandscape ? 34 : 28),
            padding: EdgeInsets.zero,
            constraints: BoxConstraints.tightFor(
                width: isLandscape ? 48 : 40, height: isLandscape ? 48 : 40),
          ),
          Expanded(
            child: Text(
              currentItem.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  color: Colors.white,
                  fontSize: isLandscape ? 22 : 16,
                  fontWeight: FontWeight.w700,
                  shadows: controlShadows),
            ),
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
          size: isLandscape ? 28 : 24),
      controlIconButton(
          icon: Icons.fit_screen_outlined,
          onPressed: showFitModes,
          size: isLandscape ? 28 : 24),
    ];
    return Positioned(
      left: isLandscape ? 32 : 10,
      top: isLandscape ? math.max(96, constraints.maxHeight * 0.35) : 76,
      child: isLandscape
          ? Column(
              children: [buttons[0], const SizedBox(height: 34), buttons[1]])
          : Row(children: [buttons[0], const SizedBox(width: 8), buttons[1]]),
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
        size: isLandscape ? 30 : 25,
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
              onTap: () => setStateIfMounted(() => episodePanelOpen = false),
              child: const ColoredBox(color: Color(0x66000000)),
            ),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: Container(
              width: panelWidth,
              height: double.infinity,
              padding: EdgeInsets.fromLTRB(
                  isLandscape ? 22 : 16, 18, isLandscape ? 30 : 16, 20),
              decoration: const BoxDecoration(
                color: Color(0xE81F1F24),
                border: Border(left: BorderSide(color: Color(0x55FFFFFF))),
              ),
              child: SafeArea(
                left: false,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('第 1 季（共 ${items.length} 集）',
                        style: TextStyle(
                            color: Colors.white70,
                            fontSize: isLandscape ? 15 : 13)),
                    SizedBox(height: isLandscape ? 28 : 16),
                    Expanded(
                      child: ListView.separated(
                        itemCount: items.length,
                        separatorBuilder: (_, __) =>
                            SizedBox(height: isLandscape ? 12 : 8),
                        itemBuilder: (context, index) {
                          final item = items[index];
                          final selected = item.id == currentItem.id;
                          return InkWell(
                            borderRadius: BorderRadius.circular(9),
                            onTap: () => playEpisode(item),
                            child: Container(
                              padding: EdgeInsets.symmetric(
                                  horizontal: isLandscape ? 16 : 12,
                                  vertical: isLandscape ? 15 : 11),
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
                                      size: 24),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      '${index + 1}. ${item.title}',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                          color: Colors.white,
                                          fontSize: isLandscape ? 18 : 14),
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
        ],
      ),
    );
  }

  Widget buildSeekButton(int seconds) {
    return IconButton(
      color: Colors.white,
      onPressed: () => seekRelative(seconds),
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints.tightFor(width: 44, height: 44),
      icon: Stack(
        alignment: Alignment.center,
        children: [
          shadowIcon(seconds < 0 ? Icons.replay_10 : Icons.forward_10,
              size: 40),
        ],
      ),
    );
  }

  Widget buildBottomControls(
      BuildContext context, BoxConstraints constraints, bool isLandscape) {
    final compact = !isLandscape || constraints.maxWidth < 740;
    final playButton = IconButton(
      color: Colors.white,
      iconSize: compact ? 44 : 52,
      padding: EdgeInsets.zero,
      constraints: BoxConstraints.tightFor(
          width: compact ? 52 : 60, height: compact ? 52 : 60),
      onPressed: togglePlayback,
      icon: Icon(playing ? Icons.pause : Icons.play_arrow,
          shadows: controlShadows),
    );
    final audioButton = controlIconButton(
        icon: Icons.graphic_eq,
        onPressed: showAudioTracks,
        size: compact ? 27 : 31);
    final subtitleButton = controlIconButton(
        icon: Icons.closed_caption_outlined,
        onPressed: showSubtitleTracks,
        size: compact ? 27 : 31);
    final episodeButton = controlIconButton(
      icon: Icons.format_list_bulleted_rounded,
      onPressed: () => setStateIfMounted(() => episodePanelOpen = true),
      size: compact ? 28 : 32,
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
                        size: compact ? 12 : 18)),
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
                      onChanged: (value) =>
                          player.seek(Duration(milliseconds: value.toInt())),
                    ),
                  ),
                ),
                SizedBox(
                  width: compact ? 56 : 92,
                  child: Align(
                      alignment: Alignment.centerRight,
                      child: statusText(formatDuration(duration),
                          size: compact ? 12 : 18)),
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
                  statusText('1.0x', size: 13),
                  statusText(fitShortLabel, size: 13),
                  audioButton,
                  subtitleButton,
                  episodeButton,
                ],
              ),
            ] else
              Row(
                children: [
                  SizedBox(width: 66, child: statusText('1.0x', size: 16)),
                  SizedBox(
                      width: 66, child: statusText(fitShortLabel, size: 16)),
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
                              fontSize: 18,
                              fontWeight: FontWeight.w600),
                        ),
                      ),
                    ),
                  ),
                if (!fullscreen && !controlsLocked)
                  buildBottomControls(context, constraints, isLandscape),
                if (episodePanelOpen)
                  buildEpisodePanel(constraints, isLandscape),
              ],
            ),
          );
        },
      ),
    );
  }
}
