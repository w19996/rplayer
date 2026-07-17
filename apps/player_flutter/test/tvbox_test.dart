import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:player_flutter/main.dart';

void main() {
  test('fast search keeps results containing every title word', () {
    expect(tvboxSearchNameMatches('功夫女足 4K', '功夫 女足'), isTrue);
    expect(tvboxSearchNameMatches('功夫足球', '功夫 女足'), isFalse);
  });

  test('parses TVBox image headers', () {
    final request = tvboxImageRequest(
        'https://img.example/poster.jpg@Headers=%7B%22X-Test%22%3A%221%22%7D@Referer=https://example.com/@User-Agent=TVBox');
    expect(request.url, 'https://img.example/poster.jpg');
    expect(request.headers, {
      'X-Test': '1',
      'Referer': 'https://example.com/',
      'User-Agent': 'TVBox',
    });

    final douban = tvboxImageRequest('//img9.doubanio.com/poster.webp');
    expect(douban.url, 'https://img9.doubanio.com/poster.webp');
    expect(douban.headers['Referer'], 'https://api.douban.com/');
  });

  test('decodes TVBox configs and keeps cross-platform site types', () {
    expect(
      normalizeTvboxSourceUrl(
          'https://github.com/qist/tvbox/blob/master/0821.json'),
      'https://raw.githubusercontent.com/qist/tvbox/master/0821.json',
    );
    final config = jsonEncode({
      'sites': [
        {'key': 'xml', 'name': 'XML', 'type': 0, 'api': './xml'},
        {'key': 'json', 'name': 'JSON', 'type': 1, 'api': './json'},
        {
          'key': 'remote',
          'name': 'Remote',
          'type': 4,
          'api': './remote',
          'searchable': 0,
        },
        {'key': 'spider', 'name': 'Spider', 'type': 3, 'api': 'csp_Test'},
      ],
    });
    final wrapped = [
      ...<int>[0xff, 0xd8, 0xff, 0xd9],
      ...latin1.encode('12345678**${base64Encode(utf8.encode(config))}'),
    ];
    final sites = tvboxSitesFromConfig('https://example.com/config.json',
        jsonDecode(decodeTvboxConfigBytes(wrapped)));

    expect(sites.map((site) => site.type), [0, 1, 4]);
    expect(sites.first.apiUrl, 'https://example.com/xml');
    expect(sites.last.apiUrl, 'https://example.com/remote');
    expect(sites.last.searchable, isFalse);
    expect(
      parseTvboxJarSpec(
          'https://example.com/config/main.json', './jar/fan.jar;md5;abc123'),
      ('https://example.com/config/jar/fan.jar', 'abc123'),
    );
    expect(
      tvboxSpiderExt('https://example.com/config/main.json', 'encrypted-data'),
      'encrypted-data',
    );
    expect(
      jsonDecode(tvboxSpiderExt('https://example.com/config/main.json', {
        'Cloud-drive': 'tvfan/Cloud-drive.txt',
        'token': 'encrypted-data',
      })),
      {
        'Cloud-drive': 'https://example.com/config/tvfan/Cloud-drive.txt',
        'token': 'encrypted-data',
      },
    );
    expect(
      () => tvboxSitesFromConfig('https://example.com/config', {
        'sites': [
          {'type': 3, 'api': 'csp_Test'},
        ],
      }),
      throwsA(isA<FormatException>().having(
          (error) => error.message, 'message', contains('Spider/JAR/JS'))),
    );
  });

  test('uses FongMi JSON and remote site protocols', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final subscription = server.listen((request) async {
      request.response.headers.contentType = ContentType.json;
      if (request.uri.queryParameters.containsKey('play')) {
        request.response.write(jsonEncode({
          'url': 'https://cdn.example/video.m3u8',
          'format': 'application/dash+xml',
          'header': {'Referer': 'https://example.com/'},
        }));
      } else if (request.uri.queryParameters['ids'] == 'movie-1') {
        request.response.write(jsonEncode({
          'list': [
            {
              'vod_id': 'movie-1',
              'vod_name': '测试电影',
              'vod_play_from': '线路',
              'vod_play_url': r'正片$play-id',
            },
          ],
        }));
      } else if (request.uri.queryParameters['t'] == '1') {
        expect(request.uri.queryParameters['ac'], 'detail');
        request.response.write(jsonEncode({
          'list': [
            {'vod_id': 'movie-1', 'vod_name': '测试电影'},
          ],
        }));
      } else {
        request.response.write(jsonEncode({
          'class': [
            {'type_id': '1', 'type_name': '电影'},
          ],
        }));
      }
      await request.response.close();
    });
    final base = 'http://${server.address.address}:${server.port}';

    try {
      final jsonClient = TvboxClient(TvboxSite(
          key: 'json', name: 'JSON', type: 1, apiUrl: '$base/json?ac=list'));
      expect((await jsonClient.categories()).single.name, '电影');
      expect((await jsonClient.videos(typeId: '1')).single.name, '测试电影');
      expect((await jsonClient.detail('movie-1')).playUrl, r'正片$play-id');

      final remoteClient = TvboxClient(TvboxSite(
          key: 'remote', name: 'Remote', type: 4, apiUrl: '$base/remote'));
      final playback = await remoteClient.playback('线路', 'play-id');
      expect(playback.uri, 'https://cdn.example/video.m3u8');
      expect(playback.mimeType, 'application/dash+xml');
      expect(playback.headers['Referer'], 'https://example.com/');
    } finally {
      await server.close(force: true);
      await subscription.cancel();
    }
  });

  test('marks TVBox getM3u8 playback as HLS without rewriting URL', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final subscription = server.listen((request) async {
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode({
        'url': 'https://api.example/getM3u8?vid=1',
        'header': {'Referer': 'https://example.com/'},
      }));
      await request.response.close();
    });

    try {
      final client = TvboxClient(TvboxSite(
          key: 'remote',
          name: 'Remote',
          type: 4,
          apiUrl: 'http://${server.address.address}:${server.port}/remote'));
      final playback = await client.playback('线路', 'play-id');
      expect(playback.uri, 'https://api.example/getM3u8?vid=1');
      expect(playback.mimeType, 'application/x-mpegURL');
    } finally {
      await server.close(force: true);
      await subscription.cancel();
    }
  });

  test('parses type 0 XML and skips failed sites', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final subscription = server.listen((request) async {
      request.response.headers.contentType = ContentType('application', 'xml');
      request.response.add(utf8.encode('''
<rss><class><ty id="2">连续剧</ty></class><list><video>
<id>tv-1</id><name>测试剧</name><pic>poster.jpg</pic><note>更新</note>
<dl><dd flag="线路A">第1集\$https://cdn.example/1.m3u8</dd></dl>
</video></list></rss>
'''));
      await request.response.close();
    });
    final site = TvboxSite(
        key: 'xml',
        name: 'XML',
        type: 0,
        apiUrl: 'http://${server.address.address}:${server.port}/xml');

    try {
      final client = TvboxClient(site);
      expect((await client.categories()).single.name, '连续剧');
      final video = (await client.videos(typeId: '2')).single;
      expect(video.name, '测试剧');
      expect(
          parseTvboxPlayGroups(video.playFrom, video.playUrl)
              .single
              .episodes
              .single
              .url,
          'https://cdn.example/1.m3u8');
      final selected = await firstWorkingTvboxSite(
        [
          const TvboxSite(
              key: 'bad', name: 'Bad', type: 1, apiUrl: 'https://bad'),
          site,
        ],
        (value) => value.key == 'bad'
            ? Future.error(const HttpException('failed'))
            : Future.value(const [TvboxCategory('2', '连续剧')]),
      );
      expect(selected.$1.key, 'xml');
    } finally {
      await server.close(force: true);
      await subscription.cancel();
    }
  });

  test('passes resolved playback and direct media URLs to the player',
      () async {
    final groups = parseTvboxPlayGroups(
      r'线路A$$$线路B',
      r'第1集$https://cdn.example/1.m3u8#第2集$https://cdn.example/2.m3u8$$$正片$https://cdn.example/movie.mp4',
    );
    expect(groups.map((group) => group.name), ['线路A', '线路B']);
    expect(groups.first.episodes.last.name, '第2集');

    final playback = await playbackForItem(
      AppStore(),
      const MediaItem(
        id: 'tvbox:1',
        sourceId: 'tvbox',
        sourceName: 'TVBox',
        type: SourceType.local,
        title: '测试',
        uri: 'https://cdn.example/1.m3u8',
      ),
    );
    expect(playback.uri, 'https://cdn.example/1.m3u8');
  });

  test('keeps the TVBox episode queue and recent playback context', () {
    const site = TvboxSite(
      key: 'site',
      name: '线路',
      type: 0,
      apiUrl: 'https://example.com/api.php',
    );
    const video = TvboxVideo(
      id: 'show',
      name: '测试剧',
      playFrom: '线路A',
      playUrl: r'第1集$one#第2集$two',
    );
    final group = parseTvboxPlayGroups(video.playFrom, video.playUrl).single;
    final items = tvboxMediaItems(site, video, group);

    expect(items.map((item) => item.episode), [1, 2]);
    expect(items.map((item) => item.uri), ['one', 'two']);
    expect(items.map(mediaFolderKey).toSet(), hasLength(1));

    final restored = TvboxRecentEntry.fromJson(TvboxRecentEntry(
      site: site,
      video: video,
      groupName: group.name,
      episodeName: group.episodes.last.name,
      episodeUrl: group.episodes.last.url,
      lastPlayedAt: 123,
      positionMs: 45,
      durationMs: 90,
    ).toJson());
    expect(restored.item.id, items.last.id);
    expect(restored.libraryRecent.displayTitle, '测试剧 第 2 集 第2集');
  });
}
