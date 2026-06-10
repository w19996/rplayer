part of 'package:player_flutter/main.dart';

const currentMetadataSchemaVersion = 4;

enum _TmdbEndpointKind { search, detail }

class TmdbMetadataService {
  TmdbMetadataService(this.config, {this.log});

  final TmdbConfig config;
  final void Function(String message)? log;
  final Map<String, Map<String, dynamic>> _jsonCache = {};

  String get _baseUrl {
    final value = config.apiBaseUrl.trim();
    if (value.isEmpty) return defaultTmdbApiBaseUrl;
    return _normalizeBaseUrl(value);
  }

  Future<MediaMetadata?> lookup(MediaItem item) async {
    if (!config.enabled) return null;
    final tmdbId = explicitTmdbId(item);
    if (tmdbId != null) {
      _log('explicit tmdb id $tmdbId for ${describeMediaItem(item)}');
      final metadata = await _lookupExplicitId(item, tmdbId);
      if (metadata != null) return metadata;
    }

    final queries = looksLikeSeriesItem(item) || item.mediaKind == 'TvEpisode'
        ? _tvQueriesFor(item)
        : _movieQueriesFor(item);
    _log('queries for ${describeMediaItem(item)} => ${queries.join(' | ')}');
    if (queries.isEmpty) return null;

    if (looksLikeSeriesItem(item)) {
      return await _lookupTv(item, queries) ??
          await _lookupMovie(item, queries);
    }
    if (item.mediaKind == 'TvEpisode') {
      return await _lookupTv(item, queries) ??
          await _lookupMovie(item, queries);
    }
    if (item.mediaKind == 'Movie') {
      return await _lookupMovie(item, queries) ??
          await _lookupTv(item, queries);
    }
    return await _lookupMovie(item, queries) ?? await _lookupTv(item, queries);
  }

  Future<MediaMetadata?> _lookupExplicitId(MediaItem item, int id) async {
    if (looksLikeSeriesItem(item)) {
      return await _lookupTvId(item, id) ?? await _lookupMovieId(item, id);
    }
    if (item.mediaKind == 'TvEpisode') {
      return await _lookupTvId(item, id) ?? await _lookupMovieId(item, id);
    }
    if (item.mediaKind == 'Movie') {
      return await _lookupMovieId(item, id) ?? await _lookupTvId(item, id);
    }
    return await _lookupMovieId(item, id) ?? await _lookupTvId(item, id);
  }

  Future<MediaMetadata?> _lookupMovieId(MediaItem item, int id) async {
    try {
      final details = await _getJson(
        '/movie/$id',
        {'append_to_response': 'images,credits'},
      );
      return _movieMetadata(item, details);
    } catch (_) {
      return null;
    }
  }

  Future<MediaMetadata?> _lookupTvId(MediaItem item, int id) async {
    try {
      _log('GET /tv/$id');
      final details = await _getJson(
        '/tv/$id',
        {'append_to_response': 'images,aggregate_credits'},
      );
      Map<String, dynamic>? seasonDetails;
      Map<String, dynamic>? episodeDetails;
      final season = inferredSeasonNumber(item);
      final episode = inferredEpisodeNumber(item);
      if (season != null) {
        _log('GET /tv/$id/season/$season');
        seasonDetails = await _getJsonOrNull(
          '/tv/$id/season/$season',
          const {},
        );
        episodeDetails = _episodeFromSeason(seasonDetails, episode);
      }
      return _tvMetadata(item, details, seasonDetails, episodeDetails);
    } catch (_) {
      return null;
    }
  }

  Future<MediaMetadata?> _lookupMovie(
      MediaItem item, List<String> queries) async {
    for (final query in queries) {
      _log('GET /search/movie query="$query"');
      final results = await _getJsonList(
        '/search/movie',
        {
          'query': query,
          if (item.matchYear != null) 'year': '${item.matchYear}',
        },
        kind: _TmdbEndpointKind.search,
      );
      _log('/search/movie query="$query" results=${results.length}');
      final best = _bestSearchResult(results, item, movie: true);
      if (best == null) continue;

      final id = (best['id'] as num?)?.toInt();
      if (id == null) continue;
      _log(
          'selected movie id=$id title=${best['title']} poster=${best['poster_path']}');
      final details = await _getJson(
        '/movie/$id',
        {'append_to_response': 'images,credits'},
      );
      return _movieMetadata(item, details);
    }
    return null;
  }

  Future<MediaMetadata?> _lookupTv(MediaItem item, List<String> queries) async {
    for (final query in queries) {
      _log('GET /search/tv query="$query"');
      final results = await _getJsonList(
        '/search/tv',
        {
          'query': query,
          if (item.matchYear != null)
            'first_air_date_year': '${item.matchYear}',
        },
        kind: _TmdbEndpointKind.search,
      );
      _log('/search/tv query="$query" results=${results.length}');
      final best = _bestSearchResult(results, item, movie: false);
      if (best == null) continue;

      final id = (best['id'] as num?)?.toInt();
      if (id == null) continue;
      _log(
          'selected tv id=$id name=${best['name']} poster=${best['poster_path']}');
      _log('GET /tv/$id');
      final details = await _getJson(
        '/tv/$id',
        {'append_to_response': 'images,aggregate_credits'},
      );
      Map<String, dynamic>? seasonDetails;
      Map<String, dynamic>? episodeDetails;
      final season = inferredSeasonNumber(item);
      final episode = inferredEpisodeNumber(item);
      if (season != null) {
        _log('GET /tv/$id/season/$season');
        seasonDetails = await _getJsonOrNull(
          '/tv/$id/season/$season',
          const {},
        );
        episodeDetails = _episodeFromSeason(seasonDetails, episode);
        _log(
            'season=$season episode=$episode still=${episodeDetails?['still_path']}');
      }
      return _tvMetadata(item, details, seasonDetails, episodeDetails);
    }
    return null;
  }

  List<String> _tvQueriesFor(MediaItem item) {
    final folderTitle = cleanTmdbHints(mediaGroupDisplayTitle(item));
    final values = <String>[
      folderTitle,
      item.matchTitle,
    ];
    return _dedupeQueries(values);
  }

  List<String> _movieQueriesFor(MediaItem item) {
    final folderTitle = cleanTmdbHints(mediaGroupDisplayTitle(item));
    final values = <String>[
      item.matchTitle,
      folderTitle,
      item.title.replaceAll(RegExp(r'[Ss]\d{1,2}[Ee]\d{1,3}'), ''),
      item.title.replaceAll(RegExp(r'\d{4}'), ''),
      item.title,
    ];
    return _dedupeQueries(values);
  }

  List<String> _dedupeQueries(List<String> values) {
    return values
        .map(cleanTmdbHints)
        .map((value) => value.trim())
        .where((value) => value.length >= 2)
        .fold<List<String>>([], (acc, value) {
      final normalized = normalizeMatchText(value);
      if (normalized.isNotEmpty &&
          !acc.any((entry) => normalizeMatchText(entry) == normalized)) {
        acc.add(value);
      }
      return acc;
    });
  }

  Map<String, dynamic>? _bestSearchResult(
      List<Map<String, dynamic>> results, MediaItem item,
      {required bool movie}) {
    if (results.isEmpty) return null;
    final target = normalizeMatchText(mediaGroupDisplayTitle(item));
    final parsedTarget = normalizeMatchText(
        item.matchTitle.isNotEmpty ? item.matchTitle : item.title);
    final basename = normalizeMatchText(item.title);
    Map<String, dynamic>? best;
    var bestScore = -1;

    for (final result in results.take(8)) {
      final title = normalizeMatchText(
        (movie ? result['title'] : result['name']) as String? ?? '',
      );
      final originalTitle = normalizeMatchText(
        (movie ? result['original_title'] : result['original_name'])
                as String? ??
            '',
      );
      if (title.isEmpty && originalTitle.isEmpty) continue;
      var score = 0;
      if (title == target || originalTitle == target) score += 90;
      if (title == parsedTarget || originalTitle == parsedTarget) score += 86;
      if (title == basename || originalTitle == basename) score += 80;
      if (target.contains(title) || title.contains(target)) score += 35;
      if (parsedTarget.contains(title) || title.contains(parsedTarget)) {
        score += 32;
      }
      if (basename.contains(title) || title.contains(basename)) score += 30;
      if (result['poster_path'] != null) score += 8;
      if (result['backdrop_path'] != null) score += 4;
      final date = (movie ? result['release_date'] : result['first_air_date'])
          as String?;
      if (item.matchYear != null &&
          date?.startsWith('${item.matchYear}') == true) {
        score += 18;
      }
      score += ((result['vote_count'] as num?)?.toInt() ?? 0).clamp(0, 20);

      if (score > bestScore) {
        bestScore = score;
        best = result;
      }
    }
    return best ?? results.first;
  }

  MediaMetadata _movieMetadata(MediaItem item, Map<String, dynamic> json) {
    final images = json['images'] as Map<String, dynamic>?;
    final credits = json['credits'] as Map<String, dynamic>?;
    return MediaMetadata(
      itemId: item.id,
      tmdbId: (json['id'] as num).toInt(),
      mediaType: 'movie',
      title: json['original_title'] as String? ??
          json['title'] as String? ??
          item.title,
      originalTitle: json['title'] as String?,
      overview: json['overview'] as String?,
      posterPath: json['poster_path'] as String?,
      backdropPath: json['backdrop_path'] as String?,
      logoPath: _firstImagePath(images, 'logos', 'file_path'),
      profilePaths: _profilePaths(credits),
      castNames: _castNames(credits),
      genres: _genres(json),
      releaseDate: json['release_date'] as String?,
      voteAverage: (json['vote_average'] as num?)?.toDouble(),
      totalEpisodes: 1,
      updatedAt: DateTime.now().millisecondsSinceEpoch,
      schemaVersion: currentMetadataSchemaVersion,
    );
  }

  Map<String, dynamic>? _episodeFromSeason(
      Map<String, dynamic>? seasonJson, int? episodeNumber) {
    if (seasonJson == null || episodeNumber == null) return null;
    final episodes = seasonJson['episodes'] as List<dynamic>? ?? const [];
    return episodes.whereType<Map<String, dynamic>>().firstWhere(
          (episode) =>
              (episode['episode_number'] as num?)?.toInt() == episodeNumber,
          orElse: () => <String, dynamic>{},
        );
  }

  MediaMetadata _tvMetadata(MediaItem item, Map<String, dynamic> json,
      Map<String, dynamic>? seasonJson, Map<String, dynamic>? episodeJson) {
    final images = json['images'] as Map<String, dynamic>?;
    final credits = json['aggregate_credits'] as Map<String, dynamic>?;
    final episode = episodeJson?.isEmpty == true ? null : episodeJson;
    return MediaMetadata(
      itemId: item.id,
      tmdbId: (json['id'] as num).toInt(),
      mediaType: 'tv',
      title: json['original_name'] as String? ??
          json['name'] as String? ??
          item.title,
      originalTitle: json['name'] as String?,
      overview: episode?['overview'] as String? ?? json['overview'] as String?,
      posterPath: json['poster_path'] as String?,
      backdropPath: json['backdrop_path'] as String?,
      stillPath: episode?['still_path'] as String?,
      logoPath: _firstImagePath(images, 'logos', 'file_path'),
      profilePaths: _profilePaths(credits),
      castNames: _castNames(credits),
      genres: _genres(json),
      releaseDate:
          episode?['air_date'] as String? ?? json['first_air_date'] as String?,
      voteAverage: (episode?['vote_average'] as num?)?.toDouble() ??
          (json['vote_average'] as num?)?.toDouble(),
      totalSeasons: (json['number_of_seasons'] as num?)?.toInt(),
      totalEpisodes: (json['number_of_episodes'] as num?)?.toInt(),
      episodeName: episode?['name'] as String?,
      updatedAt: DateTime.now().millisecondsSinceEpoch,
      schemaVersion: currentMetadataSchemaVersion,
    );
  }

  String? _firstImagePath(
      Map<String, dynamic>? images, String listKey, String pathKey) {
    final list = images?[listKey] as List<dynamic>?;
    if (list == null || list.isEmpty) return null;
    final value = list.firstWhere(
      (item) => item is Map<String, dynamic> && item[pathKey] != null,
      orElse: () => null,
    );
    return value is Map<String, dynamic> ? value[pathKey] as String? : null;
  }

  List<String> _profilePaths(Map<String, dynamic>? credits) {
    final cast = credits?['cast'] as List<dynamic>? ?? const [];
    return cast
        .take(8)
        .whereType<Map<String, dynamic>>()
        .map((person) => person['profile_path'])
        .whereType<String>()
        .toList();
  }

  List<String> _castNames(Map<String, dynamic>? credits) {
    final cast = credits?['cast'] as List<dynamic>? ?? const [];
    return cast
        .take(8)
        .whereType<Map<String, dynamic>>()
        .map((person) => person['name'])
        .whereType<String>()
        .toList();
  }

  List<String> _genres(Map<String, dynamic> json) {
    final genres = json['genres'] as List<dynamic>? ?? const [];
    return genres
        .whereType<Map<String, dynamic>>()
        .map((genre) => genre['name'])
        .whereType<String>()
        .toList();
  }

  Future<List<Map<String, dynamic>>> _getJsonList(
    String path,
    Map<String, String> query, {
    _TmdbEndpointKind kind = _TmdbEndpointKind.detail,
  }) async {
    final json = await _getJson(path, query, kind: kind);
    return (json['results'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .toList();
  }

  Future<Map<String, dynamic>?> _getJsonOrNull(
      String path, Map<String, String> query) async {
    try {
      return await _getJson(path, query);
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, dynamic>> _getJson(
    String path,
    Map<String, String> query, {
    _TmdbEndpointKind kind = _TmdbEndpointKind.detail,
  }) async {
    final uri = Uri.parse('$_baseUrl$path').replace(queryParameters: {
      'language': config.language,
      if (kind == _TmdbEndpointKind.detail && config.region.isNotEmpty)
        'region': config.region,
      ...query,
    });
    final cacheKey = uri.toString();
    final cached = _jsonCache[cacheKey];
    if (cached != null) {
      _log('cache hit $uri');
      return cached;
    }
    _log('request $uri');
    _log(
        'headers accept=application/json Authorization=Bearer ${_maskedToken()}');
    _log(
        'curl equivalent: curl --request GET --url "$uri" --header "Authorization: Bearer ${_maskedToken()}" --header "accept: application/json"');
    if (config.proxyUrl.trim().isNotEmpty) {
      _log('proxy configured: ${config.proxyUrl.trim()}');
    }
    _log('Rust reqwest request on worker isolate host=${uri.host}');
    final body = await RustCoreService.instance.tmdbGetJsonAsync(
      uri.toString(),
      config.accessToken.trim(),
      config.proxyUrl.trim(),
    );
    final decoded = jsonDecode(body) as Map<String, dynamic>;
    _jsonCache[cacheKey] = decoded;
    return decoded;
  }

  void _log(String message) {
    log?.call(message);
  }

  String _maskedToken() {
    final token = config.accessToken.trim();
    if (token.length <= 10) return '***';
    return '${token.substring(0, 6)}...${token.substring(token.length - 4)}';
  }

  String _normalizeBaseUrl(String value) {
    return value.endsWith('/') ? value.substring(0, value.length - 1) : value;
  }
}
