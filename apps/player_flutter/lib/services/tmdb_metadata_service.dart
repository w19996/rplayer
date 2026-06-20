part of 'package:player_flutter/main.dart';

const currentMetadataSchemaVersion = 10;

enum _TmdbEndpointKind { search, detail }

class TmdbMetadataService {
  TmdbMetadataService(this.config, {this.log});

  final TmdbConfig config;
  final void Function(String message)? log;
  final Map<String, Map<String, dynamic>> _jsonCache = {};

  String get _baseUrl {
    return normalizeTmdbApiBaseUrl(config.apiBaseUrl);
  }

  Future<MediaMetadata?> lookup(MediaItem item) async {
    if (!config.enabled) return null;
    final tmdbId = explicitTmdbId(item);
    if (tmdbId != null) {
      _log('explicit tmdb id $tmdbId for ${describeMediaItem(item)}');
      final metadata = await _lookupExplicitId(item, tmdbId);
      if (metadata != null) return metadata;
    }

    final queries = _multiQueriesFor(item);
    _log('queries for ${describeMediaItem(item)} => ${queries.join(' | ')}');
    if (queries.isEmpty) return null;

    final multi = await _lookupMulti(item, queries);
    if (multi != null) return multi;

    if (looksLikeSeriesItem(item)) {
      return await _lookupTv(item, _tvQueriesFor(item)) ??
          await _lookupMovie(item, _movieQueriesFor(item));
    }
    if (item.mediaKind == 'TvEpisode') {
      return await _lookupTv(item, _tvQueriesFor(item)) ??
          await _lookupMovie(item, _movieQueriesFor(item));
    }
    if (item.mediaKind == 'Movie') {
      return await _lookupMovie(item, _movieQueriesFor(item)) ??
          await _lookupTv(item, _tvQueriesFor(item));
    }
    return await _lookupMovie(item, _movieQueriesFor(item)) ??
        await _lookupTv(item, _tvQueriesFor(item));
  }

  Future<Map<String, MediaMetadata>> lookupGroup(
    MediaFolderGroup group, {
    MediaMetadata? cachedTitle,
  }) async {
    final representative = group.representative;
    if (!group.items.any(looksLikeSeriesItem) &&
        representative.mediaKind != 'TvEpisode') {
      final metadata = await lookup(representative);
      return metadata == null ? {} : {representative.id: metadata};
    }

    if (cachedTitle != null &&
        cachedTitle.mediaType == 'tv' &&
        cachedTitle.tmdbId > 0) {
      final result = await _lookupTvGroupFromCachedTitle(group, cachedTitle);
      if (result.isNotEmpty) return result;
    }
    if (cachedTitle != null &&
        cachedTitle.mediaType == 'movie' &&
        cachedTitle.tmdbId > 0) {
      final result = await _lookupMovieGroupById(group, cachedTitle.tmdbId);
      if (result.isNotEmpty) return result;
    }

    final tmdbId = group.items.map(explicitTmdbId).whereType<int>().firstOrNull;
    if (tmdbId == null) {
      final multi =
          await _lookupMultiGroup(group, _multiQueriesFor(representative));
      if (multi.isNotEmpty) return multi;
    }
    final result = tmdbId == null
        ? await _lookupTvGroup(group, _tvQueriesFor(representative))
        : await _lookupTvGroupById(group, tmdbId);
    if (result.isNotEmpty) return result;

    final metadata = await lookup(representative);
    return metadata == null ? {} : {representative.id: metadata};
  }

  Future<List<TmdbSearchCandidate>> searchCandidates(String query) async {
    final text = query.trim();
    if (!config.enabled || text.isEmpty) return const [];
    const tvTypeLookupLimit = 16;
    const movieGenreLookupLimit = 16;
    _log('manual TMDB search query="$text"');
    final tvResults = await _getJsonList(
      '/search/tv',
      {'query': text},
      kind: _TmdbEndpointKind.search,
    );
    final movieResults = await _getJsonList(
      '/search/movie',
      {'query': text},
      kind: _TmdbEndpointKind.search,
    );
    final tvCandidates = [
      ...await Future.wait(
        tvResults.take(tvTypeLookupLimit).map(_tvSearchCandidate),
      ),
      for (final result in tvResults.skip(tvTypeLookupLimit))
        TmdbSearchCandidate.fromSearchJson(result, mediaType: 'tv'),
    ];
    final movieCandidates = [
      ...await Future.wait(
        movieResults.take(movieGenreLookupLimit).map(_movieSearchCandidate),
      ),
      for (final result in movieResults.skip(movieGenreLookupLimit))
        TmdbSearchCandidate.fromSearchJson(result, mediaType: 'movie'),
    ];
    final candidates = [
      ...tvCandidates,
      ...movieCandidates,
    ]
        .where((candidate) =>
            candidate.tmdbId > 0 && candidate.title.trim().isNotEmpty)
        .toList();
    candidates.sort((a, b) {
      final titleA = normalizeMatchText(a.title);
      final titleB = normalizeMatchText(b.title);
      final queryText = normalizeMatchText(text);
      final exactA = titleA == queryText ? 1 : 0;
      final exactB = titleB == queryText ? 1 : 0;
      if (exactA != exactB) return exactB.compareTo(exactA);
      return (b.popularity ?? 0).compareTo(a.popularity ?? 0);
    });
    _log('manual TMDB search results=${candidates.length}');
    return candidates.take(40).toList(growable: false);
  }

  Future<TmdbSearchCandidate> _tvSearchCandidate(
      Map<String, dynamic> result) async {
    final id = (result['id'] as num?)?.toInt();
    String? tmdbType;
    var genres = const <String>[];
    if (id != null) {
      final details = await _getJsonOrNull('/tv/$id', const <String, String>{});
      tmdbType = details?['type'] as String?;
      if (details != null) genres = _genres(details);
    }
    return TmdbSearchCandidate.fromSearchJson(
      result,
      mediaType: 'tv',
      tmdbType: tmdbType,
      genres: genres,
    );
  }

  Future<TmdbSearchCandidate> _movieSearchCandidate(
      Map<String, dynamic> result) async {
    final id = (result['id'] as num?)?.toInt();
    var genres = const <String>[];
    if (id != null) {
      final details =
          await _getJsonOrNull('/movie/$id', const <String, String>{});
      if (details != null) genres = _genres(details);
    }
    return TmdbSearchCandidate.fromSearchJson(
      result,
      mediaType: 'movie',
      genres: genres,
    );
  }

  Future<Map<String, MediaMetadata>> lookupGroupByCandidate(
    MediaFolderGroup group,
    TmdbSearchCandidate candidate,
  ) {
    _log(
      'manual TMDB selected ${candidate.mediaType} id=${candidate.tmdbId} title="${candidate.title}" group="${group.title}"',
    );
    return candidate.isTv
        ? _lookupTvGroupById(group, candidate.tmdbId)
        : _lookupMovieGroupById(group, candidate.tmdbId);
  }

  Future<Map<String, MediaMetadata>> _lookupTvGroupFromCachedTitle(
      MediaFolderGroup group, MediaMetadata cachedTitle) async {
    final id = cachedTitle.tmdbId;
    final seasons = <int, Map<String, dynamic>?>{};
    for (final season
        in group.items.map(inferredSeasonNumber).whereType<int>().toSet()) {
      _log(
          'GET /tv/$id/season/$season for new episodes, title cache="${cachedTitle.title}"');
      seasons[season] = await _getSeasonJson(id, season, group.items);
    }
    return {
      for (final item in group.items)
        item.id: _tvMetadataFromCachedTitle(
          item,
          cachedTitle,
          seasons[inferredSeasonNumber(item)],
          _episodeFromSeason(
            seasons[inferredSeasonNumber(item)],
            inferredEpisodeNumber(item),
          ),
        ),
    };
  }

  Future<Map<String, MediaMetadata>> _lookupMultiGroup(
      MediaFolderGroup group, List<String> queries) async {
    for (final query in queries) {
      _log('GET /search/multi group="${group.title}" query="$query"');
      final results = await _getJsonList(
        '/search/multi',
        {
          'query': query,
          if (group.representative.matchYear != null)
            'year': '${group.representative.matchYear}',
        },
        kind: _TmdbEndpointKind.search,
      );
      _log('/search/multi group="${group.title}" results=${results.length}');
      final best = _bestMultiSearchResult(results, group.representative);
      final id = (best?['id'] as num?)?.toInt();
      final mediaType = best?['media_type'] as String?;
      if (id == null) continue;
      if (mediaType == 'movie') return _lookupMovieGroupById(group, id);
      if (mediaType == 'tv') return _lookupTvGroupById(group, id);
    }
    return {};
  }

  Future<Map<String, MediaMetadata>> _lookupTvGroup(
      MediaFolderGroup group, List<String> queries) async {
    for (final query in queries) {
      _log('GET /search/tv group="${group.title}" query="$query"');
      final results = await _getJsonList(
        '/search/tv',
        {
          'query': query,
          if (group.representative.matchYear != null)
            'first_air_date_year': '${group.representative.matchYear}',
        },
        kind: _TmdbEndpointKind.search,
      );
      final best =
          _bestSearchResult(results, group.representative, movie: false);
      final id = (best?['id'] as num?)?.toInt();
      if (id == null) continue;
      return _lookupTvGroupById(group, id);
    }
    return {};
  }

  Future<Map<String, MediaMetadata>> _lookupTvGroupById(
      MediaFolderGroup group, int id) async {
    _log('GET /tv/$id once for group="${group.title}"');
    final details = await _getJson(
      '/tv/$id',
      {'append_to_response': 'images,aggregate_credits'},
    );
    final seasons = <int, Map<String, dynamic>?>{};
    for (final season
        in group.items.map(inferredSeasonNumber).whereType<int>().toSet()) {
      _log('GET /tv/$id/season/$season once for group="${group.title}"');
      seasons[season] = await _getSeasonJson(id, season, group.items);
    }
    return {
      for (final item in group.items)
        item.id: _tvMetadata(
          item,
          details,
          seasons[inferredSeasonNumber(item)],
          _episodeFromSeason(
            seasons[inferredSeasonNumber(item)],
            inferredEpisodeNumber(item),
          ),
        ),
    };
  }

  Future<Map<String, MediaMetadata>> _lookupMovieGroupById(
      MediaFolderGroup group, int id) async {
    _log('GET /movie/$id once for group="${group.title}"');
    final details = await _getJson(
      '/movie/$id',
      {'append_to_response': 'images,credits'},
    );
    return {
      for (final item in group.items) item.id: _movieMetadata(item, details),
    };
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
        seasonDetails = await _getSeasonJson(id, season, [item]);
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

  Future<MediaMetadata?> _lookupMulti(
      MediaItem item, List<String> queries) async {
    for (final query in queries) {
      _log('GET /search/multi query="$query"');
      final results = await _getJsonList(
        '/search/multi',
        {
          'query': query,
          if (item.matchYear != null) 'year': '${item.matchYear}',
        },
        kind: _TmdbEndpointKind.search,
      );
      _log('/search/multi query="$query" results=${results.length}');
      final best = _bestMultiSearchResult(results, item);
      if (best == null) continue;
      final id = (best['id'] as num?)?.toInt();
      final mediaType = best['media_type'] as String?;
      if (id == null) continue;
      _log('selected multi id=$id type=$mediaType title=${_multiTitle(best)}');
      if (mediaType == 'movie') return _lookupMovieId(item, id);
      if (mediaType == 'tv') return _lookupTvId(item, id);
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
        seasonDetails = await _getSeasonJson(id, season, [item]);
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

  List<String> _multiQueriesFor(MediaItem item) {
    final values = <String>[
      mediaGroupDisplayTitle(item),
      item.matchTitle,
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

  Map<String, dynamic>? _bestMultiSearchResult(
      List<Map<String, dynamic>> results, MediaItem item) {
    final candidates = results
        .where((result) =>
            result['media_type'] == 'movie' || result['media_type'] == 'tv')
        .toList();
    if (candidates.isEmpty) return null;
    final target = normalizeMatchText(mediaGroupDisplayTitle(item));
    final parsedTarget = normalizeMatchText(
        item.matchTitle.isNotEmpty ? item.matchTitle : item.title);
    final basename = normalizeMatchText(item.title);
    Map<String, dynamic>? best;
    var bestScore = -1;

    for (final result in candidates.take(10)) {
      final title = normalizeMatchText(_multiTitle(result));
      final originalTitle = normalizeMatchText(_multiOriginalTitle(result));
      if (title.isEmpty && originalTitle.isEmpty) continue;
      var score = 0;
      if (title == target || originalTitle == target) score += 95;
      if (title == parsedTarget || originalTitle == parsedTarget) score += 90;
      if (title == basename || originalTitle == basename) score += 82;
      if (target.contains(title) || title.contains(target)) score += 35;
      if (parsedTarget.contains(title) || title.contains(parsedTarget)) {
        score += 32;
      }
      if (basename.contains(title) || title.contains(basename)) score += 30;
      if (result['poster_path'] != null) score += 8;
      if (result['backdrop_path'] != null) score += 4;
      final date = result['media_type'] == 'movie'
          ? result['release_date'] as String?
          : result['first_air_date'] as String?;
      if (item.matchYear != null &&
          date?.startsWith('${item.matchYear}') == true) {
        score += 18;
      }
      if (looksLikeSeriesItem(item) && result['media_type'] == 'tv') {
        score += 10;
      }
      if (item.mediaKind == 'Movie' && result['media_type'] == 'movie') {
        score += 10;
      }
      score += ((result['vote_count'] as num?)?.toInt() ?? 0).clamp(0, 20);

      if (score > bestScore) {
        bestScore = score;
        best = result;
      }
    }
    return best ?? candidates.first;
  }

  String _multiTitle(Map<String, dynamic> result) {
    return result['media_type'] == 'movie'
        ? result['title'] as String? ?? ''
        : result['name'] as String? ?? '';
  }

  String _multiOriginalTitle(Map<String, dynamic> result) {
    return result['media_type'] == 'movie'
        ? result['original_title'] as String? ?? ''
        : result['original_name'] as String? ?? '';
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

  Future<Map<String, dynamic>?> _getSeasonJson(
      int tvId, int season, Iterable<MediaItem> localItems) async {
    final localEpisodes =
        localItems.map(inferredEpisodeNumber).whereType<int>().toSet();
    final languages = <String>[
      config.language,
      'zh-CN',
      'en-US',
      '',
    ].where((value) => value.trim().isNotEmpty).fold<List<String>>(
      [],
      (acc, value) {
        if (!acc.contains(value)) acc.add(value);
        return acc;
      },
    );
    Map<String, dynamic>? fallback;
    for (final language in languages) {
      final json = await _getJsonOrNull(
        '/tv/$tvId/season/$season',
        {'language': language},
      );
      if (json == null) continue;
      fallback ??= json;
      final episodes = json['episodes'] as List<dynamic>? ?? const [];
      final useful = episodes.whereType<Map<String, dynamic>>().any((episode) {
        final number = (episode['episode_number'] as num?)?.toInt();
        if (number == null || !localEpisodes.contains(number)) return false;
        final name = (episode['name'] as String?)?.trim() ?? '';
        final still = (episode['still_path'] as String?)?.trim() ?? '';
        return name.isNotEmpty || still.isNotEmpty;
      });
      if (useful) return json;
    }
    return fallback;
  }

  List<Map<String, dynamic>> _seasonEpisodes(Map<String, dynamic>? seasonJson) {
    final seasonNumber = (seasonJson?['season_number'] as num?)?.toInt();
    final episodes = seasonJson?['episodes'] as List<dynamic>? ?? const [];
    return episodes
        .whereType<Map<String, dynamic>>()
        .map((episode) {
          final episodeNumber = (episode['episode_number'] as num?)?.toInt();
          if (episodeNumber == null) return null;
          return <String, dynamic>{
            if ((episode['id'] as num?) != null)
              'episodeTmdbId': (episode['id'] as num).toInt(),
            if (seasonNumber != null) 'seasonNumber': seasonNumber,
            'episodeNumber': episodeNumber,
            if (episode['name'] != null) 'episodeName': episode['name'],
            if (episode['overview'] != null)
              'episodeOverview': episode['overview'],
            if (episode['air_date'] != null) 'releaseDate': episode['air_date'],
            if ((episode['runtime'] as num?) != null)
              'episodeRuntime': (episode['runtime'] as num).toInt(),
            if (episode['still_path'] != null)
              'stillPath': episode['still_path'],
            if (episode['episode_type'] != null)
              'episodeType': episode['episode_type'],
            if ((episode['vote_average'] as num?) != null)
              'voteAverage': (episode['vote_average'] as num).toDouble(),
            if ((episode['vote_count'] as num?) != null)
              'episodeVoteCount': (episode['vote_count'] as num).toInt(),
          };
        })
        .whereType<Map<String, dynamic>>()
        .toList();
  }

  List<Map<String, dynamic>> _showSeasons(Map<String, dynamic> showJson) {
    final seasons = showJson['seasons'] as List<dynamic>? ?? const [];
    return seasons
        .whereType<Map<String, dynamic>>()
        .map((season) {
          final seasonNumber = (season['season_number'] as num?)?.toInt();
          if (seasonNumber == null) return null;
          return <String, dynamic>{
            if ((season['id'] as num?) != null)
              'seasonTmdbId': (season['id'] as num).toInt(),
            'seasonNumber': seasonNumber,
            if (season['name'] != null) 'seasonName': season['name'],
            if (season['overview'] != null)
              'seasonOverview': season['overview'],
            if (season['air_date'] != null) 'seasonAirDate': season['air_date'],
            if ((season['episode_count'] as num?) != null)
              'seasonEpisodeCount': (season['episode_count'] as num).toInt(),
            if (season['poster_path'] != null)
              'seasonPosterPath': season['poster_path'],
            if ((season['vote_average'] as num?) != null)
              'seasonVoteAverage': (season['vote_average'] as num).toDouble(),
          };
        })
        .whereType<Map<String, dynamic>>()
        .toList();
  }

  MediaMetadata _tvMetadataFromCachedTitle(MediaItem item, MediaMetadata title,
      Map<String, dynamic>? seasonJson, Map<String, dynamic>? episodeJson) {
    final episode = episodeJson?.isEmpty == true ? null : episodeJson;
    return MediaMetadata(
      itemId: item.id,
      tmdbId: title.tmdbId,
      mediaType: title.mediaType,
      title: title.title,
      tmdbType: title.tmdbType,
      originalTitle: title.originalTitle,
      overview: title.overview,
      posterPath: title.posterPath,
      backdropPath: title.backdropPath,
      stillPath: episode?['still_path'] as String?,
      logoPath: title.logoPath,
      profilePaths: title.profilePaths,
      castNames: title.castNames,
      genres: title.genres,
      releaseDate: episode?['air_date'] as String? ?? title.releaseDate,
      voteAverage:
          (episode?['vote_average'] as num?)?.toDouble() ?? title.voteAverage,
      totalSeasons: title.totalSeasons,
      totalEpisodes: title.totalEpisodes,
      showSeasons: title.showSeasons,
      seasonTmdbId: (seasonJson?['id'] as num?)?.toInt(),
      seasonName: seasonJson?['name'] as String?,
      seasonOverview: seasonJson?['overview'] as String?,
      seasonAirDate: seasonJson?['air_date'] as String?,
      seasonEpisodeCount: (seasonJson?['episodes'] as List<dynamic>?)?.length,
      seasonPosterPath: seasonJson?['poster_path'] as String?,
      seasonEpisodes: _seasonEpisodes(seasonJson),
      episodeTmdbId: (episode?['id'] as num?)?.toInt(),
      episodeName: episode?['name'] as String?,
      episodeOverview: episode?['overview'] as String?,
      episodeRuntime: (episode?['runtime'] as num?)?.toInt(),
      episodeType: episode?['episode_type'] as String?,
      episodeVoteCount: (episode?['vote_count'] as num?)?.toInt(),
      updatedAt: DateTime.now().millisecondsSinceEpoch,
      schemaVersion: currentMetadataSchemaVersion,
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
      tmdbType: json['type'] as String?,
      originalTitle: json['name'] as String?,
      overview: json['overview'] as String?,
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
      showSeasons: _showSeasons(json),
      seasonTmdbId: (seasonJson?['id'] as num?)?.toInt(),
      seasonName: seasonJson?['name'] as String?,
      seasonOverview: seasonJson?['overview'] as String?,
      seasonAirDate: seasonJson?['air_date'] as String?,
      seasonEpisodeCount: (seasonJson?['episodes'] as List<dynamic>?)?.length,
      seasonPosterPath: seasonJson?['poster_path'] as String?,
      seasonEpisodes: _seasonEpisodes(seasonJson),
      episodeTmdbId: (episode?['id'] as num?)?.toInt(),
      episodeName: episode?['name'] as String?,
      episodeOverview: episode?['overview'] as String?,
      episodeRuntime: (episode?['runtime'] as num?)?.toInt(),
      episodeType: episode?['episode_type'] as String?,
      episodeVoteCount: (episode?['vote_count'] as num?)?.toInt(),
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
    _log('Rust reqwest request on worker isolate host=${uri.host}');
    final body = await RustCoreService.instance.tmdbGetJsonAsync(
      uri.toString(),
      config.accessToken.trim(),
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
}
