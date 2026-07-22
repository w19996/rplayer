import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:player_flutter/main.dart';

void main() {
  test('fast search keeps results containing every title word', () {
    expect(tvboxSearchNameMatches('功夫女足 4K', '功夫 女足'), isTrue);
    expect(tvboxSearchNameMatches('功夫足球', '功夫 女足'), isFalse);
  });

  test('keeps Spider action cards without video ids', () {
    final action = TvboxClient(const TvboxSite(
      key: 'cloud',
      name: '网盘',
      type: 3,
      apiUrl: 'csp_Cloud',
    ))
        .parseVideos(jsonEncode({
          'list': [
            {'vod_name': '登录网盘', 'action': 'login'},
          ],
        }))
        .single;

    expect(action.id, isEmpty);
    expect(action.action, 'login');
    expect(tvboxVideoOpenTarget(action), TvboxVideoOpenTarget.action);
    expect(
      tvboxVideoOpenTarget(const TvboxVideo(id: 'movie-1', name: '电影')),
      TvboxVideoOpenTarget.detail,
    );
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
    expect(
      normalizeTvboxSourceUrl('https://盒子迷.top/禁止贩卖'),
      startsWith('https://xn--'),
    );
    final config = jsonEncode({
      'sites': [
        {'key': 'xml', 'name': 'XML', 'type': 0, 'api': './xml'},
        {'key': 'json', 'name': 'JSON', 'type': 1, 'api': './json'},
        {'key': 'idn', 'name': 'IDN', 'type': 1, 'api': 'https://盒子迷.top/api'},
        {
          'key': 'remote',
          'name': 'Remote',
          'type': 4,
          'api': './remote',
          'searchable': 0,
        },
        {'key': 'spider', 'name': 'Spider', 'type': 3, 'api': 'csp_Test'},
        {'key': 'js', 'name': 'JS', 'type': 3, 'api': './cat.js'},
        {'key': 'py', 'name': 'Python', 'type': 3, 'api': './cat.py'},
      ],
    });
    final wrapped = [
      ...<int>[0xff, 0xd8, 0xff, 0xd9],
      ...latin1.encode('12345678**${base64Encode(utf8.encode(config))}'),
    ];
    final sites = tvboxSitesFromConfig('https://example.com/config.json',
        jsonDecode(decodeTvboxConfigBytes(wrapped)));

    expect(
      sites.map((site) => site.key),
      Platform.isWindows
          ? ['xml', 'json', 'idn', 'remote', 'js', 'py']
          : ['xml', 'json', 'idn', 'remote'],
    );
    expect(sites.first.apiUrl, 'https://example.com/xml');
    expect(sites[2].apiUrl, startsWith('https://xn--'));
    expect(sites[3].apiUrl, 'https://example.com/remote');
    expect(sites[3].searchable, isFalse);
    if (Platform.isWindows) {
      expect(sites[4].apiUrl, 'https://example.com/cat.js');
      expect(sites[5].apiUrl, 'https://example.com/cat.py');
    }
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
    expect(tvboxIsScriptApi('https://example.com/cat.js'), isTrue);
    expect(tvboxIsScriptApi('https://example.com/cat.py?token=1'), isTrue);
    expect(tvboxIsScriptApi('csp_Test'), isFalse);
    expect(TvboxScriptRuntime.canHandle('https://example.com/cat.js'),
        Platform.isWindows);
    expect(TvboxScriptRuntime.canHandle('https://example.com/cat.py'),
        Platform.isWindows);
    expect(TvboxScriptRuntime.canHandle('csp_Test'), isFalse);
    final warehouses =
        tvboxWarehousesFromConfig('https://example.com/config/main.json', {
      'urls': [
        {'name': '盒子迷', 'url': 'https://盒子迷.top/禁止贩卖'},
        {'name': '相对仓库', 'url': '../nested.json'},
      ],
    });
    expect(warehouses.map((item) => item.name), ['盒子迷', '相对仓库']);
    expect(warehouses.first.url, startsWith('https://xn--'));
    expect(warehouses.last.url, 'https://example.com/nested.json');
    expect(
      () => tvboxSitesFromConfig('https://example.com/config', {
        'sites': [
          {'type': 3, 'api': 'csp_Test'},
        ],
      }),
      throwsA(isA<FormatException>().having((error) => error.message, 'message',
          contains('Spider/JAR/JS/Python'))),
    );
  });

  test('runs Windows JS Spider with module imports', () async {
    if (!Platform.isWindows) return;
    final quickjsDll =
        File('${p.dirname(Platform.resolvedExecutable)}\\quickjs_c_bridge.dll');
    if (!await quickjsDll.exists()) return;
    final dir = await Directory.systemTemp.createTemp('tvbox-js-test-');
    try {
      final helper = File('${dir.path}${Platform.pathSeparator}helper.js');
      await helper.writeAsString("export const title = '首页';");
      final script = File('${dir.path}${Platform.pathSeparator}cat.js');
      await script.writeAsString('''
import { title } from './helper.js';
export default {
  init(cfg) { this.cfg = cfg; },
  home(filter) { return JSON.stringify({ class: [{ type_id: '1', type_name: title }], ext: this.cfg.ext }); },
  detail(id) { return JSON.stringify({ list: [{ vod_id: id }] }); }
};
''');
      final site = TvboxSite(
        key: 'js-test',
        name: 'JS Test',
        type: 3,
        apiUrl: script.path,
        ext: '{"token":"ok"}',
      );

      expect(jsonDecode(await TvboxScriptRuntime.call(site, 'home'))['ext'],
          {'token': 'ok'});
      expect(
        jsonDecode(await TvboxScriptRuntime.call(site, 'detail', {
          'id': 'vod-1',
        }))['list'][0]['vod_id'],
        'vod-1',
      );
    } finally {
      await dir.delete(recursive: true);
    }
  });

  test('Windows script playback resolves proxy urls', () async {
    if (!Platform.isWindows) return;
    final playback = await TvboxScriptRuntime.finishPlayback(
      const TvboxSite(
        key: 'proxy-test',
        name: 'Proxy Test',
        type: 3,
        apiUrl: 'https://example.com/cat.js',
      ),
      {
        'url': 'proxy://do=js&siteKey=proxy-test&url=/media',
        'header': {'User-Agent': 'TVBox'},
      },
    );

    expect(playback.uri,
        'http://127.0.0.1:9978/proxy?do=js&siteKey=proxy-test&url=/media');
    expect(playback.headers['User-Agent'], 'TVBox');
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
          'danmaku': 'https://cdn.example/video.xml',
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
      expect(playback.danmaku, 'https://cdn.example/video.xml');
    } finally {
      await server.close(force: true);
      await subscription.cancel();
    }
  });

  test('does not auto-select the first TVBox warehouse', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final subscription = server.listen((request) async {
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode({
        'urls': [
          {'name': '仓库一', 'url': '/one.json'},
          {'name': '仓库二', 'url': '/two.json'},
        ],
      }));
      await request.response.close();
    });

    try {
      await expectLater(
        const TvboxResolver()
            .resolveConfig('http://${server.address.address}:${server.port}/'),
        throwsA(isA<FormatException>()
            .having((error) => error.message, 'message', contains('多仓订阅'))),
      );
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

  test('marks direct TVBox HLS playback for libmpv', () async {
    final playback = await TvboxClient(const TvboxSite(
      key: 'json',
      name: 'JSON',
      type: 1,
      apiUrl: 'https://example.com/api',
    )).playback('', 'https://example.com/live.m3u8');

    expect(playback.uri, 'https://example.com/live.m3u8');
    expect(playback.mimeType, 'application/x-mpegURL');
  });

  test('parses TVBox live config, M3U and TXT channel lists', () {
    final lives = tvboxLivesFromConfig('https://example.com/config/main.json', {
      'lives': [
        {
          'name': '主直播',
          'url': '../live.m3u',
          'ua': 'TVBox',
          'header': {'Referer': 'https://example.com/'},
        },
      ],
    });
    expect(lives.single.url, 'https://example.com/live.m3u');
    expect(lives.single.headers['User-Agent'], 'TVBox');
    expect(
      tvboxLivesFromConfig('https://example.com/config/main.json', {
        'lives': [
          {'name': 'IDN', 'url': 'https://肥猫.com/live.txt'},
        ],
      }).single.url,
      startsWith('https://xn--'),
    );

    final m3u = parseTvboxLiveGroups('''#EXTM3U
#EXTINF:-1 group-title="央视" tvg-logo="cctv.png",CCTV-1
https://live.example/cctv1.m3u8|User-Agent=TVBox&Referer=https%3A%2F%2Fexample.com%2F
#EXTINF:-1 group-title="央视",CCTV-1
https://backup.example/cctv1.m3u8
''');
    expect(m3u.single.name, '央视');
    expect(m3u.single.channels.single.urls, hasLength(2));
    expect(m3u.single.channels.single.headers['User-Agent'], 'TVBox');

    final txt = parseTvboxLiveGroups('''地方台,#genre#
测试台,https://live.example/1.m3u8#https://live.example/2.m3u8
''');
    expect(txt.single.name, '地方台');
    expect(txt.single.channels.single.urls, hasLength(2));

    final plain = parseTvboxLiveGroups('''轮播频道,#genre#
亮剑,http://8.155.43.98:35455/huya/30080238
''');
    expect(
      tvboxLivePlaybackHeaders(
        const TvboxLiveSource(name: '直播', url: 'https://example.com/live.txt'),
        plain.single.channels.single,
        const {},
      )['User-Agent'],
      'TVBox',
    );
  });

  test('resolves TVBox live redirect with playback headers', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final subscription = server.listen((request) async {
      expect(request.method, 'GET');
      expect(request.headers.value(HttpHeaders.userAgentHeader), 'TVBox');
      if (request.uri.path == '/huya/1') {
        request.response.statusCode = HttpStatus.movedPermanently;
        request.response.headers
            .set(HttpHeaders.locationHeader, '/al/stream.flv?token=1');
      } else if (request.uri.path == '/al/stream.flv') {
        request.response.statusCode = HttpStatus.movedTemporarily;
        request.response.headers
            .set(HttpHeaders.locationHeader, '/real/stream.flv?token=2');
      } else {
        request.response.statusCode = HttpStatus.ok;
      }
      await request.response.close();
    });
    final source = TvboxLiveSource(
      name: '直播',
      url: 'http://${server.address.host}:${server.port}/live.txt',
    );
    final channel = TvboxLiveChannel(
      name: '轮播',
      urls: ['http://${server.address.host}:${server.port}/huya/1'],
    );

    try {
      final playback =
          await resolveTvboxLivePlayback(source, channel, channel.urls.single);
      expect(playback.uri,
          'http://${server.address.host}:${server.port}/real/stream.flv?token=2');
      expect(playback.headers['User-Agent'], 'TVBox');
      expect(playback.mimeType, 'video/x-flv');
      expect(
          await tvboxLivePlaybackUrl(
            playback.uri,
            playback.headers,
            true,
          ),
          startsWith('http://127.0.0.1:'));
    } finally {
      await subscription.cancel();
      await server.close(force: true);
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
      r'夸克原画#0102$$$线路B',
      r'第1集$https://cdn.example/1.m3u8#第2集$https://cdn.example/2.m3u8$$$正片$https://cdn.example/movie.mp4',
    );
    expect(groups.map((group) => group.name), ['夸克原画#0102', '线路B']);
    expect(groups.first.episodes.last.name, '第2集');

    final detail = TvboxVideo.fromJson({
      'vod_id': 'movie-1',
      'vod_name': '测试',
      'vod_actor': '演员甲,演员乙',
      'vod_director': '导演甲',
      'vod_year': '2026',
      'vod_score': '8.6',
    });
    expect((detail.actor, detail.director, detail.year, detail.score),
        ('演员甲,演员乙', '导演甲', '2026', '8.6'));

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

  test('tries later TVBox lines with the same episode', () {
    final groups = parseTvboxPlayGroups(
      r'线路A$$$线路B$$$线路C',
      r'1$a1#2$a2$$$上集$b1#下集$b2$$$1$c1#2$c2',
    );

    final candidates = tvboxPlaybackCandidates(
        groups, groups.first, groups.first.episodes.last);

    expect(candidates.map((candidate) => candidate.$1.name),
        ['线路A', '线路B', '线路C']);
    expect(candidates.map((candidate) => candidate.$2.url), ['a2', 'b2', 'c2']);
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
