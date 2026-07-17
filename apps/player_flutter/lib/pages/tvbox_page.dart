part of 'package:player_flutter/main.dart';

class TvboxCategory {
  const TvboxCategory(this.id, this.name);

  final String id;
  final String name;
}

class TvboxSite {
  const TvboxSite({
    required this.key,
    required this.name,
    required this.type,
    required this.apiUrl,
    this.ext = '',
    this.playUrl = '',
    this.headers = const {},
    this.jarUrl = '',
    this.jarMd5 = '',
    this.searchable = true,
  });

  final String key;
  final String name;
  final int type;
  final String apiUrl;
  final String ext;
  final String playUrl;
  final Map<String, String> headers;
  final String jarUrl;
  final String jarMd5;
  final bool searchable;

  factory TvboxSite.fromJson(Map<String, dynamic> json) => TvboxSite(
        key: json['key'] as String? ?? '',
        name: json['name'] as String? ?? '',
        type: (json['type'] as num?)?.toInt() ?? 0,
        apiUrl: json['apiUrl'] as String? ?? '',
        ext: json['ext'] as String? ?? '',
        playUrl: json['playUrl'] as String? ?? '',
        headers: (json['headers'] as Map<String, dynamic>? ?? const {})
            .map((key, value) => MapEntry(key, '$value')),
        jarUrl: json['jarUrl'] as String? ?? '',
        jarMd5: json['jarMd5'] as String? ?? '',
        searchable: json['searchable'] as bool? ?? true,
      );

  Map<String, dynamic> toJson() => {
        'key': key,
        'name': name,
        'type': type,
        'apiUrl': apiUrl,
        'ext': ext,
        'playUrl': playUrl,
        'headers': headers,
        'jarUrl': jarUrl,
        'jarMd5': jarMd5,
        'searchable': searchable,
      };
}

class TvboxVideo {
  const TvboxVideo({
    required this.id,
    required this.name,
    this.picture = '',
    this.remarks = '',
    this.content = '',
    this.playFrom = '',
    this.playUrl = '',
  });

  factory TvboxVideo.fromJson(Map<String, dynamic> json) => TvboxVideo(
        id: '${json['vod_id'] ?? json['id'] ?? ''}',
        name: '${json['vod_name'] ?? json['name'] ?? ''}',
        picture: '${json['vod_pic'] ?? json['pic'] ?? ''}',
        remarks: '${json['vod_remarks'] ?? json['note'] ?? ''}',
        content: '${json['vod_content'] ?? json['des'] ?? ''}',
        playFrom: '${json['vod_play_from'] ?? ''}',
        playUrl: '${json['vod_play_url'] ?? ''}',
      );

  final String id;
  final String name;
  final String picture;
  final String remarks;
  final String content;
  final String playFrom;
  final String playUrl;

  Map<String, dynamic> toJson() => {
        'vod_id': id,
        'vod_name': name,
        'vod_pic': picture,
        'vod_remarks': remarks,
        'vod_content': content,
        'vod_play_from': playFrom,
        'vod_play_url': playUrl,
      };
}

class TvboxEpisode {
  const TvboxEpisode(this.name, this.url);

  final String name;
  final String url;
}

class TvboxPlayGroup {
  const TvboxPlayGroup(this.name, this.episodes);

  final String name;
  final List<TvboxEpisode> episodes;
}

typedef TvboxVideoSource = ({TvboxSite site, TvboxVideo video});
typedef TvboxHome = ({List<TvboxCategory> categories, List<TvboxVideo> videos});

class TvboxRecentEntry {
  const TvboxRecentEntry({
    required this.site,
    required this.video,
    required this.groupName,
    required this.episodeName,
    required this.episodeUrl,
    required this.lastPlayedAt,
    this.positionMs = 0,
    this.durationMs,
  });

  factory TvboxRecentEntry.fromJson(Map<String, dynamic> json) =>
      TvboxRecentEntry(
        site: TvboxSite.fromJson(json['site'] as Map<String, dynamic>),
        video: TvboxVideo.fromJson(json['video'] as Map<String, dynamic>),
        groupName: json['groupName'] as String? ?? '',
        episodeName: json['episodeName'] as String? ?? '',
        episodeUrl: json['episodeUrl'] as String? ?? '',
        lastPlayedAt: (json['lastPlayedAt'] as num?)?.toInt() ?? 0,
        positionMs: (json['positionMs'] as num?)?.toInt() ?? 0,
        durationMs: (json['durationMs'] as num?)?.toInt(),
      );

  final TvboxSite site;
  final TvboxVideo video;
  final String groupName;
  final String episodeName;
  final String episodeUrl;
  final int lastPlayedAt;
  final int positionMs;
  final int? durationMs;

  String get groupKey => '${site.key}\t${video.id}\t$groupName';
  MediaItem get item {
    final group = parseTvboxPlayGroups(video.playFrom, video.playUrl)
        .where((value) => value.name == groupName)
        .firstOrNull;
    final episodes = group?.episodes ?? const <TvboxEpisode>[];
    final index = episodes.indexWhere((value) => value.url == episodeUrl);
    return tvboxMediaItem(
      site,
      video,
      groupName,
      TvboxEpisode(episodeName, episodeUrl),
      index < 0 ? 0 : index,
    );
  }

  LibraryRecentEntry get libraryRecent => LibraryRecentEntry(
        fileId: 0,
        itemId: item.id,
        relativePath: episodeUrl,
        filename: video.name,
        positionMs: positionMs,
        durationMs: durationMs,
        lastPlayedAt: lastPlayedAt,
        showTitle: video.name,
        episodeNumber: item.episode,
        episodeName: episodeName,
      );

  TvboxRecentEntry copyWith({
    String? episodeName,
    String? episodeUrl,
    int? lastPlayedAt,
    int? positionMs,
    int? durationMs,
  }) =>
      TvboxRecentEntry(
        site: site,
        video: video,
        groupName: groupName,
        episodeName: episodeName ?? this.episodeName,
        episodeUrl: episodeUrl ?? this.episodeUrl,
        lastPlayedAt: lastPlayedAt ?? this.lastPlayedAt,
        positionMs: positionMs ?? this.positionMs,
        durationMs: durationMs ?? this.durationMs,
      );

  Map<String, dynamic> toJson() => {
        'site': site.toJson(),
        'video': video.toJson(),
        'groupName': groupName,
        'episodeName': episodeName,
        'episodeUrl': episodeUrl,
        'lastPlayedAt': lastPlayedAt,
        'positionMs': positionMs,
        'durationMs': durationMs,
      };
}

MediaItem tvboxMediaItem(TvboxSite site, TvboxVideo video, String groupName,
        TvboxEpisode episode, int index) =>
    MediaItem(
      id: 'tvbox:${site.key}:${video.id}:$groupName:${episode.name}',
      sourceId: 'tvbox',
      sourceName: site.name,
      type: SourceType.local,
      title: '${video.name} ${episode.name}',
      uri: episode.url,
      folderTitle: video.name,
      matchTitle: video.name,
      season: 1,
      episode: index + 1,
      mediaKind: 'TvEpisode',
      groupPath: '${site.key}/${video.id}/$groupName',
    );

List<MediaItem> tvboxMediaItems(
        TvboxSite site, TvboxVideo video, TvboxPlayGroup group) =>
    [
      for (var index = 0; index < group.episodes.length; index++)
        tvboxMediaItem(site, video, group.name, group.episodes[index], index),
    ];

Future<void> openTvboxPlayback(
  BuildContext context,
  AppStore store,
  TvboxClient client,
  TvboxVideo video,
  TvboxPlayGroup group,
  TvboxEpisode episode,
) async {
  final episodes = tvboxMediaItems(client.site, video, group);
  final index = group.episodes.indexWhere((value) => value.url == episode.url);
  if (index < 0) throw StateError('找不到所选剧集');
  final current = episodes[index];

  Future<RemotePlayback> resolve(MediaItem item) async {
    final itemIndex = episodes.indexWhere((value) => value.id == item.id);
    if (itemIndex < 0) throw StateError('找不到所选剧集');
    final selected = group.episodes[itemIndex];
    await store.rememberTvboxRecent(TvboxRecentEntry(
      site: client.site,
      video: video,
      groupName: group.name,
      episodeName: selected.name,
      episodeUrl: selected.url,
      lastPlayedAt: DateTime.now().millisecondsSinceEpoch,
      positionMs: store.progress[item.id] ?? 0,
      durationMs: store.durations[item.id],
    ));
    return client.playback(group.name, selected.url);
  }

  final playback = await resolve(current);
  if (!context.mounted) return;
  openPlayer(
    context,
    store,
    current,
    playback: playback,
    episodes: episodes,
    playbackResolver: resolve,
  );
}

Future<void> openTvboxRecent(
    BuildContext context, AppStore store, TvboxRecentEntry recent) async {
  final group =
      parseTvboxPlayGroups(recent.video.playFrom, recent.video.playUrl)
          .where((value) => value.name == recent.groupName)
          .firstOrNull;
  if (group == null) throw StateError('最近播放的剧集数据已失效');
  final episode = group.episodes
      .where((value) => value.url == recent.episodeUrl)
      .firstOrNull;
  if (episode == null) throw StateError('最近播放的选集已失效');
  await openTvboxPlayback(
      context, store, TvboxClient(recent.site), recent.video, group, episode);
}

const _tvboxHomeTypeId = 'rplayer_tvbox_home';
final _tvboxImageFutures = <String, Future<Uint8List?>>{};

bool tvboxSearchNameMatches(String name, String keyword) {
  final lowerName = name.toLowerCase();
  return keyword
      .trim()
      .toLowerCase()
      .split(RegExp(r'\s+'))
      .every(lowerName.contains);
}

({String url, Map<String, String> headers}) tvboxImageRequest(String value) {
  final raw = value.trim();
  if (raw.startsWith('data:')) return (url: raw, headers: const {});

  String? option(String name) =>
      RegExp('(?:^|@)${RegExp.escape(name)}=([^@]*)').firstMatch(raw)?.group(1);

  final headers = <String, String>{};
  final encodedHeaders = option('Headers');
  if (encodedHeaders != null) {
    try {
      headers.addAll(
          _tvboxHeaders(jsonDecode(Uri.decodeComponent(encodedHeaders))));
    } on FormatException {
      // Ignore malformed optional image headers, matching TVBoxOS behavior.
    }
  }
  for (final name in const ['Cookie', 'User-Agent', 'Referer']) {
    final value = option(name);
    if (value != null && value.isNotEmpty) headers[name] = value;
  }

  var url = raw.split('@').first.trim();
  if (url.startsWith('//')) url = 'https:$url';
  if (url.contains('doubanio.com')) {
    headers.putIfAbsent('Referer', () => 'https://api.douban.com/');
    headers.putIfAbsent(
        'User-Agent',
        () =>
            'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 Chrome/120 Safari/537.36');
  }
  return (url: url, headers: headers);
}

Future<Uint8List?> _loadTvboxImage(
    ({String url, Map<String, String> headers}) request) {
  final key = '${request.url}\n${jsonEncode(request.headers)}';
  final cached = _tvboxImageFutures[key];
  if (cached != null) return cached;
  // ponytail: FIFO cap; use a disk/LRU cache only if image churn becomes measurable.
  if (_tvboxImageFutures.length >= 200) {
    _tvboxImageFutures.remove(_tvboxImageFutures.keys.first);
  }
  final future = () async {
    try {
      final response = await http
          .get(Uri.parse(request.url), headers: request.headers)
          .timeout(const Duration(seconds: 20));
      return response.statusCode >= 200 && response.statusCode < 300
          ? response.bodyBytes
          : null;
    } on Object {
      return null;
    }
  }();
  _tvboxImageFutures[key] = future;
  future.then((bytes) {
    if (bytes == null && identical(_tvboxImageFutures[key], future)) {
      _tvboxImageFutures.remove(key);
    }
  });
  return future;
}

String normalizeTvboxSourceUrl(String value) {
  final uri = Uri.parse(value.trim());
  final segments = uri.pathSegments;
  if (uri.host == 'github.com' &&
      segments.length >= 5 &&
      segments[2] == 'blob') {
    return Uri(
      scheme: 'https',
      host: 'raw.githubusercontent.com',
      pathSegments: [segments[0], segments[1], ...segments.skip(3)],
    ).toString();
  }
  return uri.toString();
}

String decodeTvboxConfigBytes(List<int> bytes) {
  final text = utf8
      .decode(bytes, allowMalformed: true)
      .replaceFirst('\ufeff', '')
      .trim();
  if (text.startsWith('{') || text.startsWith('<rss')) return text;
  final binary = latin1.decode(bytes, allowInvalid: true);
  final marker = RegExp(r'[A-Za-z0-9]{8}\*\*').firstMatch(binary);
  if (marker != null) {
    final payload =
        binary.substring(marker.end).replaceAll(RegExp(r'[\s\x00]'), '');
    return utf8.decode(base64Decode(base64.normalize(payload))).trim();
  }
  if (text.startsWith('2423')) {
    throw const FormatException('该配置使用 AES 加密，当前跨平台版本暂不支持');
  }
  if (RegExp(r'<(?:!doctype|html)', caseSensitive: false).hasMatch(text)) {
    final title = RegExp(r'<title>(.*?)</title>', caseSensitive: false)
        .firstMatch(text)
        ?.group(1)
        ?.trim();
    throw FormatException(
        '地址返回网页而不是 TVBox 配置${title == null ? '' : '：$title'}');
  }
  throw const FormatException('响应不是 TVBox 配置或 CMS 接口');
}

int _tvboxType(Object? value) =>
    value is num ? value.toInt() : int.tryParse('$value') ?? 0;

String _tvboxConfigValue(String baseUrl, Object? value) {
  if (value == null) return '';
  if (value is! String) return jsonEncode(value);
  final text = value.trim();
  if (text.isEmpty || text.startsWith('csp_')) return text;
  return Uri.parse(baseUrl).resolve(text).toString();
}

String tvboxSpiderExt(String baseUrl, Object? value) {
  Object? resolve(Object? item) {
    if (item is Map) {
      return item.map((key, value) => MapEntry('$key', resolve(value)));
    }
    if (item is List) return item.map(resolve).toList();
    if (item is! String) return item;
    final text = item.trim();
    if (text.startsWith('./') ||
        text.startsWith('../') ||
        text.startsWith('/') ||
        RegExp(r'\.(?:json|txt|js)$', caseSensitive: false).hasMatch(text)) {
      return Uri.parse(baseUrl).resolve(text).toString();
    }
    return text;
  }

  final result = resolve(value);
  return result is String ? result : jsonEncode(result);
}

Map<String, String> _tvboxHeaders(Object? value) {
  if (value is String && value.trim().startsWith('{')) {
    return _tvboxHeaders(jsonDecode(value));
  }
  if (value is! Map) return const {};
  return value.map((key, value) => MapEntry('$key', '$value'));
}

(String, String) parseTvboxJarSpec(String baseUrl, Object? value) {
  final raw = value?.toString().trim() ?? '';
  if (raw.isEmpty) return ('', '');
  final parts = raw.split(';md5;');
  return (
    _tvboxConfigValue(baseUrl, parts.first),
    parts.length > 1 ? parts[1].trim() : ''
  );
}

List<TvboxSite> tvboxSitesFromConfig(
    String sourceUrl, Map<String, dynamic> json) {
  final values = json['sites'] as List<dynamic>?;
  if (values == null) {
    if (json.containsKey('class') || json.containsKey('list')) {
      return [
        TvboxSite(
          key: 'direct',
          name: '当前接口',
          type: 1,
          apiUrl: sourceUrl,
        ),
      ];
    }
    throw const FormatException('JSON 中没有 sites、class 或 list');
  }
  final all = values.whereType<Map<String, dynamic>>().toList();
  final sites = all.map((value) {
    final type = _tvboxType(value['type']);
    final jar = parseTvboxJarSpec(sourceUrl, value['jar'] ?? json['spider']);
    return TvboxSite(
      key: '${value['key'] ?? value['name'] ?? ''}',
      name: '${value['name'] ?? value['key'] ?? '未命名站点'}',
      type: type,
      apiUrl: _tvboxConfigValue(sourceUrl, value['api']),
      ext: type == 3
          ? tvboxSpiderExt(sourceUrl, value['ext'])
          : _tvboxConfigValue(sourceUrl, value['ext']),
      playUrl: '${value['playUrl'] ?? ''}',
      headers: _tvboxHeaders(value['header']),
      jarUrl: jar.$1,
      jarMd5: jar.$2,
      searchable: _tvboxType(value['searchable'] ?? 1) != 0,
    );
  }).where((site) {
    if (site.type == 3) {
      return Platform.isAndroid &&
          site.apiUrl.startsWith('csp_') &&
          Uri.tryParse(site.jarUrl)?.hasAuthority == true;
    }
    if (site.type != 0 && site.type != 1 && site.type != 4) return false;
    final uri = Uri.tryParse(site.apiUrl);
    return uri != null &&
        uri.hasAuthority &&
        (uri.scheme == 'http' || uri.scheme == 'https');
  }).toList();
  if (sites.isNotEmpty) return sites;
  final types = all.map((site) => _tvboxType(site['type'])).toSet().toList()
    ..sort();
  throw FormatException(
      '配置已读取，但 ${all.length} 个站点均需当前不支持的 Spider/JAR/JS（type ${types.join(', ')}）');
}

List<TvboxPlayGroup> parseTvboxPlayGroups(String from, String value) {
  final names = from.split(r'$$$');
  final groups = value.split(r'$$$');
  return groups.indexed
      .map((entry) {
        final episodes = entry.$2
            .split('#')
            .where((item) => item.isNotEmpty)
            .map((item) {
              final separator = item.indexOf(r'$');
              return separator < 0
                  ? TvboxEpisode('播放', item)
                  : TvboxEpisode(item.substring(0, separator),
                      item.substring(separator + 1));
            })
            .where((episode) => episode.url.isNotEmpty)
            .toList();
        final name = entry.$1 < names.length && names[entry.$1].isNotEmpty
            ? names[entry.$1]
            : '线路 ${entry.$1 + 1}';
        return TvboxPlayGroup(name, episodes);
      })
      .where((group) => group.episodes.isNotEmpty)
      .toList();
}

Future<(TvboxSite, List<TvboxCategory>)> firstWorkingTvboxSite(
  List<TvboxSite> sites,
  Future<List<TvboxCategory>> Function(TvboxSite site) load,
) async {
  Object? lastError;
  for (final site in sites) {
    try {
      return (site, await load(site));
    } catch (error) {
      lastError = error;
    }
  }
  throw lastError ?? const FormatException('配置中没有可用站点');
}

class TvboxResolver {
  const TvboxResolver();

  Future<List<TvboxSite>> resolve(String sourceUrl, {int depth = 0}) async {
    if (depth > 3) throw const FormatException('TVBox 多仓嵌套过深');
    sourceUrl = normalizeTvboxSourceUrl(sourceUrl);
    final response = await http.get(Uri.parse(sourceUrl),
        headers: const {'accept': '*/*'}).timeout(const Duration(seconds: 20));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException('订阅返回 HTTP ${response.statusCode}');
    }
    final text = decodeTvboxConfigBytes(response.bodyBytes);
    if (text.startsWith('<rss')) {
      return [
        TvboxSite(key: 'direct', name: '当前接口', type: 0, apiUrl: sourceUrl)
      ];
    }
    final value = jsonDecode(text);
    if (value is! Map<String, dynamic>) {
      throw const FormatException('订阅不是 JSON 对象');
    }
    if (value['urls'] case final List<dynamic> urls) {
      final first = urls.whereType<Map>().firstOrNull;
      final nested = first?['url'];
      if (nested == null) throw const FormatException('多仓订阅中没有有效地址');
      return resolve(_tvboxConfigValue(sourceUrl, nested), depth: depth + 1);
    }
    return tvboxSitesFromConfig(sourceUrl, value);
  }
}

class TvboxClient {
  TvboxClient(this.site);

  final TvboxSite site;
  String? _ext;

  Future<String> _spider(String action,
      [Map<String, Object?> arguments = const {}]) async {
    if (!Platform.isAndroid) {
      throw UnsupportedError('Spider/JAR 仅支持 Android');
    }
    final value = await appChannel.invokeMethod<String>('tvboxCall', {
      'action': action,
      'key': site.key,
      'api': site.apiUrl,
      'ext': site.ext,
      'jarUrl': site.jarUrl,
      'jarMd5': site.jarMd5,
      ...arguments,
    });
    if (value == null || value.isEmpty) {
      throw const FormatException('Spider/JAR 未返回数据');
    }
    return value;
  }

  Uri _uri(Map<String, String> query) {
    final uri = Uri.parse(site.apiUrl);
    return uri.replace(queryParameters: {...uri.queryParameters, ...query});
  }

  Future<String> _extension() async {
    if (_ext != null) return _ext!;
    if (!site.ext.startsWith('http')) return _ext = site.ext;
    final response = await http
        .get(Uri.parse(site.ext), headers: site.headers)
        .timeout(const Duration(seconds: 20));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException('扩展配置返回 HTTP ${response.statusCode}');
    }
    return _ext = utf8.decode(response.bodyBytes, allowMalformed: true).trim();
  }

  Future<String> _get(Map<String, String> query,
      {bool includeExt = true}) async {
    final params = Map<String, String>.from(query);
    if (includeExt) {
      final ext = await _extension();
      if (ext.isNotEmpty) params['extend'] = ext;
    }
    final response = await http.get(_uri(params), headers: {
      'accept': '*/*',
      ...site.headers
    }).timeout(const Duration(seconds: 20));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException('${site.name} 返回 HTTP ${response.statusCode}');
    }
    return utf8.decode(response.bodyBytes, allowMalformed: true).trim();
  }

  Future<List<TvboxCategory>> categories() async {
    return (await home()).categories;
  }

  Future<TvboxHome> home() async {
    final body = site.type == 3
        ? await _spider('home')
        : await _get(site.type == 4 ? const {'filter': 'true'} : const {},
            includeExt: site.type == 4);
    final categories = _parseCategories(body);
    if (categories.isNotEmpty) {
      return (categories: categories, videos: _parseVideos(body));
    }
    if (site.type == 3) {
      return (categories: categories, videos: _parseVideos(body));
    }
    final fallback =
        await _get({'ac': site.type == 0 ? 'videolist' : 'detail'});
    return (
      categories: _parseCategories(fallback),
      videos: _parseVideos(fallback),
    );
  }

  Future<List<TvboxVideo>> videos({String? typeId, String? keyword}) async {
    if (site.type == 3) {
      return _parseVideos(await _spider(
        keyword == null ? 'category' : 'search',
        keyword == null
            ? {'typeId': typeId ?? '', 'page': '1'}
            : {'keyword': keyword, 'page': '1'},
      ));
    }
    final query = keyword == null
        ? {
            'ac': site.type == 0 ? 'videolist' : 'detail',
            if (typeId != null) 't': typeId,
            'pg': '1',
            if (site.type == 4) 'ext': base64Url.encode(utf8.encode('{}')),
          }
        : {'wd': keyword, 'quick': 'false', 'extend': '', 'pg': '1'};
    return _parseVideos(await _get(query));
  }

  Future<TvboxVideo> detail(String id) async {
    final body = site.type == 3
        ? await _spider('detail', {'id': id})
        : await _get({
            'ac': site.type == 0 ? 'videolist' : 'detail',
            'ids': id,
          });
    final values = _parseVideos(body);
    if (values.isEmpty) throw const FormatException('接口未返回播放详情');
    return values.first;
  }

  Future<RemotePlayback> playback(String flag, String id) async {
    if (site.type != 3 && site.type != 4) {
      return RemotePlayback(id, site.headers);
    }
    final body = site.type == 3
        ? await _spider('player', {'flag': flag, 'id': id})
        : await _get({'play': id, 'flag': flag});
    final value = jsonDecode(body);
    if (value is! Map<String, dynamic>) {
      throw const FormatException('播放接口不是 JSON 对象');
    }
    final url = value['url'];
    final resolved =
        url is List ? (url.length > 1 ? url[1] : url.firstOrNull) : url;
    if (resolved == null || '$resolved'.isEmpty) {
      throw const FormatException('播放接口未返回地址');
    }
    final format = '${value['format'] ?? ''}'.trim();
    final inferredMimeType = format.isEmpty && _tvboxLooksHls('$resolved')
        ? 'application/x-mpegURL'
        : null;
    return RemotePlayback(
      '$resolved',
      {
        ...site.headers,
        ..._tvboxHeaders(value['header']),
      },
      mimeType: format.isEmpty ? inferredMimeType : format,
    );
  }

  List<TvboxCategory> _parseCategories(String body) {
    if (body.startsWith('<')) {
      final document = XmlDocument.parse(body);
      return document
          .findAllElements('ty')
          .map((node) => TvboxCategory(
              node.getAttribute('id') ?? '', node.innerText.trim()))
          .where((item) => item.id.isNotEmpty && item.name.isNotEmpty)
          .toList();
    }
    final value = jsonDecode(body);
    if (value is! Map) return const [];
    return (value['class'] as List<dynamic>? ?? const [])
        .whereType<Map>()
        .map((item) => TvboxCategory(
            '${item['type_id'] ?? ''}', '${item['type_name'] ?? ''}'))
        .where((item) => item.id.isNotEmpty && item.name.isNotEmpty)
        .toList();
  }

  List<TvboxVideo> _parseVideos(String body) {
    if (body.startsWith('<')) return _parseXmlVideos(body);
    final value = jsonDecode(body);
    if (value is! Map) return const [];
    return (value['list'] as List<dynamic>? ?? const [])
        .whereType<Map>()
        .map((item) => TvboxVideo.fromJson(
            item.map((key, value) => MapEntry('$key', value))))
        .where((item) => item.id.isNotEmpty && item.name.isNotEmpty)
        .toList();
  }

  List<TvboxVideo> _parseXmlVideos(String body) {
    final document = XmlDocument.parse(body);
    return document
        .findAllElements('video')
        .map((node) {
          String text(String name) =>
              node.findElements(name).firstOrNull?.innerText.trim() ?? '';
          final lines = node.findAllElements('dd').toList();
          return TvboxVideo(
            id: text('id'),
            name: text('name'),
            picture: text('pic'),
            remarks: text('note'),
            content: text('des'),
            playFrom: lines
                .map((line) => line.getAttribute('flag') ?? '线路')
                .join(r'$$$'),
            playUrl: lines.map((line) => line.innerText.trim()).join(r'$$$'),
          );
        })
        .where((item) => item.id.isNotEmpty && item.name.isNotEmpty)
        .toList();
  }
}

bool _tvboxLooksHls(String url) {
  final lower = url.toLowerCase();
  return lower.contains('getm3u8') ||
      Uri.tryParse(url)?.path.toLowerCase().endsWith('.m3u8') == true;
}

class TvboxPage extends StatefulWidget {
  const TvboxPage({required this.store, super.key});

  final AppStore store;

  @override
  State<TvboxPage> createState() => _TvboxPageState();
}

class _TvboxPageState extends State<TvboxPage> {
  List<TvboxSite> sites = const [];
  TvboxSite? site;
  List<TvboxCategory> categories = const [];
  List<TvboxVideo> videos = const [];
  String? selectedTypeId;
  String? error;
  bool loading = false;

  @override
  void initState() {
    super.initState();
    if (widget.store.tvboxApiUrl.isNotEmpty) unawaited(_load());
  }

  Future<void> _resolveSites() async {
    if (sites.isNotEmpty) return;
    sites = await const TvboxResolver().resolve(widget.store.tvboxApiUrl);
    if (sites.any((value) => value.type == 3) &&
        widget.store.tvboxTrustedApiUrl != widget.store.tvboxApiUrl) {
      if (!mounted) return;
      final trusted = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          title: const Text('允许运行 Spider/JAR？'),
          content: const Text(
              '此订阅会下载并运行 Android 代码，该代码拥有与 rplayer 相同的应用权限。仅在你信任订阅来源时继续。MD5 只能校验文件完整性，不能证明代码安全。'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('取消')),
            FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('信任并继续')),
          ],
        ),
      );
      if (trusted != true) throw const FormatException('已取消运行 Spider/JAR');
      await widget.store.trustTvboxApiUrl();
    }
  }

  Future<void> _load({String? typeId}) async {
    setState(() {
      loading = true;
      error = null;
      if (typeId != null) selectedTypeId = typeId;
    });
    try {
      TvboxHome? loadedHome;
      if (site == null) {
        await _resolveSites();
        Object? lastError;
        for (final source in sites) {
          try {
            loadedHome = await TvboxClient(source).home();
            site = source;
            break;
          } catch (value) {
            lastError = value;
          }
        }
        if (site == null) {
          throw lastError ?? const FormatException('配置中没有可用站点');
        }
      } else if (categories.isEmpty || typeId == _tvboxHomeTypeId) {
        loadedHome = await TvboxClient(site!).home();
      }
      final loadedCategories = loadedHome == null
          ? categories
          : [
              const TvboxCategory(_tvboxHomeTypeId, '主页'),
              ...loadedHome.categories,
            ];
      final nextTypeId =
          typeId ?? selectedTypeId ?? loadedCategories.firstOrNull?.id;
      final loadedVideos = nextTypeId == _tvboxHomeTypeId
          ? loadedHome?.videos ?? (await TvboxClient(site!).home()).videos
          : await TvboxClient(site!).videos(typeId: nextTypeId);
      if (!mounted) return;
      setState(() {
        categories = loadedCategories;
        selectedTypeId = nextTypeId;
        videos = loadedVideos;
      });
    } catch (value) {
      if (mounted) setState(() => error = '$value');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _configure() async {
    final controller = TextEditingController(text: widget.store.tvboxApiUrl);
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('TVBox 接口'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.url,
          decoration: const InputDecoration(
            labelText: 'TVBox 订阅或 CMS 接口',
            hintText: 'https://example.com/tvbox.json',
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context), child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(context, controller.text.trim()),
              child: const Text('保存')),
        ],
      ),
    );
    controller.dispose();
    if (value == null) return;
    final uri = Uri.tryParse(value);
    if (uri == null ||
        !uri.hasAuthority ||
        (uri.scheme != 'http' && uri.scheme != 'https')) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('请输入有效的 HTTP(S) 地址')));
      }
      return;
    }
    await widget.store.setTvboxApiUrl(value);
    sites = const [];
    site = null;
    categories = const [];
    videos = const [];
    selectedTypeId = null;
    await _load();
  }

  Future<void> _search() async {
    final controller = TextEditingController();
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('搜索影视'),
        content: TextField(
          controller: controller,
          autofocus: true,
          onSubmitted: (value) => Navigator.pop(context, value),
          decoration: const InputDecoration(hintText: '输入片名'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context), child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(context, controller.text),
              child: const Text('搜索')),
        ],
      ),
    );
    controller.dispose();
    if (value?.trim().isNotEmpty == true) {
      await _openFastSearch(value!.trim());
    }
  }

  Future<void> _openFastSearch(String keyword) async {
    try {
      await _resolveSites();
      if (!mounted) return;
      await Navigator.of(context).push(appSlideRoute(
        (_) => TvboxFastSearchPage(
          store: widget.store,
          sites: sites,
          keyword: keyword,
        ),
      ));
    } catch (value) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('搜索启动失败：$value')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('TVBox'),
        centerTitle: true,
        actions: [
          if (widget.store.tvboxApiUrl.isNotEmpty)
            IconButton(
                tooltip: '搜索',
                onPressed: _search,
                icon: const Icon(Icons.search)),
          IconButton(
              tooltip: '配置接口',
              onPressed: _configure,
              icon: const Icon(Icons.settings_outlined)),
        ],
      ),
      body: widget.store.tvboxApiUrl.isEmpty
          ? EmptyState(
              icon: Icons.live_tv_outlined,
              title: '未配置 TVBox 接口',
              message: '支持 type 0/1/4；Android 还支持 Java Spider/JAR（type 3）。',
              action: FilledButton.icon(
                  onPressed: _configure,
                  icon: const Icon(Icons.add_link),
                  label: const Text('配置接口')),
            )
          : Column(
              children: [
                if (sites.length > 1)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                    child: DropdownButtonFormField<String>(
                      key: ValueKey(site?.key),
                      initialValue: site?.key,
                      decoration: const InputDecoration(
                          labelText: '站点', border: OutlineInputBorder()),
                      items: [
                        for (final item in sites)
                          DropdownMenuItem(
                              value: item.key,
                              child: Text('${item.name} · type ${item.type}')),
                      ],
                      onChanged: (value) {
                        site = sites
                            .where((item) => item.key == value)
                            .firstOrNull;
                        categories = const [];
                        videos = const [];
                        selectedTypeId = null;
                        unawaited(_load());
                      },
                    ),
                  ),
                if (categories.isNotEmpty)
                  SizedBox(
                    height: 48,
                    child: ListView.separated(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 6),
                      scrollDirection: Axis.horizontal,
                      itemCount: categories.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 6),
                      itemBuilder: (_, index) {
                        final category = categories[index];
                        return ChoiceChip(
                            label: Text(category.name),
                            selected: selectedTypeId == category.id,
                            onSelected: (_) => _load(typeId: category.id));
                      },
                    ),
                  ),
                if (loading) const LinearProgressIndicator(),
                if (error != null)
                  Expanded(
                      child: EmptyState(
                          icon: Icons.cloud_off_outlined,
                          title: '接口加载失败',
                          message: error!,
                          action: FilledButton(
                              onPressed: _load, child: const Text('重试'))))
                else if (!loading && videos.isEmpty)
                  const Expanded(
                    child: EmptyState(
                      icon: Icons.video_library_outlined,
                      title: '暂无内容',
                      message: '该分类没有返回影视内容。',
                      action: SizedBox.shrink(),
                    ),
                  )
                else
                  Expanded(
                    child: GridView.builder(
                      padding: const EdgeInsets.all(16),
                      gridDelegate:
                          const SliverGridDelegateWithMaxCrossAxisExtent(
                              maxCrossAxisExtent: 190,
                              childAspectRatio: .62,
                              crossAxisSpacing: 12,
                              mainAxisSpacing: 12),
                      itemCount: videos.length,
                      itemBuilder: (context, index) {
                        return _TvboxVideoCard(
                          video: videos[index],
                          onTap: () => _openFastSearch(videos[index].name),
                        );
                      },
                    ),
                  ),
              ],
            ),
    );
  }
}

class _TvboxVideoCard extends StatelessWidget {
  const _TvboxVideoCard(
      {required this.video, required this.onTap, this.sourceName});

  final TvboxVideo video;
  final VoidCallback onTap;
  final String? sourceName;

  @override
  Widget build(BuildContext context) {
    final request = tvboxImageRequest(video.picture);
    const missing = ColoredBox(
        color: Color(0xFFF1F3F6),
        child: Center(child: Icon(Icons.broken_image_outlined)));
    final image = request.url.isEmpty
        ? const ColoredBox(
            color: Color(0xFFF1F3F6),
            child: Center(child: Icon(Icons.movie_outlined, size: 42)))
        : FutureBuilder<Uint8List?>(
            future: _loadTvboxImage(request),
            builder: (_, snapshot) {
              final bytes = snapshot.data;
              return bytes == null || bytes.isEmpty
                  ? missing
                  : Image.memory(bytes,
                      width: double.infinity,
                      fit: BoxFit.cover,
                      gaplessPlayback: true,
                      errorBuilder: (_, __, ___) => missing);
            });
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: sourceName == null
                ? image
                : Stack(fit: StackFit.expand, children: [
                    image,
                    Align(
                      alignment: Alignment.topCenter,
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(6),
                        color: Colors.black54,
                        child: Text(
                          '$sourceName${video.remarks.isEmpty ? '' : ' · ${video.remarks}'}',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: Colors.white),
                        ),
                      ),
                    ),
                    Align(
                      alignment: Alignment.bottomCenter,
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(7),
                        color: Colors.black54,
                        child: Text(video.name,
                            maxLines: 1,
                            textAlign: TextAlign.center,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: Colors.white)),
                      ),
                    ),
                  ]),
          ),
        ),
        if (sourceName == null) ...[
          const SizedBox(height: 7),
          Text(video.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w600)),
          if (video.remarks.isNotEmpty)
            Text(video.remarks,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.grey, fontSize: 12)),
        ],
      ]),
    );
  }
}

class TvboxFastSearchPage extends StatefulWidget {
  const TvboxFastSearchPage({
    required this.store,
    required this.sites,
    required this.keyword,
    super.key,
  });

  final AppStore store;
  final List<TvboxSite> sites;
  final String keyword;

  @override
  State<TvboxFastSearchPage> createState() => _TvboxFastSearchPageState();
}

class _TvboxFastSearchPageState extends State<TvboxFastSearchPage> {
  final List<TvboxVideoSource> results = [];
  final Map<String, TvboxSite> resultSites = {};
  String? selectedSourceKey;
  int total = 0;
  int finished = 0;
  int timedOut = 0;
  bool searching = true;

  List<TvboxVideoSource> get visibleResults => selectedSourceKey == null
      ? results
      : results
          .where((result) => result.site.key == selectedSourceKey)
          .toList();

  @override
  void initState() {
    super.initState();
    unawaited(_search());
  }

  Future<void> _search() async {
    final queue = ListQueue<TvboxSite>.from(
        widget.sites.where((source) => source.searchable));
    total = queue.length;
    if (total == 0) {
      setState(() => searching = false);
      return;
    }
    await Future.wait(List.generate(
      math.min(6, total),
      (_) => _searchWorker(queue),
    ));
    if (mounted) setState(() => searching = false);
  }

  Future<void> _searchWorker(ListQueue<TvboxSite> queue) async {
    while (mounted && queue.isNotEmpty) {
      final source = queue.removeFirst();
      try {
        final videos = await TvboxClient(source)
            .videos(keyword: widget.keyword)
            .timeout(const Duration(seconds: 10));
        final matched = videos
            .where(
                (video) => tvboxSearchNameMatches(video.name, widget.keyword))
            .map((video) => (site: source, video: video))
            .toList();
        if (mounted && matched.isNotEmpty) {
          setState(() {
            results.addAll(matched);
            resultSites[source.key] = source;
          });
        }
      } on TimeoutException {
        timedOut++;
      } catch (_) {
      } finally {
        if (mounted) setState(() => finished++);
      }
    }
  }

  Future<void> _open(TvboxVideoSource result) async {
    await Navigator.of(context).push(appSlideRoute(
      (_) => TvboxDetailPage(
        store: widget.store,
        client: TvboxClient(result.site),
        video: result.video,
      ),
    ));
  }

  Widget _sourceTile(String label, String? key) {
    final selected = selectedSourceKey == key;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: selected
            ? Theme.of(context).colorScheme.primaryContainer
            : const Color(0xFFF1F3F6),
        borderRadius: BorderRadius.circular(10),
        child: ListTile(
          dense: true,
          selected: selected,
          contentPadding: const EdgeInsets.symmetric(horizontal: 10),
          title: Text(label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center),
          onTap: () => setState(() => selectedSourceKey = key),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final visible = visibleResults;
    final progress = total == 0 ? 0.0 : finished / total;
    return Scaffold(
      appBar: AppBar(title: Text(widget.keyword)),
      body: Column(
        children: [
          ListTile(
            title: Text(
                searching ? '搜索($finished/$total)' : '搜索完成 ${results.length}'),
            subtitle: Text(
                '源 $finished/$total${timedOut == 0 ? '' : ' · 超时 $timedOut'}'),
          ),
          if (searching) LinearProgressIndicator(value: progress),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  width:
                      math.min(132.0, MediaQuery.sizeOf(context).width * 0.32),
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(10, 10, 6, 10),
                    children: [
                      _sourceTile('全部显示', null),
                      for (final source in resultSites.values)
                        _sourceTile(source.name, source.key),
                    ],
                  ),
                ),
                const VerticalDivider(width: 1),
                Expanded(
                  child: visible.isEmpty
                      ? Center(child: Text(searching ? '正在搜索来源…' : '没有找到相关影片'))
                      : GridView.builder(
                          padding: const EdgeInsets.all(10),
                          gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 2,
                            childAspectRatio: .66,
                            crossAxisSpacing: 10,
                            mainAxisSpacing: 10,
                          ),
                          itemCount: visible.length,
                          itemBuilder: (context, index) {
                            final result = visible[index];
                            return _TvboxVideoCard(
                              video: result.video,
                              sourceName: result.site.name,
                              onTap: () => _open(result),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class TvboxDetailPage extends StatefulWidget {
  const TvboxDetailPage(
      {required this.store,
      required this.client,
      required this.video,
      super.key});

  final AppStore store;
  final TvboxClient client;
  final TvboxVideo video;

  @override
  State<TvboxDetailPage> createState() => _TvboxDetailPageState();
}

class _TvboxDetailPageState extends State<TvboxDetailPage> {
  late Future<TvboxVideo> detail = widget.client.detail(widget.video.id);

  Future<void> _play(
      TvboxVideo video, TvboxPlayGroup group, TvboxEpisode episode) async {
    try {
      await openTvboxPlayback(
          context, widget.store, widget.client, video, group, episode);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('播放地址解析失败：$error')));
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(widget.video.name)),
        body: FutureBuilder<TvboxVideo>(
          future: detail,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return EmptyState(
                  icon: Icons.error_outline,
                  title: '详情加载失败',
                  message: '${snapshot.error}',
                  action: FilledButton(
                      onPressed: () => setState(
                          () => detail = widget.client.detail(widget.video.id)),
                      child: const Text('重试')));
            }
            final video = snapshot.requireData;
            final groups = parseTvboxPlayGroups(video.playFrom, video.playUrl);
            return ListView(
              padding: const EdgeInsets.all(18),
              children: [
                Text(video.name,
                    style: Theme.of(context).textTheme.headlineSmall),
                if (video.remarks.isNotEmpty)
                  Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(video.remarks,
                          style: const TextStyle(color: Colors.grey))),
                if (video.content.isNotEmpty)
                  Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(
                          video.content.replaceAll(RegExp(r'<[^>]*>'), ''))),
                const SizedBox(height: 18),
                if (groups.isEmpty) const Text('接口未返回可播放地址'),
                for (final group in groups) ...[
                  Text(group.name,
                      style: const TextStyle(
                          fontSize: 17, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final episode in group.episodes)
                        OutlinedButton(
                            onPressed: () => _play(video, group, episode),
                            child: Text(episode.name)),
                    ],
                  ),
                  const SizedBox(height: 18),
                ],
              ],
            );
          },
        ),
      );
}
