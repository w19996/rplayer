part of 'package:player_flutter/main.dart';

class MediaInfo {
  const MediaInfo({
    required this.isDolbyVision,
    this.dolbyVisionProfile,
    this.dolbyVisionLevel,
    this.container,
    this.videoCodec,
    this.hdrFormat,
    this.videoWidth,
    this.videoHeight,
    this.fileNameHint = false,
  });

  const MediaInfo.unknown()
      : isDolbyVision = false,
        dolbyVisionProfile = null,
        dolbyVisionLevel = null,
        container = null,
        videoCodec = null,
        hdrFormat = null,
        videoWidth = null,
        videoHeight = null,
        fileNameHint = false;

  final bool isDolbyVision;
  final int? dolbyVisionProfile;
  final int? dolbyVisionLevel;
  final String? container;
  final String? videoCodec;
  final String? hdrFormat;
  final int? videoWidth;
  final int? videoHeight;
  final bool fileNameHint;

  bool? get isLandscape => videoWidth == null || videoHeight == null
      ? null
      : videoWidth! >= videoHeight!;
}

typedef MpvPropertyReader = Future<String> Function(String property);

Future<MediaInfo> readMpvMediaInfo(
  MpvPropertyReader readProperty, {
  String sourceUri = '',
}) async {
  final count = int.tryParse(await readProperty('track-list/count')) ?? 0;
  String? codec;
  String? codecTag;
  String? codecProfile;
  String? transfer;
  int? dolbyVisionProfile;
  int? dolbyVisionLevel;
  int? videoWidth;
  int? videoHeight;
  for (var index = 0; index < count; index++) {
    if ((await readProperty('track-list/$index/type')).trim() != 'video') {
      continue;
    }
    codec = _nonEmpty(await readProperty('track-list/$index/codec'));
    codecTag = _nonEmpty(await readProperty('track-list/$index/codec-tag'));
    codecProfile =
        _nonEmpty(await readProperty('track-list/$index/codec-profile'));
    transfer =
        _nonEmpty(await readProperty('track-list/$index/color-transfer'));
    dolbyVisionProfile = await _firstPositiveInt(readProperty, [
      'track-list/$index/dolby-vision-profile',
      'track-list/$index/demux-dolby-vision-profile',
      'video-params/dolby-vision-profile',
    ]);
    dolbyVisionLevel = await _firstPositiveInt(readProperty, [
      'track-list/$index/dolby-vision-level',
      'track-list/$index/demux-dolby-vision-level',
      'video-params/dolby-vision-level',
    ]);
    videoWidth = await _firstPositiveInt(
      readProperty,
      ['track-list/$index/demux-w', 'track-list/$index/w'],
    );
    videoHeight = await _firstPositiveInt(
      readProperty,
      ['track-list/$index/demux-h', 'track-list/$index/h'],
    );
    final rotation = int.tryParse(
            (await readProperty('track-list/$index/demux-rotate')).trim()) ??
        0;
    if (rotation.abs() % 180 == 90) {
      final width = videoWidth;
      videoWidth = videoHeight;
      videoHeight = width;
    }
    break;
  }

  final streamDescription = '$codec $codecTag $codecProfile'.toLowerCase();
  final codecString = RegExp(
    r'\b(?:dvhe|dvh1|dvav|dva1)\.(\d{2})\.(\d{2})\b',
  ).firstMatch(streamDescription);
  dolbyVisionProfile ??= int.tryParse(codecString?.group(1) ?? '');
  dolbyVisionLevel ??= int.tryParse(codecString?.group(2) ?? '');
  final isDolbyVision = dolbyVisionProfile != null ||
      streamDescription.contains('dolby vision') ||
      RegExp(r'\b(dvhe|dvh1|dvav|dva1)\b').hasMatch(streamDescription);
  final normalizedTransfer = transfer?.toLowerCase();
  final hdrFormat = isDolbyVision
      ? 'dolby_vision'
      : normalizedTransfer == 'smpte2084' || normalizedTransfer == 'pq'
          ? 'hdr10'
          : normalizedTransfer?.contains('hlg') == true
              ? 'hlg'
              : null;
  final fileName =
      Uri.tryParse(sourceUri)?.pathSegments.lastOrNull ?? sourceUri;
  final fileNameHint = hasDolbyVisionPathHint(fileName);
  return MediaInfo(
    isDolbyVision: isDolbyVision,
    dolbyVisionProfile: dolbyVisionProfile,
    dolbyVisionLevel: dolbyVisionLevel,
    container: _nonEmpty(await readProperty('file-format')),
    videoCodec: codec,
    hdrFormat: hdrFormat,
    videoWidth: videoWidth,
    videoHeight: videoHeight,
    fileNameHint: fileNameHint,
  );
}

Future<MediaInfo> waitForMpvMediaInfo(
  MpvPropertyReader readProperty, {
  String sourceUri = '',
  Duration timeout = const Duration(seconds: 8),
}) async {
  final deadline = DateTime.now().add(timeout);
  MediaInfo info = const MediaInfo.unknown();
  do {
    info = await readMpvMediaInfo(readProperty, sourceUri: sourceUri);
    if (info.videoCodec != null) return info;
    await Future<void>.delayed(const Duration(milliseconds: 40));
  } while (DateTime.now().isBefore(deadline));
  return info;
}

bool hasDolbyVisionPathHint(String value) => RegExp(
      r'杜比视界|dovi|dolby[. _-]?vision|(^|[. /_\-])dv([. /_\-]|$)',
      caseSensitive: false,
    ).hasMatch(value);

String? _nonEmpty(String value) {
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

Future<int?> _firstPositiveInt(
  MpvPropertyReader readProperty,
  List<String> properties,
) async {
  for (final property in properties) {
    final value = int.tryParse((await readProperty(property)).trim());
    if (value != null && value > 0) return value;
  }
  return null;
}

class MediaProbe {
  const MediaProbe({this.log});

  final void Function(String message)? log;

  Future<MediaInfo> probe(
    PlayerMediaSource source, {
    void Function(String message)? log,
  }) async {
    final player = Player(
      configuration: const PlayerConfiguration(
        logLevel: MPVLogLevel.error,
        bufferSize: 8 * 1024 * 1024,
      ),
    );
    try {
      final native = player.platform as dynamic;
      for (final property in const {'vo': 'null', 'ao': 'null'}.entries) {
        try {
          await native.setProperty(property.key, property.value);
        } catch (_) {}
      }
      await player.open(
        Media(
          source.uri,
          httpHeaders: source.httpHeaders.isEmpty ? null : source.httpHeaders,
        ),
        play: false,
      );
      final info = await waitForMpvMediaInfo(
        (property) async {
          try {
            return '${await native.getProperty(property)}';
          } catch (_) {
            return '';
          }
        },
        sourceUri: source.uri,
      );
      (log ?? this.log)?.call(
        'media probe: codec=${info.videoCodec ?? 'unknown'} container=${info.container ?? 'unknown'} hdr=${info.hdrFormat ?? 'sdr_or_unknown'} dvProfile=${info.dolbyVisionProfile ?? 'unknown'} dvLevel=${info.dolbyVisionLevel ?? 'unknown'} size=${info.videoWidth ?? 0}x${info.videoHeight ?? 0} filenameHint=${info.fileNameHint}',
      );
      return info;
    } catch (error) {
      (log ?? this.log)?.call('media probe failed: $error');
      return const MediaInfo.unknown();
    } finally {
      await player.dispose();
    }
  }
}
