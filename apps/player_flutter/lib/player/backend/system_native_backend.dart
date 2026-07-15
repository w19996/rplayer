part of 'package:player_flutter/main.dart';

const androidNativeCapabilities = PlayerCapabilities(
  supportsNativeDolbyVision: true,
  supportsHdr10: true,
  supportsHardwareDecoding: true,
  supportsAssSubtitles: false,
  supportsExternalSubtitles: false,
  supportsAudioPassthrough: false,
  supportsShaders: false,
  supportsFrameStep: false,
  supportsScreenshots: false,
  supportsCustomHttpHeaders: false,
  supportsWebDav: false,
);

const windowsNativeCapabilities = PlayerCapabilities(
  supportsNativeDolbyVision: true,
  supportsHdr10: true,
  supportsHardwareDecoding: true,
  supportsAssSubtitles: false,
  supportsExternalSubtitles: false,
  supportsAudioPassthrough: false,
  supportsShaders: false,
  supportsFrameStep: false,
  supportsScreenshots: false,
  supportsCustomHttpHeaders: false,
  supportsWebDav: false,
);

class AndroidNativeBackend extends _SystemNativeBackend {
  AndroidNativeBackend({super.decoder})
      : super(outputId: 'android_media3_surface');

  @override
  String get backendId => 'android_native_media3';

  @override
  PlayerCapabilities get capabilities => androidNativeCapabilities;
}

class WindowsNativeBackend extends _SystemNativeBackend {
  WindowsNativeBackend({super.decoder})
      : super(
          outputId: 'windows_media_foundation_texture_experimental',
        );

  @override
  String get backendId => 'windows_native_media_foundation_experimental';

  @override
  PlayerCapabilities get capabilities => windowsNativeCapabilities;
}

abstract class _SystemNativeBackend implements PlayerBackend {
  _SystemNativeBackend({required this.outputId, this.decoder})
      : _videoOutput = _SystemNativeVideoOutput(outputId);

  final HardwareDecoderInfo? decoder;
  late final _SystemNativeVideoOutput _videoOutput;
  native_video.VideoPlayerController? _controller;
  String? _lastError;
  bool _disposed = false;
  PlayerBackendState _state = const PlayerBackendState(
    playing: false,
    completed: false,
    position: Duration.zero,
    duration: Duration.zero,
    bufferedPosition: Duration.zero,
    volume: 100,
    speed: 1,
    buffering: false,
    bufferingPercentage: 0,
    videoWidth: null,
    videoHeight: null,
  );

  final String outputId;

  final _stateController = StreamController<PlayerBackendState>.broadcast();
  final _positionController = StreamController<Duration>.broadcast();
  final _bufferedPositionController = StreamController<Duration>.broadcast();
  final _durationController = StreamController<Duration>.broadcast();
  final _playingController = StreamController<bool>.broadcast();
  final _completedController = StreamController<bool>.broadcast();
  final _bufferingController = StreamController<bool>.broadcast();
  final _bufferingPercentageController = StreamController<double>.broadcast();
  final _volumeController = StreamController<double>.broadcast();
  final _speedController = StreamController<double>.broadcast();
  final _videoWidthController = StreamController<int?>.broadcast();
  final _videoHeightController = StreamController<int?>.broadcast();
  final _audioTracksController =
      StreamController<List<PlayerTrack>>.broadcast();
  final _subtitleTracksController =
      StreamController<List<PlayerTrack>>.broadcast();
  final _selectedAudioTrackController =
      StreamController<PlayerTrack>.broadcast();
  final _selectedSubtitleTrackController =
      StreamController<PlayerTrack>.broadcast();
  final _errorController = StreamController<String>.broadcast();

  @override
  PlayerBackendState get state => _state;

  @override
  Stream<PlayerBackendState> get stateStream => _stateController.stream;

  @override
  Stream<Duration> get positionStream => _positionController.stream;

  @override
  Stream<Duration> get bufferedPositionStream =>
      _bufferedPositionController.stream;

  @override
  Stream<Duration> get durationStream => _durationController.stream;

  @override
  Stream<bool> get playingStream => _playingController.stream;

  @override
  Stream<bool> get completedStream => _completedController.stream;

  @override
  Stream<bool> get bufferingStream => _bufferingController.stream;

  @override
  Stream<double> get bufferingPercentageStream =>
      _bufferingPercentageController.stream;

  @override
  Stream<double> get volumeStream => _volumeController.stream;

  @override
  Stream<double> get speedStream => _speedController.stream;

  @override
  Stream<int?> get videoWidthStream => _videoWidthController.stream;

  @override
  Stream<int?> get videoHeightStream => _videoHeightController.stream;

  @override
  Stream<List<PlayerTrack>> get audioTracksStream =>
      _audioTracksController.stream;

  @override
  Stream<List<PlayerTrack>> get subtitleTracksStream =>
      _subtitleTracksController.stream;

  @override
  Stream<PlayerTrack> get selectedAudioTrackStream =>
      _selectedAudioTrackController.stream;

  @override
  Stream<PlayerTrack> get selectedSubtitleTrackStream =>
      _selectedSubtitleTrackController.stream;

  @override
  Stream<String> get errorStream => _errorController.stream;

  @override
  PlayerVideoOutput get videoOutput => _videoOutput;

  @override
  Future<void> initialize() => _videoOutput.attach();

  @override
  Future<void> open(
    PlayerMediaSource source, {
    Duration? startPosition,
  }) async {
    await _disposeController();
    final uri = Uri.parse(source.uri);
    const viewType = native_video.VideoViewType.textureView;
    final controller = uri.scheme == 'file'
        ? native_video.VideoPlayerController.file(
            File.fromUri(uri),
            viewType: viewType,
          )
        : native_video.VideoPlayerController.networkUrl(
            uri,
            httpHeaders: source.httpHeaders,
            viewType: viewType,
          );
    _controller = controller;
    _videoOutput.controller.value = controller;
    controller.addListener(_handleControllerChanged);
    _setState(
      _stateWith(buffering: true, bufferingPercentage: 0),
      force: true,
    );
    await controller.initialize();
    if (controller.value.hasError || !controller.value.isInitialized) {
      throw StateError(
        controller.value.errorDescription ??
            'System player initialization failed',
      );
    }
    if (controller.value.size.isEmpty) {
      throw StateError('System player initialized without a video surface');
    }
    _handleControllerChanged();
    await _refreshAudioTracks();
    _subtitleTracksController.add(const []);
    _selectedSubtitleTrackController.add(const PlayerTrack(id: 'no'));
    if (startPosition != null && startPosition > Duration.zero) {
      await controller.seekTo(startPosition);
    }
    await controller.play();
  }

  @override
  Future<void> play() => _requiredController.play();

  @override
  Future<void> pause() => _requiredController.pause();

  @override
  Future<void> seek(Duration position) => _requiredController.seekTo(position);

  @override
  Future<void> setVolume(double volume) =>
      _requiredController.setVolume(volume.clamp(0, 100) / 100);

  @override
  Future<void> setSpeed(double speed) =>
      _requiredController.setPlaybackSpeed(speed);

  @override
  Future<void> selectAudioTrack(String trackId) async {
    final controller = _requiredController;
    if (!controller.isAudioTrackSupportAvailable()) {
      throw UnsupportedError('Audio track selection is unavailable');
    }
    await controller.selectAudioTrack(trackId);
    await _refreshAudioTracks();
  }

  @override
  Future<void> selectSubtitleTrack(String? trackId) async {
    if (trackId == null || trackId == 'no') return;
    throw UnsupportedError('Subtitle track selection is unavailable');
  }

  @override
  Future<void> stop() async {
    final controller = _controller;
    if (controller != null) await controller.pause();
  }

  @override
  Future<PlayerRuntimeInfo> runtimeInfo() async => PlayerRuntimeInfo(
        videoOutput: outputId,
        decoderName: decoder?.name ??
            (Platform.isWindows
                ? 'Windows Media Foundation'
                : 'Media3 MediaCodec'),
        hardwareAccelerated: decoder?.hardwareAccelerated ?? true,
      );

  native_video.VideoPlayerController get _requiredController {
    final controller = _controller;
    if (controller == null) throw StateError('System player is not open');
    return controller;
  }

  void _handleControllerChanged() {
    final controller = _controller;
    if (controller == null || _disposed) return;
    final value = controller.value;
    final bufferedPosition = value.buffered.isEmpty
        ? Duration.zero
        : value.buffered
            .map((range) => range.end)
            .reduce((left, right) => left > right ? left : right);
    final durationMs = value.duration.inMilliseconds;
    final bufferingPercentage = durationMs <= 0
        ? 0.0
        : (bufferedPosition.inMilliseconds * 100 / durationMs)
            .clamp(0, 100)
            .toDouble();
    _setState(PlayerBackendState(
      playing: value.isPlaying,
      completed: value.isCompleted,
      position: value.position,
      duration: value.duration,
      bufferedPosition: bufferedPosition,
      volume: value.volume * 100,
      speed: value.playbackSpeed,
      buffering: value.isBuffering,
      bufferingPercentage: bufferingPercentage,
      videoWidth: value.isInitialized ? value.size.width.round() : null,
      videoHeight: value.isInitialized ? value.size.height.round() : null,
    ));
    final error = value.errorDescription;
    if (error != null && error != _lastError) {
      _lastError = error;
      _errorController.add(error);
    }
  }

  PlayerBackendState _stateWith({
    bool? buffering,
    double? bufferingPercentage,
  }) =>
      PlayerBackendState(
        playing: _state.playing,
        completed: _state.completed,
        position: _state.position,
        duration: _state.duration,
        bufferedPosition: _state.bufferedPosition,
        volume: _state.volume,
        speed: _state.speed,
        buffering: buffering ?? _state.buffering,
        bufferingPercentage: bufferingPercentage ?? _state.bufferingPercentage,
        videoWidth: _state.videoWidth,
        videoHeight: _state.videoHeight,
      );

  void _setState(PlayerBackendState next, {bool force = false}) {
    final previous = _state;
    _state = next;
    var changed = force;
    if (force || previous.position != next.position) {
      _positionController.add(next.position);
      changed = true;
    }
    if (force || previous.bufferedPosition != next.bufferedPosition) {
      _bufferedPositionController.add(next.bufferedPosition);
      changed = true;
    }
    if (force || previous.duration != next.duration) {
      _durationController.add(next.duration);
      changed = true;
    }
    if (force || previous.playing != next.playing) {
      _playingController.add(next.playing);
      changed = true;
    }
    if (force || previous.completed != next.completed) {
      _completedController.add(next.completed);
      changed = true;
    }
    if (force || previous.buffering != next.buffering) {
      _bufferingController.add(next.buffering);
      changed = true;
    }
    if (force || previous.bufferingPercentage != next.bufferingPercentage) {
      _bufferingPercentageController.add(next.bufferingPercentage);
      changed = true;
    }
    if (force || previous.volume != next.volume) {
      _volumeController.add(next.volume);
      changed = true;
    }
    if (force || previous.speed != next.speed) {
      _speedController.add(next.speed);
      changed = true;
    }
    if (force || previous.videoWidth != next.videoWidth) {
      _videoWidthController.add(next.videoWidth);
      changed = true;
    }
    if (force || previous.videoHeight != next.videoHeight) {
      _videoHeightController.add(next.videoHeight);
      changed = true;
    }
    if (changed) _stateController.add(next);
  }

  Future<void> _refreshAudioTracks() async {
    final controller = _controller;
    if (controller == null || !controller.isAudioTrackSupportAvailable()) {
      _audioTracksController.add(const []);
      _selectedAudioTrackController.add(const PlayerTrack(id: 'auto'));
      return;
    }
    try {
      final tracks = await controller.getAudioTracks();
      final mapped = [
        for (final track in tracks)
          PlayerTrack(
            id: track.id,
            title: track.label,
            language: track.language,
            codec: track.codec,
            channelCount: track.channelCount,
            isDefault: track.isSelected,
          ),
      ];
      _audioTracksController.add(mapped);
      _selectedAudioTrackController.add(
        mapped.firstWhere(
          (track) => track.isDefault == true,
          orElse: () => const PlayerTrack(id: 'auto'),
        ),
      );
    } catch (_) {
      _audioTracksController.add(const []);
      _selectedAudioTrackController.add(const PlayerTrack(id: 'auto'));
    }
  }

  Future<void> _disposeController() async {
    final controller = _controller;
    if (controller == null) return;
    controller.removeListener(_handleControllerChanged);
    _controller = null;
    _videoOutput.controller.value = null;
    await controller.dispose();
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _disposeController();
    await _videoOutput.dispose();
    for (final controller in <StreamController<dynamic>>[
      _stateController,
      _positionController,
      _bufferedPositionController,
      _durationController,
      _playingController,
      _completedController,
      _bufferingController,
      _bufferingPercentageController,
      _volumeController,
      _speedController,
      _videoWidthController,
      _videoHeightController,
      _audioTracksController,
      _subtitleTracksController,
      _selectedAudioTrackController,
      _selectedSubtitleTrackController,
      _errorController,
    ]) {
      await controller.close();
    }
  }
}

class _SystemNativeVideoOutput implements PlayerVideoOutput {
  _SystemNativeVideoOutput(this.outputId);

  @override
  final String outputId;

  final controller = ValueNotifier<native_video.VideoPlayerController?>(null);

  @override
  Object get platformViewHandle => controller;

  @override
  Future<void> attach() async {}

  @override
  Future<void> detach() async => controller.value = null;

  @override
  Future<void> dispose() async {
    await detach();
    controller.dispose();
  }
}
