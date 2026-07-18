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
    this.typeName = '',
    this.year = '',
    this.area = '',
    this.language = '',
    this.director = '',
    this.actor = '',
    this.score = '',
    this.backdrop = '',
    this.playFrom = '',
    this.playUrl = '',
    this.action = '',
  });

  factory TvboxVideo.fromJson(Map<String, dynamic> json) => TvboxVideo(
        id: '${json['vod_id'] ?? json['id'] ?? ''}',
        name: '${json['vod_name'] ?? json['name'] ?? ''}',
        picture: '${json['vod_pic'] ?? json['pic'] ?? ''}',
        remarks: '${json['vod_remarks'] ?? json['note'] ?? ''}',
        content: '${json['vod_content'] ?? json['des'] ?? ''}',
        typeName: '${json['type_name'] ?? json['vod_class'] ?? ''}',
        year: '${json['vod_year'] ?? ''}',
        area: '${json['vod_area'] ?? ''}',
        language: '${json['vod_lang'] ?? ''}',
        director: '${json['vod_director'] ?? ''}',
        actor: '${json['vod_actor'] ?? ''}',
        score: '${json['vod_score'] ?? ''}',
        backdrop: '${json['vod_pic_slide'] ?? ''}',
        playFrom: '${json['vod_play_from'] ?? ''}',
        playUrl: '${json['vod_play_url'] ?? ''}',
        action: '${json['action'] ?? ''}',
      );

  final String id;
  final String name;
  final String picture;
  final String remarks;
  final String content;
  final String typeName;
  final String year;
  final String area;
  final String language;
  final String director;
  final String actor;
  final String score;
  final String backdrop;
  final String playFrom;
  final String playUrl;
  final String action;

  Map<String, dynamic> toJson() => {
        'vod_id': id,
        'vod_name': name,
        'vod_pic': picture,
        'vod_remarks': remarks,
        'vod_content': content,
        'type_name': typeName,
        'vod_year': year,
        'vod_area': area,
        'vod_lang': language,
        'vod_director': director,
        'vod_actor': actor,
        'vod_score': score,
        'vod_pic_slide': backdrop,
        'vod_play_from': playFrom,
        'vod_play_url': playUrl,
        'action': action,
      };
}

enum TvboxVideoOpenTarget { action, search, detail }

TvboxVideoOpenTarget tvboxVideoOpenTarget(TvboxVideo video) =>
    video.action.isNotEmpty
        ? TvboxVideoOpenTarget.action
        : video.id.isEmpty || video.id.startsWith('msearch:')
            ? TvboxVideoOpenTarget.search
            : TvboxVideoOpenTarget.detail;

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

class TvboxLiveSource {
  const TvboxLiveSource({
    required this.name,
    required this.url,
    this.headers = const {},
    this.epg = '',
  });

  final String name;
  final String url;
  final Map<String, String> headers;
  final String epg;
}

class TvboxLiveChannel {
  const TvboxLiveChannel({
    required this.name,
    required this.urls,
    this.logo = '',
    this.headers = const {},
    this.epg = '',
  });

  final String name;
  final List<String> urls;
  final String logo;
  final Map<String, String> headers;
  final String epg;
}

class TvboxLiveGroup {
  const TvboxLiveGroup(this.name, this.channels);

  final String name;
  final List<TvboxLiveChannel> channels;
}

class TvboxResolvedConfig {
  const TvboxResolvedConfig(this.sites, this.lives);

  final List<TvboxSite> sites;
  final List<TvboxLiveSource> lives;
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
    if (!store.isTvboxSiteIncognito(client.site.key)) {
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
    }
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

List<TvboxLiveSource> tvboxLivesFromConfig(
        String sourceUrl, Map<String, dynamic> json) =>
    (json['lives'] as List<dynamic>? ?? const [])
        .whereType<Map>()
        .map((value) {
          final headers = {
            ..._tvboxHeaders(value['header']),
            if ('${value['ua'] ?? ''}'.trim().isNotEmpty)
              'User-Agent': '${value['ua']}'.trim(),
          };
          return TvboxLiveSource(
            name: '${value['name'] ?? '直播'}'.trim(),
            url: _tvboxConfigValue(sourceUrl, value['url']),
            headers: headers,
            epg: _tvboxConfigValue(sourceUrl, value['epg']),
          );
        })
        .where((value) => value.url.isNotEmpty)
        .toList();

List<TvboxLiveGroup> parseTvboxLiveGroups(String text) {
  final value = text.trim();
  if (value.isEmpty) return const [];
  try {
    final decoded = jsonDecode(value);
    if (decoded is List) return _parseTvboxLiveJson(decoded);
  } catch (_) {}
  return value.startsWith('#EXTM3U')
      ? _parseTvboxLiveM3u(value)
      : _parseTvboxLiveTxt(value);
}

List<TvboxLiveGroup> _parseTvboxLiveJson(List<dynamic> values) => values
    .whereType<Map>()
    .map((group) {
      final channels = (group['channels'] as List<dynamic>? ??
              group['channel'] as List<dynamic>? ??
              const [])
          .whereType<Map>()
          .map((channel) => TvboxLiveChannel(
                name: '${channel['name'] ?? '未命名频道'}'.trim(),
                urls: (channel['urls'] as List<dynamic>? ?? const [])
                    .map((url) => '$url'.trim())
                    .where(_isTvboxLiveUrl)
                    .toSet()
                    .toList(),
                logo: '${channel['logo'] ?? ''}'.trim(),
                headers: _liveHeaders(channel),
                epg: '${channel['epg'] ?? ''}'.trim(),
              ))
          .where((channel) => channel.urls.isNotEmpty)
          .toList();
      return TvboxLiveGroup(
          '${group['group'] ?? group['name'] ?? '直播'}'.trim(), channels);
    })
    .where((group) => group.channels.isNotEmpty)
    .toList();

List<TvboxLiveGroup> _parseTvboxLiveTxt(String text) {
  final groups = <String, List<TvboxLiveChannel>>{};
  var group = '直播';
  for (final raw in const LineSplitter().convert(text)) {
    final line = raw.trim();
    if (line.isEmpty || line.startsWith('#')) continue;
    if (line.contains('#genre#')) {
      group = line.split(',').first.trim();
      continue;
    }
    final separator = line.indexOf(',');
    if (separator < 1) continue;
    final urls = line
        .substring(separator + 1)
        .split('#')
        .map((url) => url.trim())
        .where(_isTvboxLiveUrl)
        .toSet()
        .toList();
    if (urls.isEmpty) continue;
    groups.putIfAbsent(group, () => []).add(TvboxLiveChannel(
        name: line.substring(0, separator).trim(), urls: urls));
  }
  return groups.entries
      .map((entry) => TvboxLiveGroup(entry.key, entry.value))
      .toList();
}

List<TvboxLiveGroup> _parseTvboxLiveM3u(String text) {
  final groups = <String, List<TvboxLiveChannel>>{};
  String? info;
  for (final raw in const LineSplitter().convert(text)) {
    final line = raw.trim();
    if (line.startsWith('#EXTINF')) {
      info = line;
      continue;
    }
    if (line.isEmpty || line.startsWith('#') || info == null) continue;
    final parsed = _splitTvboxLiveUrl(line);
    if (!_isTvboxLiveUrl(parsed.$1)) continue;
    final group = _m3uAttribute(info, 'group-title').isEmpty
        ? '直播'
        : _m3uAttribute(info, 'group-title');
    final comma = info.lastIndexOf(',');
    final name = comma < 0 ? '未命名频道' : info.substring(comma + 1).trim();
    groups.putIfAbsent(group, () => []).add(TvboxLiveChannel(
          name: name,
          urls: [parsed.$1],
          logo: _m3uAttribute(info, 'tvg-logo'),
          headers: parsed.$2,
          epg: _m3uAttribute(info, 'tvg-url'),
        ));
  }
  return groups.entries
      .map((entry) =>
          TvboxLiveGroup(entry.key, _mergeTvboxLiveChannels(entry.value)))
      .toList();
}

List<TvboxLiveChannel> _mergeTvboxLiveChannels(
    List<TvboxLiveChannel> channels) {
  final merged = <String, TvboxLiveChannel>{};
  for (final channel in channels) {
    final old = merged[channel.name];
    merged[channel.name] = old == null
        ? channel
        : TvboxLiveChannel(
            name: old.name,
            urls: {...old.urls, ...channel.urls}.toList(),
            logo: old.logo.isEmpty ? channel.logo : old.logo,
            headers: {...channel.headers, ...old.headers},
            epg: old.epg.isEmpty ? channel.epg : old.epg,
          );
  }
  return merged.values.toList();
}

Map<String, String> _liveHeaders(Map channel) => {
      ..._tvboxHeaders(channel['header']),
      if ('${channel['ua'] ?? ''}'.trim().isNotEmpty)
        'User-Agent': '${channel['ua']}'.trim(),
      if ('${channel['referer'] ?? ''}'.trim().isNotEmpty)
        'Referer': '${channel['referer']}'.trim(),
      if ('${channel['origin'] ?? ''}'.trim().isNotEmpty)
        'Origin': '${channel['origin']}'.trim(),
    };

(String, Map<String, String>) _splitTvboxLiveUrl(String value) {
  final parts = value.split('|');
  if (parts.length < 2) return (value.trim(), const {});
  final headers = <String, String>{};
  for (final item in parts.skip(1).join('|').split('&')) {
    final separator = item.indexOf('=');
    if (separator > 0) {
      headers[Uri.decodeComponent(item.substring(0, separator))] =
          Uri.decodeComponent(item.substring(separator + 1));
    }
  }
  return (parts.first.trim(), headers);
}

String _m3uAttribute(String line, String name) =>
    RegExp('$name="([^"]*)"').firstMatch(line)?.group(1)?.trim() ?? '';

bool _isTvboxLiveUrl(String value) =>
    RegExp(r'^(?:https?|rtmp|rtsp|udp|rtp)://', caseSensitive: false)
        .hasMatch(value);

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
    final result = await resolveConfig(sourceUrl, depth: depth);
    if (result.sites.isEmpty) throw const FormatException('配置中没有点播站点');
    return result.sites;
  }

  Future<TvboxResolvedConfig> resolveConfig(String sourceUrl,
      {int depth = 0}) async {
    if (depth > 3) throw const FormatException('TVBox 多仓嵌套过深');
    sourceUrl = normalizeTvboxSourceUrl(sourceUrl);
    final response = await http.get(Uri.parse(sourceUrl),
        headers: const {'accept': '*/*'}).timeout(const Duration(seconds: 20));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException('订阅返回 HTTP ${response.statusCode}');
    }
    final text = decodeTvboxConfigBytes(response.bodyBytes);
    if (text.startsWith('<rss')) {
      return TvboxResolvedConfig(
          [TvboxSite(key: 'direct', name: '当前接口', type: 0, apiUrl: sourceUrl)],
          const []);
    }
    final value = jsonDecode(text);
    if (value is! Map<String, dynamic>) {
      throw const FormatException('订阅不是 JSON 对象');
    }
    if (value['urls'] case final List<dynamic> urls) {
      final first = urls.whereType<Map>().firstOrNull;
      final nested = first?['url'];
      if (nested == null) throw const FormatException('多仓订阅中没有有效地址');
      return resolveConfig(_tvboxConfigValue(sourceUrl, nested),
          depth: depth + 1);
    }
    final lives = tvboxLivesFromConfig(sourceUrl, value);
    try {
      return TvboxResolvedConfig(tvboxSitesFromConfig(sourceUrl, value), lives);
    } on FormatException {
      if (lives.isNotEmpty) return TvboxResolvedConfig(const [], lives);
      rethrow;
    }
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
      return (categories: categories, videos: parseVideos(body));
    }
    if (site.type == 3) {
      return (categories: categories, videos: parseVideos(body));
    }
    final fallback =
        await _get({'ac': site.type == 0 ? 'videolist' : 'detail'});
    return (
      categories: _parseCategories(fallback),
      videos: parseVideos(fallback),
    );
  }

  Future<List<TvboxVideo>> videos({String? typeId, String? keyword}) async {
    if (site.type == 3) {
      return parseVideos(await _spider(
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
    return parseVideos(await _get(query));
  }

  Future<TvboxVideo> detail(String id) async {
    final body = site.type == 3
        ? await _spider('detail', {'id': id})
        : await _get({
            'ac': site.type == 0 ? 'videolist' : 'detail',
            'ids': id,
          });
    final values = parseVideos(body);
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
    final danmaku = '${value['danmaku'] ?? ''}'.trim();
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
      danmaku: danmaku.isEmpty ? null : danmaku,
    );
  }

  Future<String?> action(String value) async {
    final body = await _spider('action', {'value': value});
    final result = jsonDecode(body);
    if (result is! Map) return null;
    final message = '${result['msg'] ?? ''}'.trim();
    return message.isEmpty ? null : message;
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

  List<TvboxVideo> parseVideos(String body) {
    if (body.startsWith('<')) return _parseXmlVideos(body);
    final value = jsonDecode(body);
    if (value is! Map) return const [];
    return (value['list'] as List<dynamic>? ?? const [])
        .whereType<Map>()
        .map((item) => TvboxVideo.fromJson(
            item.map((key, value) => MapEntry('$key', value))))
        .where((item) =>
            (item.id.isNotEmpty || item.action.isNotEmpty) &&
            item.name.isNotEmpty)
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
            typeName: text('type'),
            year: text('year'),
            area: text('area'),
            language: text('lang'),
            director: text('director'),
            actor: text('actor'),
            score: text('score'),
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
  List<TvboxLiveSource> liveSources = const [];
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
    if (sites.isNotEmpty || liveSources.isNotEmpty) return;
    final config =
        await const TvboxResolver().resolveConfig(widget.store.tvboxApiUrl);
    sites = config.sites;
    liveSources = config.lives;
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
        if (sites.isEmpty && liveSources.isNotEmpty) {
          if (mounted) {
            setState(() {
              categories = const [];
              videos = const [];
            });
          }
          return;
        }
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
    liveSources = const [];
    site = null;
    categories = const [];
    videos = const [];
    selectedTypeId = null;
    await _load();
  }

  Future<void> _toggleIncognito(TvboxSite selected) async {
    final enabled = await widget.store.toggleTvboxSiteIncognito(selected.key);
    if (!mounted) return;
    setState(() {});
    showSnack(context, '${selected.name}：${enabled ? '已开启无痕' : '已关闭无痕'}');
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

  Future<void> _openLive() async {
    try {
      await _resolveSites();
      if (!mounted) return;
      if (liveSources.isEmpty) throw const FormatException('配置中没有直播源');
      await Navigator.of(context).push(appSlideRoute(
        (_) => TvboxLivePage(store: widget.store, sources: liveSources),
      ));
    } catch (value) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('直播加载失败：$value')));
      }
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

  Future<void> _openVideo(TvboxVideo video) async {
    final source = site;
    if (source == null) return;
    final target = tvboxVideoOpenTarget(video);
    if (target == TvboxVideoOpenTarget.action) {
      try {
        final message = await TvboxClient(source).action(video.action);
        if (!mounted) return;
        if (message != null) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(message)));
        }
        await _load(typeId: selectedTypeId);
      } catch (value) {
        if (mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text('操作失败：$value')));
        }
      }
      return;
    }
    if (target == TvboxVideoOpenTarget.search) {
      await _openFastSearch(video.name);
      return;
    }
    await Navigator.of(context).push(appSlideRoute(
      (_) => TvboxDetailPage(
        store: widget.store,
        client: TvboxClient(source),
        video: video,
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 16,
        title: sites.isEmpty
            ? null
            : DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  key: ValueKey(site?.key),
                  value: site?.key,
                  isExpanded: true,
                  icon: const Icon(Icons.arrow_drop_down),
                  items: [
                    for (final item in sites)
                      DropdownMenuItem(
                        value: item.key,
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onLongPress: () {
                            if (ModalRoute.of(context)?.isCurrent == false) {
                              Navigator.of(context).pop();
                            }
                            unawaited(_toggleIncognito(item));
                          },
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  '${item.name} · type ${item.type}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.normal),
                                ),
                              ),
                              if (widget.store.isTvboxSiteIncognito(item.key))
                                const Padding(
                                  padding: EdgeInsets.only(left: 8),
                                  child: Icon(Icons.visibility_off_outlined,
                                      size: 18),
                                ),
                            ],
                          ),
                        ),
                      ),
                  ],
                  onChanged: (value) {
                    site = sites.where((item) => item.key == value).firstOrNull;
                    categories = const [];
                    videos = const [];
                    selectedTypeId = null;
                    unawaited(_load());
                  },
                ),
              ),
        centerTitle: false,
        actions: [
          if (widget.store.tvboxApiUrl.isNotEmpty)
            IconButton(
                tooltip: '直播',
                onPressed: _openLive,
                icon: const Icon(Icons.live_tv_outlined)),
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
                          const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 3,
                              childAspectRatio: .58,
                              crossAxisSpacing: 10,
                              mainAxisSpacing: 10),
                      itemCount: videos.length,
                      itemBuilder: (context, index) {
                        return _TvboxVideoCard(
                          video: videos[index],
                          onTap: () => _openVideo(videos[index]),
                        );
                      },
                    ),
                  ),
              ],
            ),
    );
  }
}

class TvboxLivePage extends StatefulWidget {
  const TvboxLivePage({required this.store, required this.sources, super.key});

  final AppStore store;
  final List<TvboxLiveSource> sources;

  @override
  State<TvboxLivePage> createState() => _TvboxLivePageState();
}

class _TvboxLivePageState extends State<TvboxLivePage> {
  late TvboxLiveSource source = widget.sources.first;
  List<TvboxLiveGroup> groups = const [];
  int groupIndex = 0;
  String? error;
  bool loading = true;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final response = await http
          .get(Uri.parse(source.url), headers: source.headers)
          .timeout(const Duration(seconds: 20));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException('直播源返回 HTTP ${response.statusCode}');
      }
      final parsed = parseTvboxLiveGroups(
          utf8.decode(response.bodyBytes, allowMalformed: true));
      if (parsed.isEmpty) throw const FormatException('直播源中没有可用频道');
      if (!mounted) return;
      setState(() {
        groups = parsed;
        groupIndex = 0;
      });
    } catch (value) {
      if (mounted) setState(() => error = '$value');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _open(TvboxLiveChannel selected) async {
    final group = groups[groupIndex];
    final selectedUrls = <String, String>{};
    if (selected.urls.length > 1) {
      final chosen = await showDialog<String>(
        context: context,
        builder: (context) => SimpleDialog(
          title: Text('${selected.name} · 选择线路'),
          children: [
            for (final entry in selected.urls.indexed)
              SimpleDialogOption(
                onPressed: () => Navigator.pop(context, entry.$2),
                child: Text('线路 ${entry.$1 + 1}'),
              ),
          ],
        ),
      );
      if (chosen == null) return;
      selectedUrls[selected.name] = chosen;
    }
    final items = [
      for (final channel in group.channels)
        MediaItem(
          id: 'tvbox-live:${source.name}:${group.name}:${channel.name}',
          sourceId: 'tvbox',
          sourceName: source.name,
          type: SourceType.local,
          title: channel.name,
          uri: channel.urls.first,
          folderTitle: group.name,
          groupPath: 'live/${source.name}/${group.name}',
        ),
    ];
    final current =
        items.where((item) => item.title == selected.name).firstOrNull;
    if (current == null || !mounted) return;

    Future<RemotePlayback> resolve(MediaItem item) async {
      final channel =
          group.channels.where((value) => value.name == item.title).first;
      final raw = selectedUrls[channel.name] ?? channel.urls.first;
      final parsed = _splitTvboxLiveUrl(raw);
      return RemotePlayback(
        parsed.$1,
        {...source.headers, ...channel.headers, ...parsed.$2},
        mimeType: _tvboxLooksHls(parsed.$1) ? 'application/x-mpegURL' : null,
      );
    }

    final playback = await resolve(current);
    if (!mounted) return;
    openPlayer(context, widget.store, current,
        playback: playback, episodes: items, playbackResolver: resolve);
  }

  @override
  Widget build(BuildContext context) {
    final channels = groups.isEmpty
        ? const <TvboxLiveChannel>[]
        : groups[groupIndex].channels;
    return Scaffold(
      appBar: AppBar(
        title: const Text('TVBox 直播'),
        actions: [
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: Column(
        children: [
          if (widget.sources.length > 1)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: DropdownButtonFormField<TvboxLiveSource>(
                initialValue: source,
                decoration: const InputDecoration(
                    labelText: '直播源', border: OutlineInputBorder()),
                items: [
                  for (final item in widget.sources)
                    DropdownMenuItem(value: item, child: Text(item.name)),
                ],
                onChanged: (value) {
                  if (value == null) return;
                  source = value;
                  unawaited(_load());
                },
              ),
            ),
          if (groups.isNotEmpty)
            SizedBox(
              height: 48,
              child: ListView.separated(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                scrollDirection: Axis.horizontal,
                itemCount: groups.length,
                separatorBuilder: (_, __) => const SizedBox(width: 6),
                itemBuilder: (_, index) => ChoiceChip(
                  label: Text(groups[index].name),
                  selected: groupIndex == index,
                  onSelected: (_) => setState(() => groupIndex = index),
                ),
              ),
            ),
          if (loading) const LinearProgressIndicator(),
          Expanded(
            child: error != null
                ? EmptyState(
                    icon: Icons.cloud_off_outlined,
                    title: '直播源加载失败',
                    message: error!,
                    action:
                        FilledButton(onPressed: _load, child: const Text('重试')),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.all(12),
                    itemCount: channels.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (_, index) {
                      final channel = channels[index];
                      return ListTile(
                        leading: const Icon(Icons.live_tv_outlined),
                        title: Text(channel.name),
                        subtitle: channel.urls.length > 1
                            ? Text('${channel.urls.length} 条线路')
                            : null,
                        trailing: const Icon(Icons.play_arrow),
                        onTap: () => _open(channel),
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
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.normal),
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
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.normal)),
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
              style:
                  const TextStyle(fontSize: 13, fontWeight: FontWeight.normal)),
          if (video.remarks.isNotEmpty)
            Text(video.remarks,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    color: Colors.grey,
                    fontSize: 11,
                    fontWeight: FontWeight.normal)),
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
          contentPadding: const EdgeInsets.symmetric(horizontal: 4),
          title: Text(label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style:
                  const TextStyle(fontSize: 11, fontWeight: FontWeight.normal)),
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
      appBar: AppBar(
          title: Text(widget.keyword,
              style: const TextStyle(
                  fontSize: 18, fontWeight: FontWeight.normal))),
      body: Column(
        children: [
          ListTile(
            dense: true,
            title: Text(
                searching ? '搜索($finished/$total)' : '搜索完成 ${results.length}',
                style: const TextStyle(
                    fontSize: 15, fontWeight: FontWeight.normal)),
            subtitle: Text(
                '源 $finished/$total${timedOut == 0 ? '' : ' · 超时 $timedOut'}',
                style: const TextStyle(
                    fontSize: 12, fontWeight: FontWeight.normal)),
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
                    padding: const EdgeInsets.fromLTRB(6, 10, 4, 10),
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
  String? selectedGroupName;

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

  Widget _image(String value, {BoxFit fit = BoxFit.cover}) {
    final request = tvboxImageRequest(value);
    if (request.url.isEmpty) {
      return const ColoredBox(
        color: Color(0xFF252A22),
        child: Center(
          child: Icon(Icons.movie_creation_outlined, color: Colors.white70),
        ),
      );
    }
    return FutureBuilder<Uint8List?>(
      future: _loadTvboxImage(request),
      builder: (_, snapshot) {
        final bytes = snapshot.data;
        if (bytes == null || bytes.isEmpty) {
          return const ColoredBox(color: Color(0xFF252A22));
        }
        return Image.memory(bytes,
            fit: fit,
            gaplessPlayback: true,
            errorBuilder: (_, __, ___) =>
                const ColoredBox(color: Color(0xFF252A22)));
      },
    );
  }

  TvboxRecentEntry? _recent(TvboxVideo video, TvboxPlayGroup group) =>
      widget.store.tvboxRecent
          .where((entry) =>
              entry.site.key == widget.client.site.key &&
              entry.video.id == video.id &&
              entry.groupName == group.name)
          .firstOrNull;

  @override
  Widget build(BuildContext context) => FutureBuilder<TvboxVideo>(
        future: detail,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Scaffold(
              backgroundColor: Color(0xFF090B08),
              body: Center(child: CircularProgressIndicator()),
            );
          }
          if (snapshot.hasError) {
            return Scaffold(
              appBar: AppBar(),
              body: EmptyState(
                icon: Icons.error_outline,
                title: '详情加载失败',
                message: '${snapshot.error}',
                action: FilledButton(
                  onPressed: () => setState(
                      () => detail = widget.client.detail(widget.video.id)),
                  child: const Text('重试'),
                ),
              ),
            );
          }

          final video = snapshot.requireData;
          final groups = parseTvboxPlayGroups(video.playFrom, video.playUrl);
          final recentGroup = widget.store.tvboxRecent
              .where((entry) =>
                  entry.site.key == widget.client.site.key &&
                  entry.video.id == video.id)
              .firstOrNull
              ?.groupName;
          final selectedGroup = groups
                  .where((group) =>
                      group.name == (selectedGroupName ?? recentGroup))
                  .firstOrNull ??
              groups.firstOrNull;
          final recent =
              selectedGroup == null ? null : _recent(video, selectedGroup);
          final currentEpisode = selectedGroup?.episodes
                  .where((episode) => episode.url == recent?.episodeUrl)
                  .firstOrNull ??
              selectedGroup?.episodes.firstOrNull;
          final currentItem = selectedGroup == null || currentEpisode == null
              ? null
              : tvboxMediaItem(
                  widget.client.site,
                  video,
                  selectedGroup.name,
                  currentEpisode,
                  selectedGroup.episodes.indexOf(currentEpisode),
                );
          final progress = currentItem == null
              ? 0
              : widget.store.progress[currentItem.id] ?? 0;
          final overview = video.content
              .replaceAll(RegExp(r'<[^>]*>'), '')
              .replaceAll('&nbsp;', ' ')
              .trim();
          final actors = video.actor
              .split(RegExp(r'[,，/、]+'))
              .map((value) => value.trim())
              .where((value) => value.isNotEmpty)
              .toList();
          final info = [video.typeName, video.area, video.language]
              .where((value) => value.trim().isNotEmpty)
              .join('  ');
          final score = double.tryParse(video.score);

          return Scaffold(
            backgroundColor: const Color(0xFF090B08),
            body: CustomScrollView(
              slivers: [
                SliverToBoxAdapter(
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: _image(video.backdrop.isEmpty
                            ? video.picture
                            : video.backdrop),
                      ),
                      Positioned.fill(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Colors.black.withValues(alpha: 0.34),
                                const Color(0xFF090B08).withValues(alpha: 0.78),
                                const Color(0xFF090B08),
                              ],
                              stops: const [0, 0.58, 1],
                            ),
                          ),
                        ),
                      ),
                      SafeArea(
                        bottom: false,
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(22, 8, 22, 34),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  IconButton(
                                    color: Colors.white,
                                    onPressed: () =>
                                        Navigator.of(context).maybePop(),
                                    icon: const Icon(Icons.chevron_left,
                                        size: 32),
                                  ),
                                  Expanded(
                                    child: Text(
                                      video.name,
                                      textAlign: TextAlign.center,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 21,
                                        fontWeight: FontWeight.normal,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 48),
                                ],
                              ),
                              const SizedBox(height: 128),
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(8),
                                    child: SizedBox(
                                      width: 82,
                                      height: 123,
                                      child: _image(video.picture),
                                    ),
                                  ),
                                  const SizedBox(width: 14),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Wrap(
                                          spacing: 10,
                                          runSpacing: 8,
                                          children: [
                                            if ((score ?? 0) > 0)
                                              _DarkMetaChip(
                                                icon: Icons.local_movies,
                                                label:
                                                    score!.toStringAsFixed(1),
                                                accent: const Color(0xFF60D264),
                                              ),
                                            if (video.year.isNotEmpty)
                                              _DarkMetaChip(
                                                icon: Icons
                                                    .calendar_month_outlined,
                                                label: video.year,
                                              ),
                                            if (video.remarks.isNotEmpty)
                                              _DarkTextChip(
                                                  label: video.remarks),
                                          ],
                                        ),
                                        if (info.isNotEmpty) ...[
                                          const SizedBox(height: 12),
                                          Text(
                                            info,
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              color: Color(0xDDFFFFFF),
                                              fontSize: 15,
                                              fontWeight: FontWeight.normal,
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(28, 0, 28, 34),
                  sliver: SliverList(
                    delegate: SliverChildListDelegate([
                      SizedBox(
                        height: 46,
                        child: FilledButton.icon(
                          style: FilledButton.styleFrom(
                            backgroundColor: Colors.white,
                            foregroundColor: Colors.black,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(6)),
                          ),
                          onPressed: selectedGroup == null ||
                                  currentEpisode == null
                              ? null
                              : () =>
                                  _play(video, selectedGroup, currentEpisode),
                          icon: const Icon(Icons.play_arrow, size: 22),
                          label: Text(
                            currentEpisode == null
                                ? '接口未返回可播放地址'
                                : progress <= 0
                                    ? '播放 ${currentEpisode.name}'
                                    : '继续播放 ${currentEpisode.name} ${formatDuration(Duration(milliseconds: progress))}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.normal,
                            ),
                          ),
                        ),
                      ),
                      if (selectedGroup != null) ...[
                        const SizedBox(height: 34),
                        Row(
                          children: [
                            const Text(
                              '版本',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.normal,
                              ),
                            ),
                            const SizedBox(width: 14),
                            PopupMenuButton<String>(
                              tooltip: '切换版本',
                              color: Colors.white,
                              initialValue: selectedGroup.name,
                              onSelected: (value) =>
                                  setState(() => selectedGroupName = value),
                              itemBuilder: (_) => [
                                for (final group in groups)
                                  PopupMenuItem(
                                    value: group.name,
                                    child: Text(group.name),
                                  ),
                              ],
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Flexible(
                                    child: Text(
                                      selectedGroup.name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 16,
                                        fontWeight: FontWeight.normal,
                                      ),
                                    ),
                                  ),
                                  const Icon(Icons.arrow_drop_down,
                                      color: Colors.white),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        const Divider(
                          height: 1,
                          thickness: 1,
                          color: Color(0x44FFFFFF),
                        ),
                        const SizedBox(height: 20),
                        SizedBox(
                          height: 154,
                          child: ListView.separated(
                            scrollDirection: Axis.horizontal,
                            itemCount: selectedGroup.episodes.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(width: 12),
                            itemBuilder: (context, index) {
                              final episode = selectedGroup.episodes[index];
                              final item = tvboxMediaItem(widget.client.site,
                                  video, selectedGroup.name, episode, index);
                              final position =
                                  widget.store.progress[item.id] ?? 0;
                              final duration =
                                  widget.store.durations[item.id] ?? 0;
                              final progressValue = position <= 0
                                  ? 0.0
                                  : duration <= 0
                                      ? 0.06
                                      : (position / duration).clamp(0.0, 1.0);
                              return SizedBox(
                                width: 176,
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(8),
                                  onTap: () =>
                                      _play(video, selectedGroup, episode),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      ClipRRect(
                                        borderRadius: BorderRadius.circular(8),
                                        child: AspectRatio(
                                          aspectRatio: 16 / 9,
                                          child: Stack(
                                            fit: StackFit.expand,
                                            children: [
                                              _image(video.picture),
                                              const Center(
                                                child: CircleAvatar(
                                                  radius: 15,
                                                  backgroundColor:
                                                      Color(0xAA000000),
                                                  child: Icon(Icons.play_arrow,
                                                      color: Colors.white,
                                                      size: 20),
                                                ),
                                              ),
                                              Positioned(
                                                left: 0,
                                                right: 0,
                                                bottom: 0,
                                                child: LinearProgressIndicator(
                                                  minHeight: 3,
                                                  value: progressValue,
                                                  backgroundColor:
                                                      const Color(0x66FFFFFF),
                                                  color:
                                                      const Color(0xFF2E7AF6),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                      const SizedBox(height: 7),
                                      Text(
                                        '${index + 1}. ${episode.name}',
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 12,
                                          fontWeight: FontWeight.normal,
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
                      if (overview.isNotEmpty) ...[
                        const SizedBox(height: 28),
                        const _DarkSectionHeader(title: '剧情简介'),
                        const SizedBox(height: 12),
                        Text(
                          overview,
                          style: const TextStyle(
                            color: Color(0xDDFFFFFF),
                            height: 1.65,
                            fontSize: 15,
                            fontWeight: FontWeight.normal,
                          ),
                        ),
                      ],
                      if (video.director.isNotEmpty) ...[
                        const SizedBox(height: 24),
                        Text(
                          '导演：${video.director}',
                          style: const TextStyle(
                            color: Color(0xDDFFFFFF),
                            fontSize: 14,
                            fontWeight: FontWeight.normal,
                          ),
                        ),
                      ],
                      if (actors.isNotEmpty) ...[
                        const SizedBox(height: 30),
                        const _DarkSectionHeader(title: '相关演员'),
                        const SizedBox(height: 16),
                        SizedBox(
                          height: 130,
                          child: ListView.separated(
                            scrollDirection: Axis.horizontal,
                            itemCount: math.min(actors.length, 10),
                            separatorBuilder: (_, __) =>
                                const SizedBox(width: 18),
                            itemBuilder: (_, index) => _ActorAvatar(
                              store: widget.store,
                              name: actors[index],
                              imagePath: null,
                            ),
                          ),
                        ),
                      ],
                    ]),
                  ),
                ),
              ],
            ),
          );
        },
      );
}
