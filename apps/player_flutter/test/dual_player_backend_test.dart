import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:player_flutter/main.dart';

void main() {
  test('factory selects native only for confirmed matching DV profile', () {
    const factory = PlayerBackendFactory();
    const device = DeviceCapabilities(
      nativeBackendAvailable: true,
      supportsNativeDolbyVision: true,
      supportedDolbyVisionProfiles: {8},
      supportsHdr10: true,
      hardwareDecoders: [
        HardwareDecoderInfo(
          name: 'DV hardware decoder',
          mimeType: 'video/dolby-vision',
          hardwareAccelerated: true,
          dolbyVisionProfiles: {8},
        ),
      ],
    );
    const dv8 = MediaInfo(
      isDolbyVision: true,
      dolbyVisionProfile: 8,
      container: 'mov,mp4,m4a,3gp,3g2,mj2',
    );
    const dv5 = MediaInfo(
      isDolbyVision: true,
      dolbyVisionProfile: 5,
      container: 'mov,mp4,m4a,3gp,3g2,mj2',
    );
    const standard = MediaInfo(isDolbyVision: false);

    expect(
      factory.wantsNative(
        preference: PlayerBackendPreference.automatic,
        media: dv8,
        device: device,
      ),
      isTrue,
    );
    expect(
      factory.wantsNative(
        preference: PlayerBackendPreference.automatic,
        media: dv5,
        device: device,
      ),
      isFalse,
    );
    expect(
      factory.wantsNative(
        preference: PlayerBackendPreference.automatic,
        media: const MediaInfo(
          isDolbyVision: true,
          dolbyVisionProfile: 8,
          container: 'matroska,webm',
        ),
        device: device,
      ),
      isTrue,
    );
    expect(
      factory.wantsNative(
        preference: PlayerBackendPreference.automatic,
        media: standard,
        device: device,
      ),
      isFalse,
    );
  });

  test('filename DV hint does not confirm Dolby Vision', () async {
    Future<String> read(String property) async =>
        {
          'track-list/count': '1',
          'track-list/0/type': 'video',
          'track-list/0/codec': 'hevc',
        }[property] ??
        '';

    final info = await readMpvMediaInfo(
      read,
      sourceUri: 'file:///Movie.DV.mkv',
    );

    expect(info.fileNameHint, isTrue);
    expect(info.isDolbyVision, isFalse);
  });

  test('only likely native DV files pay the media probe cost', () {
    const device = DeviceCapabilities(
      nativeBackendAvailable: true,
      supportsNativeDolbyVision: true,
      supportedDolbyVisionProfiles: {8},
      supportsHdr10: true,
      hardwareDecoders: [],
    );

    bool shouldProbe(String uri) => shouldProbeMediaForNativeSelection(
          source: PlayerMediaSource(uri),
          preference: PlayerBackendPreference.automatic,
          device: device,
        );

    expect(shouldProbe('https://media/Show.DV.mp4'), isTrue);
    expect(shouldProbe('https://media/Show.mp4'), isFalse);
    expect(shouldProbe('https://media/Show.DV.mkv'), isTrue);
    expect(
      shouldProbe(
        'https://media/4K%20DV%E6%9D%9C%E6%AF%94%E8%A7%86%E7%95%8C/02.mkv',
      ),
      isTrue,
    );
  });

  test('Windows libmpv maps confirmed Dolby Vision through libplacebo', () {
    const dolbyVision = MediaInfo(
      isDolbyVision: true,
      dolbyVisionProfile: 5,
    );
    const standard = MediaInfo(isDolbyVision: false);

    expect(
      libmpvDolbyVisionFilter(
        dolbyVision,
        isWindows: true,
      ),
      'lavfi=[libplacebo=apply_dolbyvision=1]',
    );
    expect(
      libmpvDolbyVisionFilter(
        standard,
        isWindows: true,
      ),
      isNull,
    );
    expect(
      libmpvDolbyVisionFilter(
        dolbyVision,
        isWindows: false,
      ),
      isNull,
    );
  });

  test('Android libmpv does not attach unavailable FFmpeg libplacebo filter',
      () {
    const dolbyVision = MediaInfo(
      isDolbyVision: true,
      dolbyVisionProfile: 8,
    );

    expect(
      libmpvDolbyVisionFilter(
        dolbyVision,
        isWindows: false,
      ),
      isNull,
    );
  });

  test('Android Dolby Vision uses gpu-next output', () {
    const dolbyVision = MediaInfo(isDolbyVision: true);
    const standard = MediaInfo(isDolbyVision: false);

    expect(libmpvVideoOutput(dolbyVision, isAndroid: true), 'gpu-next');
    expect(libmpvVideoOutput(standard, isAndroid: true), isNull);
    expect(libmpvVideoOutput(dolbyVision, isAndroid: false), isNull);
  });

  test('codec string confirms Dolby Vision profile and level', () async {
    Future<String> read(String property) async =>
        {
          'track-list/count': '1',
          'track-list/0/type': 'video',
          'track-list/0/codec': 'dvhe.08.06',
        }[property] ??
        '';

    final info = await readMpvMediaInfo(read);

    expect(info.isDolbyVision, isTrue);
    expect(info.dolbyVisionProfile, 8);
    expect(info.dolbyVisionLevel, 6);
  });

  test('media probe applies rotation to display orientation', () async {
    Future<String> read(String property) async =>
        {
          'track-list/count': '1',
          'track-list/0/type': 'video',
          'track-list/0/codec': 'hevc',
          'track-list/0/demux-w': '1080',
          'track-list/0/demux-h': '1920',
          'track-list/0/demux-rotate': '90',
        }[property] ??
        '';

    final info = await readMpvMediaInfo(read);

    expect(info.videoWidth, 1920);
    expect(info.videoHeight, 1080);
    expect(info.isLandscape, isTrue);
  });

  test('media probe waits for delayed track metadata', () async {
    var countReads = 0;
    Future<String> read(String property) async {
      if (property == 'track-list/count') {
        countReads += 1;
        return countReads < 3 ? '0' : '1';
      }
      return {
            'track-list/0/type': 'video',
            'track-list/0/codec': 'dvhe.05.06',
          }[property] ??
          '';
    }

    final info = await waitForMpvMediaInfo(
      read,
      timeout: const Duration(seconds: 1),
    );

    expect(info.isDolbyVision, isTrue);
    expect(info.dolbyVisionProfile, 5);
    expect(countReads, 3);
  });

  test('track restore matches metadata instead of backend id', () {
    const wanted = PlayerTrack(
      id: 'native-17',
      title: 'Main',
      language: 'zh',
      codec: 'eac3',
      channelCount: 6,
      isDefault: true,
    );
    const candidates = [
      PlayerTrack(id: 'mpv-1', language: 'en', codec: 'aac'),
      PlayerTrack(
        id: 'mpv-9',
        title: 'Main',
        language: 'zh',
        codec: 'eac3',
        channelCount: 6,
        isDefault: true,
      ),
    ];

    expect(matchPlayerTrack(wanted, candidates)?.id, 'mpv-9');
  });

  test('local proxy forwards auth and exact byte ranges without credentials',
      () async {
    final data = Uint8List.fromList(List<int>.generate(256, (index) => index));
    var requests = 0;
    var interrupted = false;
    final upstream = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final subscription = upstream.listen((request) async {
      requests++;
      expect(request.headers.value('authorization'), 'Bearer upstream-secret');
      request.response.headers.set(HttpHeaders.acceptRangesHeader, 'bytes');
      if (request.method == 'HEAD') {
        request.response.headers.contentLength = data.length;
        await request.response.close();
        return;
      }
      final range = request.headers.value(HttpHeaders.rangeHeader);
      final match = RegExp(r'bytes=(\d+)-(\d*)').firstMatch(range ?? '');
      final start = int.parse(match!.group(1)!);
      final end = match.group(2)!.isEmpty
          ? data.length - 1
          : int.parse(match.group(2)!);
      if (range == 'bytes=20-29' && !interrupted) {
        interrupted = true;
        request.response.statusCode = HttpStatus.partialContent;
        request.response.headers.set(
          HttpHeaders.contentRangeHeader,
          'bytes 20-29/${data.length}',
        );
        request.response.headers.contentLength = 10;
        request.response.add(data.sublist(20, 25));
        try {
          await request.response.close();
        } catch (_) {}
        return;
      }
      final bytes = data.sublist(start, end + 1);
      request.response.statusCode = HttpStatus.partialContent;
      request.response.headers.set(
        HttpHeaders.contentRangeHeader,
        'bytes $start-$end/${data.length}',
      );
      request.response.headers.contentLength = bytes.length;
      request.response.add(bytes);
      await request.response.close();
    });
    final proxy = LocalMediaProxy();
    try {
      final source = await proxy.prepare(
        PlayerMediaSource(
          'http://${upstream.address.address}:${upstream.port}/movie.mp4',
          httpHeaders: const {
            'authorization': 'Bearer upstream-secret',
          },
          isRemote: true,
        ),
      );
      expect(source, isNotNull);
      expect(source!.nativeProxyReady, isTrue);
      expect(source.uri, isNot(contains('upstream-secret')));
      expect(Uri.parse(source.uri).query, isEmpty);
      expect(source.httpHeaders, isEmpty);

      Future<List<int>> getRange(String range, String contentRange) async {
        final client = HttpClient();
        try {
          final request = await client.getUrl(Uri.parse(source.uri));
          request.headers.set(HttpHeaders.rangeHeader, range);
          final response = await request.close();
          expect(response.statusCode, HttpStatus.partialContent);
          expect(
            response.headers.value(HttpHeaders.contentRangeHeader),
            contentRange,
          );
          return await response.fold<List<int>>(
            <int>[],
            (all, chunk) => all..addAll(chunk),
          );
        } finally {
          client.close(force: true);
        }
      }

      expect(
        await getRange('bytes=10-19', 'bytes 10-19/256'),
        data.sublist(10, 20),
      );
      expect(
        await getRange('bytes=10-19', 'bytes 10-19/256'),
        data.sublist(10, 20),
      );
      expect(
        await getRange('bytes=20-29', 'bytes 20-29/256'),
        data.sublist(20, 30),
      );
      expect(
        requests,
        4,
        reason: 'probe + cached range + interrupted range + resumed range',
      );
    } finally {
      await proxy.dispose();
      await subscription.cancel();
      await upstream.close(force: true);
    }
  });
}
