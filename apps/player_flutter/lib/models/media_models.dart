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
  });

  factory MediaItem.local(
      {required MediaSourceConfig source, required String path}) {
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
  const TmdbApiEndpoint({required this.label, required this.url});

  final String label;
  final String url;
}

const defaultTmdbApiBaseUrl = 'https://api.tmdb.org/3';

const tmdbApiEndpoints = [
  TmdbApiEndpoint(label: 'api.tmdb.org', url: defaultTmdbApiBaseUrl),
  TmdbApiEndpoint(
    label: 'api.themoviedb.org',
    url: 'https://api.themoviedb.org/3',
  ),
];

String normalizeTmdbApiBaseUrl(String value) {
  final trimmed = value.trim();
  final normalized = trimmed.endsWith('/')
      ? trimmed.substring(0, trimmed.length - 1)
      : trimmed;
  if (normalized.isEmpty) return defaultTmdbApiBaseUrl;
  return normalized;
}

String selectedTmdbApiBaseUrl(String value) {
  final normalized = normalizeTmdbApiBaseUrl(value);
  return tmdbApiEndpoints.any((endpoint) => endpoint.url == normalized)
      ? normalized
      : defaultTmdbApiBaseUrl;
}

class TmdbConfig {
  const TmdbConfig({
    this.accessToken = '',
    this.language = 'zh-CN',
    this.region = 'CN',
    this.apiBaseUrl = defaultTmdbApiBaseUrl,
    this.proxyUrl = '',
  });

  final String accessToken;
  final String language;
  final String region;
  final String apiBaseUrl;
  final String proxyUrl;

  bool get enabled => accessToken.trim().isNotEmpty;

  TmdbConfig copyWith({
    String? accessToken,
    String? language,
    String? region,
    String? apiBaseUrl,
    String? proxyUrl,
  }) {
    return TmdbConfig(
      accessToken: accessToken ?? this.accessToken,
      language: language ?? this.language,
      region: region ?? this.region,
      apiBaseUrl: apiBaseUrl ?? this.apiBaseUrl,
      proxyUrl: proxyUrl ?? this.proxyUrl,
    );
  }

  factory TmdbConfig.fromJson(Map<String, dynamic> json) => TmdbConfig(
        accessToken: json['accessToken'] as String? ?? '',
        language: json['language'] as String? ?? 'zh-CN',
        region: json['region'] as String? ?? 'CN',
        apiBaseUrl: selectedTmdbApiBaseUrl(json['apiBaseUrl'] as String? ?? ''),
        proxyUrl: json['proxyUrl'] as String? ?? '',
      );

  Map<String, dynamic> toJson() => {
        'accessToken': accessToken,
        'language': language,
        'region': region,
        'apiBaseUrl': apiBaseUrl,
        'proxyUrl': proxyUrl,
      };
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
    this.episodeName,
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
  final String? episodeName;
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
        episodeName: json['episodeName'] as String?,
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
        'episodeName': episodeName,
        'updatedAt': updatedAt,
        'schemaVersion': schemaVersion,
      };
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
