part of 'package:player_flutter/main.dart';

const libmpvCapabilities = PlayerCapabilities(
  supportsNativeDolbyVision: false,
  supportsHdr10: true,
  supportsHardwareDecoding: true,
  supportsAssSubtitles: true,
  supportsExternalSubtitles: true,
  supportsAudioPassthrough: true,
  supportsShaders: true,
  supportsFrameStep: true,
  supportsScreenshots: true,
  supportsCustomHttpHeaders: true,
  supportsWebDav: true,
);

class LibmpvBackend implements PlayerBackend, MpvRuntimeBackend {
  LibmpvBackend({MediaInfo mediaInfo = const MediaInfo.unknown()})
      : _mediaInfo = mediaInfo,
        _player = Player(
          configuration: const PlayerConfiguration(
            logLevel: MPVLogLevel.warn,
            bufferSize: 64 * 1024 * 1024,
          ),
        ) {
    _videoOutput = _LibmpvVideoOutput(
      _player,
      vo: libmpvVideoOutput(
        mediaInfo,
        isAndroid: Platform.isAndroid,
      ),
    );
    for (final stream in <Stream<dynamic>>[
      _player.stream.playing,
      _player.stream.completed,
      _player.stream.position,
      _player.stream.duration,
      _player.stream.buffer,
      _player.stream.volume,
      _player.stream.rate,
      _player.stream.buffering,
      _player.stream.bufferingPercentage,
      _player.stream.width,
      _player.stream.height,
    ]) {
      _stateSubscriptions.add(stream.listen((_) {
        if (!_stateController.isClosed) _stateController.add(state);
      }));
    }
  }

  final Player _player;
  final MediaInfo _mediaInfo;
  bool _dolbyVisionMappingActive = false;
  final _stateController = StreamController<PlayerBackendState>.broadcast();
  final _stateSubscriptions = <StreamSubscription<dynamic>>[];
  late final PlayerVideoOutput _videoOutput;

  dynamic get _native => _player.platform as dynamic;

  @override
  String get backendId => 'libmpv';

  @override
  PlayerCapabilities get capabilities => libmpvCapabilities;

  @override
  PlayerBackendState get state {
    final state = _player.state;
    return PlayerBackendState(
      playing: state.playing,
      completed: state.completed,
      position: state.position,
      duration: state.duration,
      bufferedPosition: state.buffer,
      volume: state.volume,
      speed: state.rate,
      buffering: state.buffering,
      bufferingPercentage: state.bufferingPercentage,
      videoWidth: state.width ?? _mediaInfo.videoWidth,
      videoHeight: state.height ?? _mediaInfo.videoHeight,
    );
  }

  @override
  Stream<PlayerBackendState> get stateStream => _stateController.stream;

  @override
  Stream<Duration> get positionStream => _player.stream.position;

  @override
  Stream<Duration> get bufferedPositionStream => _player.stream.buffer;

  @override
  Stream<Duration> get durationStream => _player.stream.duration;

  @override
  Stream<bool> get playingStream => _player.stream.playing;

  @override
  Stream<bool> get completedStream => _player.stream.completed;

  @override
  Stream<bool> get bufferingStream => _player.stream.buffering;

  @override
  Stream<double> get bufferingPercentageStream =>
      _player.stream.bufferingPercentage;

  @override
  Stream<double> get volumeStream => _player.stream.volume;

  @override
  Stream<double> get speedStream => _player.stream.rate;

  @override
  Stream<int?> get videoWidthStream =>
      _player.stream.width.map((value) => value ?? _mediaInfo.videoWidth);

  @override
  Stream<int?> get videoHeightStream =>
      _player.stream.height.map((value) => value ?? _mediaInfo.videoHeight);

  @override
  Stream<List<PlayerTrack>> get audioTracksStream => _player.stream.tracks.map(
        (tracks) => tracks.audio.map(_playerTrackFromMediaKit).toList(),
      );

  @override
  Stream<List<PlayerTrack>> get subtitleTracksStream =>
      _player.stream.tracks.map(
        (tracks) => tracks.subtitle.map(_playerTrackFromMediaKit).toList(),
      );

  @override
  Stream<PlayerTrack> get selectedAudioTrackStream => _player.stream.track
      .map((track) => _playerTrackFromMediaKit(track.audio));

  @override
  Stream<PlayerTrack> get selectedSubtitleTrackStream => _player.stream.track
      .map((track) => _playerTrackFromMediaKit(track.subtitle));

  @override
  Stream<String> get errorStream => _player.stream.error;

  @override
  PlayerVideoOutput get videoOutput => _videoOutput;

  @override
  Future<void> initialize() => _videoOutput.attach();

  @override
  Future<void> open(
    PlayerMediaSource source, {
    Duration? startPosition,
  }) async {
    final media = Media(
      source.uri,
      httpHeaders: source.httpHeaders.isEmpty ? null : source.httpHeaders,
      start: startPosition,
    );
    if (!Platform.isWindows) {
      _dolbyVisionMappingActive =
          Platform.isAndroid && _mediaInfo.isDolbyVision;
      await _player.open(media);
      return;
    }

    // Keep vo=libmpv for the Flutter texture. vf_libplacebo performs Dolby
    // Vision reshaping before the existing renderer sees the frame.
    await _player.open(media, play: false);
    final info = _mediaInfo.isDolbyVision
        ? _mediaInfo
        : Platform.isWindows
            ? await waitForMpvMediaInfo((property) async {
                try {
                  return await getRuntimeProperty(property);
                } catch (_) {
                  return '';
                }
              })
            : _mediaInfo;
    final filter = libmpvDolbyVisionFilter(
      info,
      isWindows: Platform.isWindows,
    );
    await setRuntimeProperty('vf', filter ?? '');
    _dolbyVisionMappingActive = filter != null;
    await _player.play();
  }

  @override
  Future<void> play() => _player.play();

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Future<void> setVolume(double volume) => _player.setVolume(volume);

  @override
  Future<void> setSpeed(double speed) => _player.setRate(speed);

  @override
  Future<void> selectAudioTrack(String trackId) async {
    for (final track in _player.state.tracks.audio) {
      if (track.id == trackId) return _player.setAudioTrack(track);
    }
    throw ArgumentError.value(trackId, 'trackId', 'Unknown audio track');
  }

  @override
  Future<void> selectSubtitleTrack(String? trackId) async {
    trackId ??= 'no';
    for (final track in _player.state.tracks.subtitle) {
      if (track.id == trackId) return _player.setSubtitleTrack(track);
    }
    throw ArgumentError.value(trackId, 'trackId', 'Unknown subtitle track');
  }

  @override
  Future<void> stop() => _player.stop();

  @override
  Future<PlayerRuntimeInfo> runtimeInfo() async {
    String? decoder;
    String? hwdec;
    try {
      decoder = await getRuntimeProperty('video-codec');
    } catch (_) {}
    try {
      hwdec = await getRuntimeProperty('hwdec-current');
    } catch (_) {}
    final normalizedHwdec = hwdec?.trim().toLowerCase();
    final accelerated = normalizedHwdec == null ||
            normalizedHwdec.isEmpty ||
            normalizedHwdec == 'null' ||
            normalizedHwdec == 'unavailable'
        ? null
        : normalizedHwdec != 'no';
    return PlayerRuntimeInfo(
      videoOutput: videoOutput.outputId,
      decoderName: [
        if (decoder?.isNotEmpty == true) decoder,
        if (hwdec?.isNotEmpty == true && hwdec != 'no') hwdec,
        if (_dolbyVisionMappingActive) 'libplacebo Dolby Vision mapping',
      ].join(' / '),
      hardwareAccelerated: accelerated,
    );
  }

  @override
  Future<void> setRuntimeProperty(String property, String value) =>
      _native.setProperty(property, value);

  @override
  Future<String> getRuntimeProperty(String property) async =>
      '${await _native.getProperty(property)}';

  @override
  Future<void> observeRuntimeProperty(
    String property,
    Future<void> Function(String value) listener,
  ) =>
      _native.observeProperty(property, listener);

  @override
  Future<void> unobserveRuntimeProperty(String property) =>
      _native.unobserveProperty(property);

  @override
  Future<void> dispose() async {
    for (final subscription in _stateSubscriptions) {
      await subscription.cancel();
    }
    await _stateController.close();
    await _videoOutput.dispose();
    await _player.dispose();
  }
}

String? libmpvDolbyVisionFilter(
  MediaInfo media, {
  required bool isWindows,
}) {
  if (!media.isDolbyVision) return null;
  if (isWindows) return 'lavfi=[libplacebo=apply_dolbyvision=1]';
  return null;
}

String? libmpvVideoOutput(
  MediaInfo media, {
  required bool isAndroid,
}) =>
    isAndroid && media.isDolbyVision ? 'gpu-next' : null;

PlayerTrack _playerTrackFromMediaKit(dynamic track) => PlayerTrack(
      id: track.id as String,
      title: track.title as String?,
      language: track.language as String?,
      codec: track.codec as String?,
      channelCount: track.channelscount as int?,
      isDefault: track.isDefault as bool?,
    );

class _LibmpvVideoOutput implements PlayerVideoOutput {
  _LibmpvVideoOutput(Player player, {required String? vo})
      : _controller = VideoController(
          player,
          configuration: VideoControllerConfiguration(vo: vo),
        ),
        _outputId =
            vo == 'gpu-next' ? 'android_gpu_next_surface' : 'libmpv_texture';

  final VideoController _controller;
  final String _outputId;

  @override
  String get outputId => _outputId;

  @override
  Object get platformViewHandle => _controller;

  @override
  Future<void> attach() async {}

  @override
  Future<void> detach() async {}

  @override
  Future<void> dispose() => detach();
}
