part of 'package:player_flutter/main.dart';

class PlayerCapabilities {
  const PlayerCapabilities({
    required this.supportsNativeDolbyVision,
    required this.supportsHdr10,
    required this.supportsHardwareDecoding,
    required this.supportsAssSubtitles,
    required this.supportsExternalSubtitles,
    required this.supportsAudioPassthrough,
    required this.supportsShaders,
    required this.supportsFrameStep,
    required this.supportsScreenshots,
    required this.supportsCustomHttpHeaders,
    required this.supportsWebDav,
  });

  final bool supportsNativeDolbyVision;
  final bool supportsHdr10;
  final bool supportsHardwareDecoding;
  final bool supportsAssSubtitles;
  final bool supportsExternalSubtitles;
  final bool supportsAudioPassthrough;
  final bool supportsShaders;
  final bool supportsFrameStep;
  final bool supportsScreenshots;
  final bool supportsCustomHttpHeaders;
  final bool supportsWebDav;
}

class PlayerMediaSource {
  const PlayerMediaSource(
    this.uri, {
    this.httpHeaders = const {},
    this.isRemote = false,
    this.nativeProxyReady = false,
  });

  final String uri;
  final Map<String, String> httpHeaders;
  final bool isRemote;
  final bool nativeProxyReady;

  PlayerMediaSource copyWith({
    String? uri,
    Map<String, String>? httpHeaders,
    bool? isRemote,
    bool? nativeProxyReady,
  }) =>
      PlayerMediaSource(
        uri ?? this.uri,
        httpHeaders: httpHeaders ?? this.httpHeaders,
        isRemote: isRemote ?? this.isRemote,
        nativeProxyReady: nativeProxyReady ?? this.nativeProxyReady,
      );
}

class PlayerBackendState {
  const PlayerBackendState({
    required this.playing,
    required this.completed,
    required this.position,
    required this.duration,
    required this.bufferedPosition,
    required this.volume,
    required this.speed,
    required this.buffering,
    required this.bufferingPercentage,
    required this.videoWidth,
    required this.videoHeight,
  });

  final bool playing;
  final bool completed;
  final Duration position;
  final Duration duration;
  final Duration bufferedPosition;
  final double volume;
  final double speed;
  final bool buffering;
  final double bufferingPercentage;
  final int? videoWidth;
  final int? videoHeight;
}

class PlayerTrack {
  const PlayerTrack({
    required this.id,
    this.title,
    this.language,
    this.codec,
    this.channelCount,
    this.isDefault,
    this.isForced,
  });

  final String id;
  final String? title;
  final String? language;
  final String? codec;
  final int? channelCount;
  final bool? isDefault;
  final bool? isForced;

  @override
  bool operator ==(Object other) => other is PlayerTrack && id == other.id;

  @override
  int get hashCode => id.hashCode;
}

abstract interface class PlayerVideoOutput {
  String get outputId;

  Object? get platformViewHandle;

  Future<void> attach();

  Future<void> detach();

  Future<void> dispose();
}

class PlayerRuntimeInfo {
  const PlayerRuntimeInfo({
    required this.videoOutput,
    this.decoderName,
    this.hardwareAccelerated,
  });

  final String videoOutput;
  final String? decoderName;
  final bool? hardwareAccelerated;
}

abstract interface class PlayerBackend {
  String get backendId;

  PlayerCapabilities get capabilities;

  PlayerBackendState get state;

  Stream<PlayerBackendState> get stateStream;

  Stream<Duration> get positionStream;

  Stream<Duration> get bufferedPositionStream;

  Stream<Duration> get durationStream;

  Stream<bool> get playingStream;

  Stream<bool> get completedStream;

  Stream<bool> get bufferingStream;

  Stream<double> get bufferingPercentageStream;

  Stream<double> get volumeStream;

  Stream<double> get speedStream;

  Stream<int?> get videoWidthStream;

  Stream<int?> get videoHeightStream;

  Stream<List<PlayerTrack>> get audioTracksStream;

  Stream<List<PlayerTrack>> get subtitleTracksStream;

  Stream<PlayerTrack> get selectedAudioTrackStream;

  Stream<PlayerTrack> get selectedSubtitleTrackStream;

  Stream<String> get errorStream;

  PlayerVideoOutput get videoOutput;

  Future<void> initialize();

  Future<void> open(
    PlayerMediaSource source, {
    Duration? startPosition,
  });

  Future<void> play();

  Future<void> pause();

  Future<void> seek(Duration position);

  Future<void> setVolume(double volume);

  Future<void> setSpeed(double speed);

  Future<void> selectAudioTrack(String trackId);

  Future<void> selectSubtitleTrack(String? trackId);

  Future<void> stop();

  Future<PlayerRuntimeInfo> runtimeInfo();

  Future<void> dispose();
}

abstract interface class MpvRuntimeBackend {
  Future<void> setRuntimeProperty(String property, String value);

  Future<String> getRuntimeProperty(String property);

  Future<void> observeRuntimeProperty(
    String property,
    Future<void> Function(String value) listener,
  );

  Future<void> unobserveRuntimeProperty(String property);
}
