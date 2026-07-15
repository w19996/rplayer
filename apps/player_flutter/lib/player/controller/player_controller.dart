part of 'package:player_flutter/main.dart';

class PlayerBackendController {
  PlayerBackendController({
    this.factory = const PlayerBackendFactory(),
    this.detector = const DeviceCapabilityDetector(),
    MediaProbe? probe,
    LocalMediaProxy? proxy,
  })  : probe = probe ?? const MediaProbe(),
        proxy = proxy ?? LocalMediaProxy();

  final PlayerBackendFactory factory;
  final DeviceCapabilityDetector detector;
  final MediaProbe probe;
  final LocalMediaProxy proxy;
  bool fallbackTriggered = false;

  void beginMedia() => fallbackTriggered = false;

  Future<PlayerBackendSelection> select({
    required PlayerMediaSource source,
    required PlayerBackendPreference preference,
    void Function(String message)? log,
  }) async {
    final device = await detector.detect();
    final shouldProbe = shouldProbeMediaForNativeSelection(
      source: source,
      preference: preference,
      device: device,
    );
    final preparedSource = shouldProbe && source.isRemote
        ? await proxy.prepare(source, log: log) ?? source
        : source;
    final media = shouldProbe
        ? await probe.probe(preparedSource, log: log)
        : const MediaInfo.unknown();
    if (!shouldProbe) {
      log?.call('media probe skipped: native Dolby Vision candidate=false');
    }
    var effectiveSource = source;
    if (source.isRemote &&
        factory.wantsNative(
          preference: preference,
          media: media,
          device: device,
        )) {
      effectiveSource = preparedSource.nativeProxyReady
          ? preparedSource
          : await proxy.prepare(source, log: log) ?? source;
    }
    final decision = factory.createBackend(
      source: effectiveSource,
      media: media,
      device: device,
      preference: preference,
    );
    return PlayerBackendSelection(
      backend: decision.backend,
      source: effectiveSource,
      media: media,
      device: device,
      reason: decision.reason,
    );
  }

  PlayerBackend? createFallback({MediaInfo media = const MediaInfo.unknown()}) {
    if (fallbackTriggered) return null;
    fallbackTriggered = true;
    return factory.createFallbackBackend(media: media);
  }

  Future<void> dispose() => proxy.dispose();
}

bool shouldProbeMediaForNativeSelection({
  required PlayerMediaSource source,
  required PlayerBackendPreference preference,
  required DeviceCapabilities device,
}) {
  if (preference == PlayerBackendPreference.libmpvOnly ||
      preference == PlayerBackendPreference.nativePreferred ||
      !device.supportsNativeDolbyVision) {
    return false;
  }
  final path =
      Uri.tryParse(source.uri)?.path.toLowerCase() ?? source.uri.toLowerCase();
  // ponytail: filename is only a cheap probe trigger; stream metadata still
  // confirms DV. Probe every file only if unlabeled DV discovery is required.
  return hasDolbyVisionPathHint(Uri.decodeComponent(path));
}

class PlayerBackendSelection {
  const PlayerBackendSelection({
    required this.backend,
    required this.source,
    required this.media,
    required this.device,
    required this.reason,
  });

  final PlayerBackend backend;
  final PlayerMediaSource source;
  final MediaInfo media;
  final DeviceCapabilities device;
  final String reason;
}
