part of 'package:player_flutter/main.dart';

enum SourceType { local, webdav }

class MediaSourceConfig {
  const MediaSourceConfig({
    required this.id,
    required this.name,
    required this.type,
    required this.directory,
    this.baseUrl = '',
    this.username = '',
    this.password = '',
    this.selectedPaths = const [],
  });

  factory MediaSourceConfig.local(
      {required String id, required String name, required String directory}) {
    return MediaSourceConfig(
        id: id, name: name, type: SourceType.local, directory: directory);
  }

  factory MediaSourceConfig.webdav({
    required String id,
    required String name,
    required String baseUrl,
    required String username,
    required String password,
    required String directory,
    List<String> selectedPaths = const [],
  }) {
    return MediaSourceConfig(
      id: id,
      name: name,
      type: SourceType.webdav,
      baseUrl: baseUrl,
      username: username,
      password: password,
      directory: directory,
      selectedPaths: selectedPaths,
    );
  }

  final String id;
  final String name;
  final SourceType type;
  final String directory;
  final String baseUrl;
  final String username;
  final String password;
  final List<String> selectedPaths;

  String get displayPath =>
      type == SourceType.local ? directory : '$baseUrl$directory';

  Map<String, String> get headers {
    if (username.isEmpty && password.isEmpty) return {};
    return {
      'Authorization':
          'Basic ${base64Encode(utf8.encode('$username:$password'))}'
    };
  }

  Uri resolve(String remotePath) {
    final base = baseUrl.endsWith('/') ? baseUrl : '$baseUrl/';
    final relative =
        remotePath.startsWith('/') ? remotePath.substring(1) : remotePath;
    return Uri.parse(base)
        .resolve(relative.split('/').map(Uri.encodeComponent).join('/'));
  }

  MediaSourceConfig copyWith({
    String? id,
    String? name,
    SourceType? type,
    String? directory,
    String? baseUrl,
    String? username,
    String? password,
    List<String>? selectedPaths,
  }) {
    return MediaSourceConfig(
      id: id ?? this.id,
      name: name ?? this.name,
      type: type ?? this.type,
      directory: directory ?? this.directory,
      baseUrl: baseUrl ?? this.baseUrl,
      username: username ?? this.username,
      password: password ?? this.password,
      selectedPaths: selectedPaths ?? this.selectedPaths,
    );
  }

  factory MediaSourceConfig.fromJson(Map<String, dynamic> json) =>
      MediaSourceConfig(
        id: json['id'] as String,
        name: json['name'] as String,
        type: (json['type'] as String) == 'webdav'
            ? SourceType.webdav
            : SourceType.local,
        directory: json['directory'] as String,
        baseUrl: json['baseUrl'] as String? ?? '',
        username: json['username'] as String? ?? '',
        password: json['password'] as String? ?? '',
        selectedPaths: (json['selectedPaths'] as List<dynamic>? ?? const [])
            .whereType<String>()
            .toList(),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'type': type == SourceType.webdav ? 'webdav' : 'local',
        'directory': directory,
        'baseUrl': baseUrl,
        'username': username,
        'password': password,
        'selectedPaths': selectedPaths,
      };
}

class MediaItem {
  const MediaItem({
    required this.id,
    required this.sourceId,
    required this.sourceName,
    required this.type,
    required this.title,
    required this.uri,
    this.folderTitle = '',
    this.matchTitle = '',
    this.matchYear,
    this.season,
    this.episode,
    this.mediaKind = 'Unknown',
    this.size,
  });

  factory MediaItem.local(
      {required MediaSourceConfig source, required String path, int? size}) {
    final title = p.basenameWithoutExtension(path);
    final folderTitle = mediaSeriesTitleFromLocalPath(path);
    final identity = RustCoreService.instance.tryParseMediaIdentity(
      folderTitle,
      p.basename(path),
    );
    return MediaItem(
      id: '${source.id}:$path',
      sourceId: source.id,
      sourceName: source.name,
      type: SourceType.local,
      title: title,
      uri: path,
      folderTitle: folderTitle,
      matchTitle: identity?.normalizedTitle ?? title,
      matchYear: identity?.year,
      season: identity?.season,
      episode: identity?.episode,
      mediaKind: identity?.kind ?? 'Unknown',
      size: size,
    );
  }

  factory MediaItem.webdav(
      {required MediaSourceConfig source, required WebdavEntry entry}) {
    final title = p.basenameWithoutExtension(entry.name);
    final folderTitle = mediaSeriesTitleFromRemotePath(entry.path);
    final identity = RustCoreService.instance.tryParseMediaIdentity(
      folderTitle,
      entry.name,
    );
    return MediaItem(
      id: '${source.id}:${entry.path}',
      sourceId: source.id,
      sourceName: source.name,
      type: SourceType.webdav,
      title: title,
      uri: entry.url,
      folderTitle: folderTitle,
      matchTitle: identity?.normalizedTitle ?? title,
      matchYear: identity?.year,
      season: identity?.season,
      episode: identity?.episode,
      mediaKind: identity?.kind ?? 'Unknown',
      size: entry.size,
    );
  }

  final String id;
  final String sourceId;
  final String sourceName;
  final SourceType type;
  final String title;
  final String uri;
  final String folderTitle;
  final String matchTitle;
  final int? matchYear;
  final int? season;
  final int? episode;
  final String mediaKind;
  final int? size;

  MediaItem copyWith({
    String? id,
    String? sourceId,
    String? sourceName,
    SourceType? type,
    String? title,
    String? uri,
    String? folderTitle,
    String? matchTitle,
    int? matchYear,
    int? season,
    int? episode,
    String? mediaKind,
    int? size,
  }) {
    return MediaItem(
      id: id ?? this.id,
      sourceId: sourceId ?? this.sourceId,
      sourceName: sourceName ?? this.sourceName,
      type: type ?? this.type,
      title: title ?? this.title,
      uri: uri ?? this.uri,
      folderTitle: folderTitle ?? this.folderTitle,
      matchTitle: matchTitle ?? this.matchTitle,
      matchYear: matchYear ?? this.matchYear,
      season: season ?? this.season,
      episode: episode ?? this.episode,
      mediaKind: mediaKind ?? this.mediaKind,
      size: size ?? this.size,
    );
  }

  MediaItem withFreshIdentity() {
    final folder = mediaFolderTitle(this);
    final fileName = mediaIdentityFileName(this);
    final identity = RustCoreService.instance.tryParseMediaIdentity(
      folder,
      fileName,
    );
    if (identity == null) return this;
    return MediaItem(
      id: id,
      sourceId: sourceId,
      sourceName: sourceName,
      type: type,
      title: title,
      uri: uri,
      folderTitle: folder.isEmpty ? folderTitle : folder,
      matchTitle: identity.normalizedTitle.isEmpty
          ? matchTitle
          : identity.normalizedTitle,
      matchYear: identity.year,
      season: identity.season,
      episode: identity.episode,
      mediaKind: identity.kind,
      size: size,
    );
  }

  factory MediaItem.fromJson(Map<String, dynamic> json) => MediaItem(
        id: json['id'] as String,
        sourceId: json['sourceId'] as String,
        sourceName: json['sourceName'] as String,
        type: (json['type'] as String) == 'webdav'
            ? SourceType.webdav
            : SourceType.local,
        title: json['title'] as String,
        uri: json['uri'] as String,
        folderTitle: json['folderTitle'] as String? ?? '',
        matchTitle: json['matchTitle'] as String? ?? json['title'] as String,
        matchYear: (json['matchYear'] as num?)?.toInt(),
        season: (json['season'] as num?)?.toInt(),
        episode: (json['episode'] as num?)?.toInt(),
        mediaKind: json['mediaKind'] as String? ?? 'Unknown',
        size: (json['size'] as num?)?.toInt(),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'sourceId': sourceId,
        'sourceName': sourceName,
        'type': type == SourceType.webdav ? 'webdav' : 'local',
        'title': title,
        'uri': uri,
        'folderTitle': folderTitle,
        'matchTitle': matchTitle,
        'matchYear': matchYear,
        'season': season,
        'episode': episode,
        'mediaKind': mediaKind,
        'size': size,
      };
}

class MediaFolderGroup {
  const MediaFolderGroup({
    required this.key,
    required this.title,
    required this.items,
    required this.representative,
    required this.latestPlayedAt,
  });

  final String key;
  final String title;
  final List<MediaItem> items;
  final MediaItem representative;
  final int latestPlayedAt;
}

class TmdbApiEndpoint {
  const TmdbApiEndpoint({
    required this.label,
    required this.url,
    this.custom = false,
  });

  final String label;
  final String url;
  final bool custom;
}

const defaultTmdbApiBaseUrl = 'https://api.tmdb.org/3';
const tmdbProxyEndpointValue = 'custom:tmdb-proxy';

const tmdbApiEndpoints = [
  TmdbApiEndpoint(label: 'api.tmdb.org', url: defaultTmdbApiBaseUrl),
  TmdbApiEndpoint(
    label: 'api.themoviedb.org',
    url: 'https://api.themoviedb.org/3',
  ),
  TmdbApiEndpoint(
    label: '自建 tmdb-proxy',
    url: tmdbProxyEndpointValue,
    custom: true,
  ),
];

String normalizeTmdbApiBaseUrl(String value) {
  final trimmed = value.trim();
  var normalized = trimmed.endsWith('/')
      ? trimmed.substring(0, trimmed.length - 1)
      : trimmed;
  if (normalized.isEmpty) return defaultTmdbApiBaseUrl;
  if (!normalized.startsWith('http://') && !normalized.startsWith('https://')) {
    normalized = 'https://$normalized';
  }
  final official = tmdbApiEndpoints
      .where((endpoint) => !endpoint.custom)
      .map((endpoint) => endpoint.url)
      .contains(normalized);
  if (official) return normalized;
  final uri = Uri.tryParse(normalized);
  if (uri == null || uri.host.isEmpty) return defaultTmdbApiBaseUrl;
  final path = uri.path.endsWith('/')
      ? uri.path.substring(0, uri.path.length - 1)
      : uri.path;
  if (path.isEmpty) {
    return _tmdbUriWithPath(uri, '/3');
  }
  return _tmdbUriWithPath(uri, path);
}

bool isOfficialTmdbApiBaseUrl(String value) {
  final normalized = normalizeTmdbApiBaseUrl(value);
  return tmdbApiEndpoints
      .where((endpoint) => !endpoint.custom)
      .any((endpoint) => endpoint.url == normalized);
}

String selectedTmdbEndpointValue(String value) {
  final normalized = normalizeTmdbApiBaseUrl(value);
  return isOfficialTmdbApiBaseUrl(normalized)
      ? normalized
      : tmdbProxyEndpointValue;
}

String tmdbProxyDisplayBaseUrl(String value) {
  final normalized = normalizeTmdbApiBaseUrl(value);
  if (isOfficialTmdbApiBaseUrl(normalized)) return '';
  return normalized.endsWith('/3')
      ? normalized.substring(0, normalized.length - 2)
      : normalized;
}

String tmdbImageBaseUrlForApiBaseUrl(String value) {
  final normalized = normalizeTmdbApiBaseUrl(value);
  if (isOfficialTmdbApiBaseUrl(normalized)) {
    return 'https://image.tmdb.org/t/p';
  }
  final uri = Uri.parse(normalized);
  return _tmdbUriWithPath(uri, '/t/p');
}

String _tmdbUriWithPath(Uri uri, String path) {
  return Uri(
    scheme: uri.scheme,
    userInfo: uri.userInfo,
    host: uri.host,
    port: uri.hasPort ? uri.port : null,
    path: path,
  ).toString();
}

String tmdbEndpointLabel(String value) {
  final selected = selectedTmdbEndpointValue(value);
  return tmdbApiEndpoints
      .firstWhere((endpoint) => endpoint.url == selected)
      .label;
}

String tmdbEndpointHost(String value) {
  final normalized = normalizeTmdbApiBaseUrl(value);
  return Uri.parse(normalized).host;
}

String selectedTmdbApiBaseUrl(String value) {
  final normalized = normalizeTmdbApiBaseUrl(value);
  return normalized;
}

class TmdbConfig {
  const TmdbConfig({
    this.accessToken = '',
    this.language = 'zh-CN',
    this.region = 'CN',
    this.apiBaseUrl = defaultTmdbApiBaseUrl,
  });

  final String accessToken;
  final String language;
  final String region;
  final String apiBaseUrl;

  bool get enabled => accessToken.trim().isNotEmpty;
  String get normalizedApiBaseUrl => normalizeTmdbApiBaseUrl(apiBaseUrl);
  String get imageBaseUrl =>
      tmdbImageBaseUrlForApiBaseUrl(normalizedApiBaseUrl);

  TmdbConfig copyWith({
    String? accessToken,
    String? language,
    String? region,
    String? apiBaseUrl,
  }) {
    return TmdbConfig(
      accessToken: accessToken ?? this.accessToken,
      language: language ?? this.language,
      region: region ?? this.region,
      apiBaseUrl: normalizeTmdbApiBaseUrl(apiBaseUrl ?? this.apiBaseUrl),
    );
  }

  factory TmdbConfig.fromJson(Map<String, dynamic> json) => TmdbConfig(
        accessToken: json['accessToken'] as String? ?? '',
        language: json['language'] as String? ?? 'zh-CN',
        region: json['region'] as String? ?? 'CN',
        apiBaseUrl: selectedTmdbApiBaseUrl(json['apiBaseUrl'] as String? ?? ''),
      );

  Map<String, dynamic> toJson() => {
        'accessToken': accessToken,
        'language': language,
        'region': region,
        'apiBaseUrl': normalizedApiBaseUrl,
      };
}

class DanmuConfig {
  const DanmuConfig({
    this.enabled = false,
    this.apiBaseUrl = '',
    this.apiToken = '',
    this.visible = true,
    this.fontSize = 18,
    this.opacity = 0.92,
    this.speed = 1,
    this.offsetMs = 0,
    this.maxLines = 8,
    this.topPadding = 24,
  });

  final bool enabled;
  final String apiBaseUrl;
  final String apiToken;
  final bool visible;
  final double fontSize;
  final double opacity;
  final double speed;
  final int offsetMs;
  final int maxLines;
  final double topPadding;

  String get normalizedApiBaseUrl => normalizeDanmuApiBaseUrl(apiBaseUrl);
  String get normalizedApiToken => normalizeDanmuApiToken(apiToken);
  String get requestBaseUrl =>
      buildDanmuRequestBaseUrl(normalizedApiBaseUrl, normalizedApiToken);
  bool get available => enabled && requestBaseUrl.isNotEmpty;

  DanmuConfig copyWith({
    bool? enabled,
    String? apiBaseUrl,
    String? apiToken,
    bool? visible,
    double? fontSize,
    double? opacity,
    double? speed,
    int? offsetMs,
    int? maxLines,
    double? topPadding,
  }) {
    final endpoint = _normalizeDanmuEndpointParts(
      apiBaseUrl ?? this.apiBaseUrl,
      apiToken ?? this.apiToken,
    );
    return DanmuConfig(
      enabled: enabled ?? this.enabled,
      apiBaseUrl: endpoint.apiBaseUrl,
      apiToken: endpoint.apiToken,
      visible: visible ?? this.visible,
      fontSize: fontSize ?? this.fontSize,
      opacity: opacity ?? this.opacity,
      speed: speed ?? this.speed,
      offsetMs: offsetMs ?? this.offsetMs,
      maxLines: maxLines ?? this.maxLines,
      topPadding: topPadding ?? this.topPadding,
    );
  }

  factory DanmuConfig.fromJson(Map<String, dynamic> json) {
    final endpoint = _normalizeDanmuEndpointParts(
      json['apiBaseUrl'] as String? ?? '',
      json['apiToken'] as String? ?? '',
    );
    return DanmuConfig(
      enabled: json['enabled'] as bool? ?? false,
      apiBaseUrl: endpoint.apiBaseUrl,
      apiToken: endpoint.apiToken,
      visible: json['visible'] as bool? ?? true,
      fontSize: (json['fontSize'] as num?)?.toDouble() ?? 18,
      opacity: (json['opacity'] as num?)?.toDouble() ?? 0.92,
      speed: (json['speed'] as num?)?.toDouble() ?? 1,
      offsetMs: (json['offsetMs'] as num?)?.toInt() ?? 0,
      maxLines: (json['maxLines'] as num?)?.toInt() ?? 8,
      topPadding: (json['topPadding'] as num?)?.toDouble() ?? 24,
    );
  }

  Map<String, dynamic> toJson() => {
        'enabled': enabled,
        'apiBaseUrl': normalizedApiBaseUrl,
        'apiToken': normalizedApiToken,
        'visible': visible,
        'fontSize': fontSize,
        'opacity': opacity,
        'speed': speed,
        'offsetMs': offsetMs,
        'maxLines': maxLines,
        'topPadding': topPadding,
      };
}

String normalizeDanmuApiBaseUrl(String value) =>
    _normalizeDanmuEndpointParts(value, '').apiBaseUrl;

String normalizeDanmuApiToken(String value) => value.trim().replaceAll('/', '');

String buildDanmuRequestBaseUrl(String apiBaseUrl, String apiToken) {
  final base = normalizeDanmuApiBaseUrl(apiBaseUrl);
  if (base.isEmpty) return '';
  final token = normalizeDanmuApiToken(apiToken);
  if (token.isEmpty || token == '87654321') return base;
  final uri = Uri.tryParse(base);
  if (uri == null) return base;
  final segments = uri.pathSegments.where((part) => part.isNotEmpty).toList();
  if (segments.isNotEmpty && segments.last == token) return base;
  return Uri(
    scheme: uri.scheme,
    userInfo: uri.userInfo,
    host: uri.host,
    port: uri.hasPort ? uri.port : null,
    pathSegments: [...segments, token],
  ).toString().replaceFirst(RegExp(r'/$'), '');
}

_DanmuEndpointParts _normalizeDanmuEndpointParts(
  String apiBaseUrl,
  String apiToken,
) {
  var normalized = apiBaseUrl.trim();
  while (normalized.endsWith('/')) {
    normalized = normalized.substring(0, normalized.length - 1);
  }
  final tokenFromField = normalizeDanmuApiToken(apiToken);
  if (normalized.isEmpty) {
    return _DanmuEndpointParts('', tokenFromField);
  }
  if (!normalized.startsWith('http://') && !normalized.startsWith('https://')) {
    normalized = 'https://$normalized';
  }
  final uri = Uri.tryParse(normalized);
  if (uri == null || uri.host.isEmpty) {
    return _DanmuEndpointParts('', tokenFromField);
  }
  final segments = uri.pathSegments.where((part) => part.isNotEmpty).toList();
  if (segments.length >= 2 &&
      segments[segments.length - 2] == 'api' &&
      segments.last == 'v2') {
    segments.removeLast();
    segments.removeLast();
  }
  var token = tokenFromField;
  if (segments.isNotEmpty &&
      (token.isEmpty || segments.last == token) &&
      !_danmuKnownPathSegments.contains(segments.last)) {
    token = segments.removeLast();
  }
  final baseUrl = Uri(
    scheme: uri.scheme,
    userInfo: uri.userInfo,
    host: uri.host,
    port: uri.hasPort ? uri.port : null,
    pathSegments: segments,
  ).toString().replaceFirst(RegExp(r'/$'), '');
  return _DanmuEndpointParts(baseUrl, token);
}

const _danmuKnownPathSegments = {
  'api',
  'v1',
  'v2',
  'search',
  'match',
  'bangumi',
  'comment',
  'danmaku',
};

class _DanmuEndpointParts {
  const _DanmuEndpointParts(this.apiBaseUrl, this.apiToken);

  final String apiBaseUrl;
  final String apiToken;
}

class MediaMetadata {
  const MediaMetadata({
    required this.itemId,
    required this.tmdbId,
    required this.mediaType,
    required this.title,
    this.originalTitle,
    this.overview,
    this.posterPath,
    this.backdropPath,
    this.stillPath,
    this.logoPath,
    this.profilePaths = const [],
    this.castNames = const [],
    this.genres = const [],
    this.releaseDate,
    this.voteAverage,
    this.totalSeasons,
    this.totalEpisodes,
    this.seasonTmdbId,
    this.seasonName,
    this.seasonOverview,
    this.seasonAirDate,
    this.seasonEpisodeCount,
    this.seasonPosterPath,
    this.episodeTmdbId,
    this.episodeName,
    this.episodeOverview,
    this.episodeRuntime,
    this.episodeType,
    this.episodeVoteCount,
    this.updatedAt,
    this.schemaVersion = 0,
  });

  final String itemId;
  final int tmdbId;
  final String mediaType;
  final String title;
  final String? originalTitle;
  final String? overview;
  final String? posterPath;
  final String? backdropPath;
  final String? stillPath;
  final String? logoPath;
  final List<String> profilePaths;
  final List<String> castNames;
  final List<String> genres;
  final String? releaseDate;
  final double? voteAverage;
  final int? totalSeasons;
  final int? totalEpisodes;
  final int? seasonTmdbId;
  final String? seasonName;
  final String? seasonOverview;
  final String? seasonAirDate;
  final int? seasonEpisodeCount;
  final String? seasonPosterPath;
  final int? episodeTmdbId;
  final String? episodeName;
  final String? episodeOverview;
  final int? episodeRuntime;
  final String? episodeType;
  final int? episodeVoteCount;
  final int? updatedAt;
  final int schemaVersion;

  String? get posterUrl => tmdbImageUrl(posterPath, 'w500');
  String? get backdropUrl => tmdbImageUrl(backdropPath, 'w780');
  String? get stillUrl => tmdbImageUrl(stillPath, 'w780');
  String? get logoUrl => tmdbImageUrl(logoPath, 'w300');
  List<String> get profileUrls =>
      profilePaths.map((path) => tmdbImageUrl(path, 'w185')).nonNulls.toList();

  factory MediaMetadata.fromJson(Map<String, dynamic> json) => MediaMetadata(
        itemId: json['itemId'] as String,
        tmdbId: (json['tmdbId'] as num).toInt(),
        mediaType: json['mediaType'] as String? ?? 'movie',
        title: json['title'] as String? ?? '',
        originalTitle: json['originalTitle'] as String?,
        overview: json['overview'] as String?,
        posterPath: json['posterPath'] as String?,
        backdropPath: json['backdropPath'] as String?,
        stillPath: json['stillPath'] as String?,
        logoPath: json['logoPath'] as String?,
        profilePaths: (json['profilePaths'] as List<dynamic>? ?? const [])
            .whereType<String>()
            .toList(),
        castNames: (json['castNames'] as List<dynamic>? ?? const [])
            .whereType<String>()
            .toList(),
        genres: (json['genres'] as List<dynamic>? ?? const [])
            .whereType<String>()
            .toList(),
        releaseDate: json['releaseDate'] as String?,
        voteAverage: (json['voteAverage'] as num?)?.toDouble(),
        totalSeasons: (json['totalSeasons'] as num?)?.toInt(),
        totalEpisodes: (json['totalEpisodes'] as num?)?.toInt(),
        seasonTmdbId: (json['seasonTmdbId'] as num?)?.toInt(),
        seasonName: json['seasonName'] as String?,
        seasonOverview: json['seasonOverview'] as String?,
        seasonAirDate: json['seasonAirDate'] as String?,
        seasonEpisodeCount: (json['seasonEpisodeCount'] as num?)?.toInt(),
        seasonPosterPath: json['seasonPosterPath'] as String?,
        episodeTmdbId: (json['episodeTmdbId'] as num?)?.toInt(),
        episodeName: json['episodeName'] as String?,
        episodeOverview: json['episodeOverview'] as String?,
        episodeRuntime: (json['episodeRuntime'] as num?)?.toInt(),
        episodeType: json['episodeType'] as String?,
        episodeVoteCount: (json['episodeVoteCount'] as num?)?.toInt(),
        updatedAt: (json['updatedAt'] as num?)?.toInt(),
        schemaVersion: (json['schemaVersion'] as num?)?.toInt() ?? 0,
      );

  Map<String, dynamic> toJson() => {
        'itemId': itemId,
        'tmdbId': tmdbId,
        'mediaType': mediaType,
        'title': title,
        'originalTitle': originalTitle,
        'overview': overview,
        'posterPath': posterPath,
        'backdropPath': backdropPath,
        'stillPath': stillPath,
        'logoPath': logoPath,
        'profilePaths': profilePaths,
        'castNames': castNames,
        'genres': genres,
        'releaseDate': releaseDate,
        'voteAverage': voteAverage,
        'totalSeasons': totalSeasons,
        'totalEpisodes': totalEpisodes,
        'seasonTmdbId': seasonTmdbId,
        'seasonName': seasonName,
        'seasonOverview': seasonOverview,
        'seasonAirDate': seasonAirDate,
        'seasonEpisodeCount': seasonEpisodeCount,
        'seasonPosterPath': seasonPosterPath,
        'episodeTmdbId': episodeTmdbId,
        'episodeName': episodeName,
        'episodeOverview': episodeOverview,
        'episodeRuntime': episodeRuntime,
        'episodeType': episodeType,
        'episodeVoteCount': episodeVoteCount,
        'updatedAt': updatedAt,
        'schemaVersion': schemaVersion,
      };
}

class LibraryHomeEntry {
  const LibraryHomeEntry({
    required this.folderId,
    required this.sourceId,
    required this.folderPath,
    required this.showId,
    required this.tmdbId,
    required this.title,
    this.overview,
    this.posterPath,
    this.backdropPath,
    this.voteAverage,
    this.releaseDate,
    this.totalEpisodes,
    required this.localFileCount,
    this.latestPlayedAt,
    this.matched = false,
  });

  final int folderId;
  final String sourceId;
  final String folderPath;
  final int showId;
  final int tmdbId;
  final String title;
  final String? overview;
  final String? posterPath;
  final String? backdropPath;
  final double? voteAverage;
  final String? releaseDate;
  final int? totalEpisodes;
  final int localFileCount;
  final int? latestPlayedAt;
  final bool matched;

  factory LibraryHomeEntry.fromJson(Map<String, dynamic> json) {
    return LibraryHomeEntry(
      folderId: (json['folderId'] as num?)?.toInt() ?? 0,
      sourceId: json['sourceId'] as String? ?? '',
      folderPath: json['folderPath'] as String? ?? '',
      showId: (json['showId'] as num?)?.toInt() ?? 0,
      tmdbId: (json['tmdbId'] as num?)?.toInt() ?? 0,
      title: json['title'] as String? ?? '',
      overview: json['overview'] as String?,
      posterPath: json['posterPath'] as String?,
      backdropPath: json['backdropPath'] as String?,
      voteAverage: (json['voteAverage'] as num?)?.toDouble(),
      releaseDate: json['releaseDate'] as String?,
      totalEpisodes: (json['totalEpisodes'] as num?)?.toInt(),
      localFileCount: (json['localFileCount'] as num?)?.toInt() ?? 0,
      latestPlayedAt: (json['latestPlayedAt'] as num?)?.toInt(),
      matched: json['matched'] == true,
    );
  }

  String get folderKey => '$sourceId:db:$folderPath';
}

class LibraryShowDetail {
  const LibraryShowDetail({
    required this.folderKey,
    this.genres = const [],
    this.castNames = const [],
    this.profilePaths = const [],
    required this.files,
  });

  final String folderKey;
  final List<String> genres;
  final List<String> castNames;
  final List<String?> profilePaths;
  final List<LibraryFileEntry> files;

  LibraryFileEntry? get currentFile {
    final played = files.where((file) => (file.lastPlayedAt ?? 0) > 0).toList()
      ..sort((a, b) => (b.lastPlayedAt ?? 0).compareTo(a.lastPlayedAt ?? 0));
    if (played.isNotEmpty) return played.first;
    final progress = files.where((file) => (file.positionMs ?? 0) > 0).toList()
      ..sort((a, b) => (b.positionMs ?? 0).compareTo(a.positionMs ?? 0));
    if (progress.isNotEmpty) return progress.first;
    return files.firstOrNull;
  }

  LibraryFileEntry? get representative => currentFile ?? files.firstOrNull;

  factory LibraryShowDetail.fromJson(Map<String, dynamic> json) {
    return LibraryShowDetail(
      folderKey: json['folderKey'] as String? ?? '',
      genres: (json['genres'] as List<dynamic>? ?? const [])
          .whereType<String>()
          .toList(),
      castNames: (json['castNames'] as List<dynamic>? ?? const [])
          .whereType<String>()
          .toList(),
      profilePaths: (json['profilePaths'] as List<dynamic>? ?? const [])
          .map((value) => value is String ? value : null)
          .toList(),
      files: (json['files'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(LibraryFileEntry.fromJson)
          .toList(),
    );
  }
}

class LibraryFileEntry {
  const LibraryFileEntry({
    required this.fileId,
    required this.itemId,
    required this.relativePath,
    required this.filename,
    this.size,
    this.guessSeason,
    this.guessEpisode,
    this.positionMs,
    this.durationMs,
    this.lastPlayedAt,
    this.showId,
    this.tmdbId,
    this.showTitle,
    this.originalTitle,
    this.showOverview,
    this.posterPath,
    this.backdropPath,
    this.logoPath,
    this.voteAverage,
    this.releaseDate,
    this.totalSeasons,
    this.totalEpisodes,
    this.episodeId,
    this.seasonNumber,
    this.episodeNumber,
    this.episodeName,
    this.episodeOverview,
    this.episodeAirDate,
    this.runtime,
    this.stillPath,
  });

  final int fileId;
  final String itemId;
  final String relativePath;
  final String filename;
  final int? size;
  final int? guessSeason;
  final int? guessEpisode;
  final int? positionMs;
  final int? durationMs;
  final int? lastPlayedAt;
  final int? showId;
  final int? tmdbId;
  final String? showTitle;
  final String? originalTitle;
  final String? showOverview;
  final String? posterPath;
  final String? backdropPath;
  final String? logoPath;
  final double? voteAverage;
  final String? releaseDate;
  final int? totalSeasons;
  final int? totalEpisodes;
  final int? episodeId;
  final int? seasonNumber;
  final int? episodeNumber;
  final String? episodeName;
  final String? episodeOverview;
  final String? episodeAirDate;
  final int? runtime;
  final String? stillPath;

  factory LibraryFileEntry.fromJson(Map<String, dynamic> json) {
    return LibraryFileEntry(
      fileId: (json['fileId'] as num?)?.toInt() ?? 0,
      itemId: json['itemId'] as String? ?? '',
      relativePath: json['relativePath'] as String? ?? '',
      filename: json['filename'] as String? ?? '',
      size: (json['size'] as num?)?.toInt(),
      guessSeason: (json['guessSeason'] as num?)?.toInt(),
      guessEpisode: (json['guessEpisode'] as num?)?.toInt(),
      positionMs: (json['positionMs'] as num?)?.toInt(),
      durationMs: (json['durationMs'] as num?)?.toInt(),
      lastPlayedAt: (json['lastPlayedAt'] as num?)?.toInt(),
      showId: (json['showId'] as num?)?.toInt(),
      tmdbId: (json['tmdbId'] as num?)?.toInt(),
      showTitle: json['showTitle'] as String?,
      originalTitle: json['originalTitle'] as String?,
      showOverview: json['showOverview'] as String?,
      posterPath: json['posterPath'] as String?,
      backdropPath: json['backdropPath'] as String?,
      logoPath: json['logoPath'] as String?,
      voteAverage: (json['voteAverage'] as num?)?.toDouble(),
      releaseDate: json['releaseDate'] as String?,
      totalSeasons: (json['totalSeasons'] as num?)?.toInt(),
      totalEpisodes: (json['totalEpisodes'] as num?)?.toInt(),
      episodeId: (json['episodeId'] as num?)?.toInt(),
      seasonNumber: (json['seasonNumber'] as num?)?.toInt(),
      episodeNumber: (json['episodeNumber'] as num?)?.toInt(),
      episodeName: json['episodeName'] as String?,
      episodeOverview: json['episodeOverview'] as String?,
      episodeAirDate: json['episodeAirDate'] as String?,
      runtime: (json['runtime'] as num?)?.toInt(),
      stillPath: json['stillPath'] as String?,
    );
  }

  String get displayTitle {
    if (episodeName?.isNotEmpty == true) return episodeName!;
    return filename.isEmpty ? relativePath : filename;
  }

  int? get displayEpisode => episodeNumber ?? guessEpisode;
  int? get displaySeason => seasonNumber ?? guessSeason;
}

class LibraryRecentEntry {
  const LibraryRecentEntry({
    required this.fileId,
    required this.itemId,
    required this.relativePath,
    required this.filename,
    this.size,
    required this.positionMs,
    this.durationMs,
    this.lastPlayedAt,
    this.showTitle,
    this.posterPath,
    this.backdropPath,
    this.seasonNumber,
    this.episodeNumber,
    this.episodeName,
    this.stillPath,
  });

  final int fileId;
  final String itemId;
  final String relativePath;
  final String filename;
  final int? size;
  final int positionMs;
  final int? durationMs;
  final int? lastPlayedAt;
  final String? showTitle;
  final String? posterPath;
  final String? backdropPath;
  final int? seasonNumber;
  final int? episodeNumber;
  final String? episodeName;
  final String? stillPath;

  factory LibraryRecentEntry.fromJson(Map<String, dynamic> json) {
    return LibraryRecentEntry(
      fileId: (json['fileId'] as num?)?.toInt() ?? 0,
      itemId: json['itemId'] as String? ?? '',
      relativePath: json['relativePath'] as String? ?? '',
      filename: json['filename'] as String? ?? '',
      size: (json['size'] as num?)?.toInt(),
      positionMs: (json['positionMs'] as num?)?.toInt() ?? 0,
      durationMs: (json['durationMs'] as num?)?.toInt(),
      lastPlayedAt: (json['lastPlayedAt'] as num?)?.toInt(),
      showTitle: json['showTitle'] as String?,
      posterPath: json['posterPath'] as String?,
      backdropPath: json['backdropPath'] as String?,
      seasonNumber: (json['seasonNumber'] as num?)?.toInt(),
      episodeNumber: (json['episodeNumber'] as num?)?.toInt(),
      episodeName: json['episodeName'] as String?,
      stillPath: json['stillPath'] as String?,
    );
  }

  String get displayTitle {
    final prefix = showTitle?.isNotEmpty == true ? showTitle! : filename;
    if (episodeNumber == null) return prefix;
    final name = episodeName?.isNotEmpty == true ? ' $episodeName' : '';
    return '$prefix 第 $episodeNumber 集$name';
  }
}

class WebdavSourceDraft {
  const WebdavSourceDraft({
    required this.name,
    required this.baseUrl,
    required this.username,
    required this.password,
    required this.directory,
  });

  final String name;
  final String baseUrl;
  final String username;
  final String password;
  final String directory;
}

class SyncConfig {
  const SyncConfig({
    required this.baseUrl,
    required this.username,
    required this.password,
    required this.configPath,
    this.databasePath = '/Player/metadata.sqlite',
    this.syncConfigFile = true,
    this.syncDatabase = true,
  });

  final String baseUrl;
  final String username;
  final String password;
  final String configPath;
  final String databasePath;
  final bool syncConfigFile;
  final bool syncDatabase;

  MediaSourceConfig asSource() => MediaSourceConfig.webdav(
        id: 'sync',
        name: '同步 WebDAV',
        baseUrl: baseUrl,
        username: username,
        password: password,
        directory: '/',
      );

  factory SyncConfig.fromJson(Map<String, dynamic> json) => SyncConfig(
        baseUrl: json['baseUrl'] as String? ?? '',
        username: json['username'] as String? ?? '',
        password: json['password'] as String? ?? '',
        configPath: json['configPath'] as String? ?? '/Player/config.json',
        databasePath:
            json['databasePath'] as String? ?? '/Player/metadata.sqlite',
        syncConfigFile: json['syncConfigFile'] as bool? ?? true,
        syncDatabase: json['syncDatabase'] as bool? ?? true,
      );

  Map<String, dynamic> toJson() => {
        'baseUrl': baseUrl,
        'username': username,
        'password': password,
        'configPath': configPath,
        'databasePath': databasePath,
        'syncConfigFile': syncConfigFile,
        'syncDatabase': syncDatabase,
      };
}

class WebdavEntry {
  const WebdavEntry(
      {required this.name,
      required this.path,
      required this.url,
      required this.isDir,
      this.size});

  final String name;
  final String path;
  final String url;
  final bool isDir;
  final int? size;
}

class LocalEntry {
  const LocalEntry(
      {required this.name, required this.path, required this.isDir, this.size});

  final String name;
  final String path;
  final bool isDir;
  final int? size;
}
