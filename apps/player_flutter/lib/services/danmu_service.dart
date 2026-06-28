part of 'package:player_flutter/main.dart';

class DanmuService {
  const DanmuService(this.config, {this.log});

  final DanmuConfig config;
  final void Function(String message)? log;

  Future<RustDanmuLoadResult> loadSession({
    required String title,
    required List<String> fileNames,
    int? season,
    int? episode,
    String? episodeId,
    String? episodeTitle,
  }) async {
    final baseUrl = config.requestBaseUrl;
    if (!config.available || baseUrl.isEmpty) {
      return const RustDanmuLoadResult(
        sessionId: 0,
        count: 0,
        matchedEpisodeId: '',
        matchedTitle: '',
        matchedEpisode: '',
        logs: [],
      );
    }
    _log(
      'danmu load start: base=$baseUrl title=$title S$season E$episode episodeId=${episodeId?.trim() ?? ''} candidates=${jsonEncode(fileNames)} matchBodies=${jsonEncode(fileNames.map((name) => {
            'fileName': name
          }).toList())}',
    );
    final result = await RustCoreService.instance.danmuLoadAsync({
      'base_url': baseUrl,
      'title': title,
      'file_names': fileNames,
      if (season != null) 'season': season,
      if (episode != null) 'episode': episode,
      if (episodeId?.trim().isNotEmpty == true) 'episode_id': episodeId!.trim(),
      if (episodeTitle?.trim().isNotEmpty == true)
        'episode_title': episodeTitle!.trim(),
    });
    for (final line in result.logs) {
      _log(line);
    }
    _log(
      'danmu rust load finished: session=${result.sessionId} count=${result.count} episodeId=${result.matchedEpisodeId}',
    );
    return result;
  }

  Future<List<DanmuSearchResult>> search(String keyword, {int? episode}) async {
    final query = keyword.trim();
    final baseUrl = config.requestBaseUrl;
    if (!config.available || baseUrl.isEmpty || query.isEmpty) {
      return const [];
    }
    final params = <String, String>{'anime': query};
    if (episode != null && episode > 0) params['episode'] = '$episode';
    final searchUri = Uri.parse('$baseUrl/api/v2/search/episodes')
        .replace(queryParameters: params);
    _log('danmu manual episode search: $searchUri');
    final searchResponse =
        await http.get(searchUri, headers: {'accept': 'application/json'});
    _log(
      'danmu manual episode response: status=${searchResponse.statusCode} body=${_shortLogBody(searchResponse.body)}',
    );
    if (searchResponse.statusCode < 200 || searchResponse.statusCode >= 300) {
      throw StateError('搜索失败：HTTP ${searchResponse.statusCode}');
    }
    final searchJson = jsonDecode(searchResponse.body);
    final episodeResults = _extractSearchEpisodeResults(
      searchJson,
      fallbackAnimeTitle: query,
      fallbackEpisodeNumber: episode,
    );
    if (episodeResults.isNotEmpty) {
      _log('danmu manual episode results=${episodeResults.length}');
      return _sortDanmuSearchResults(
        episodeResults,
        preferredEpisode: episode,
      );
    }

    final animeSearchUri = Uri.parse('$baseUrl/api/v2/search/anime')
        .replace(queryParameters: {'keyword': query});
    _log('danmu manual anime fallback: $animeSearchUri');
    final animeSearchResponse =
        await http.get(animeSearchUri, headers: {'accept': 'application/json'});
    _log(
      'danmu manual anime response: status=${animeSearchResponse.statusCode} body=${_shortLogBody(animeSearchResponse.body)}',
    );
    if (animeSearchResponse.statusCode < 200 ||
        animeSearchResponse.statusCode >= 300) {
      return const [];
    }
    final animeSearchJson = jsonDecode(animeSearchResponse.body);
    final animes = _extractAnimeItems(animeSearchJson);
    final results = <DanmuSearchResult>[];
    for (final anime in animes.take(12)) {
      final animeId = _stringValue(anime, const [
        'animeId',
        'id',
        'bangumiId',
      ]);
      if (animeId.isEmpty) continue;
      final animeTitle = _stringValue(anime, const [
        'animeTitle',
        'title',
        'name',
        'animeName',
      ]);
      final animeType = _stringValue(anime, const ['type']);
      final animeTypeDescription =
          _stringValue(anime, const ['typeDescription']);
      final bangumiUri = Uri.parse('$baseUrl/api/v2/bangumi/$animeId');
      _log('danmu manual bangumi: $bangumiUri');
      final bangumiResponse =
          await http.get(bangumiUri, headers: {'accept': 'application/json'});
      _log(
        'danmu manual bangumi response: animeId=$animeId status=${bangumiResponse.statusCode} body=${_shortLogBody(bangumiResponse.body)}',
      );
      if (bangumiResponse.statusCode < 200 ||
          bangumiResponse.statusCode >= 300) {
        continue;
      }
      final bangumiJson = jsonDecode(bangumiResponse.body);
      final episodes = _extractEpisodeItems(bangumiJson);
      for (final episode in episodes) {
        final episodeId = _stringValue(episode, const [
          'episodeId',
          'id',
          'commentId',
        ]);
        if (episodeId.isEmpty) continue;
        final episodeTitle = _stringValue(episode, const [
          'episodeTitle',
          'title',
          'name',
          'episodeName',
        ]);
        final episodeNumber = _intValue(episode, const [
          'episode',
          'episodeNumber',
          'sort',
          'index',
        ]);
        results.add(DanmuSearchResult(
          animeId: animeId,
          animeTitle: animeTitle.isEmpty ? query : animeTitle,
          episodeId: episodeId,
          episodeTitle: episodeTitle,
          episodeNumber: episodeNumber,
          type: animeType,
          typeDescription: animeTypeDescription,
        ));
      }
    }
    _log('danmu manual search results=${results.length}');
    return _sortDanmuSearchResults(results, preferredEpisode: episode);
  }

  void _log(String message) {
    log?.call(message);
  }
}

String _shortLogBody(String body) {
  const limit = 2000;
  if (body.length <= limit) return body;
  return '${body.substring(0, limit)}...<truncated ${body.length - limit} chars>';
}

class DanmuSearchResult {
  const DanmuSearchResult({
    required this.animeId,
    required this.animeTitle,
    required this.episodeId,
    required this.episodeTitle,
    this.episodeNumber,
    this.type = '',
    this.typeDescription = '',
  });

  final String animeId;
  final String animeTitle;
  final String episodeId;
  final String episodeTitle;
  final int? episodeNumber;
  final String type;
  final String typeDescription;

  String get displayTitle {
    final parts = <String>[animeTitle];
    if (episodeNumber != null) parts.add('第 $episodeNumber 集');
    if (episodeTitle.trim().isNotEmpty) parts.add(episodeTitle.trim());
    return parts.join(' · ');
  }
}

List<Map<String, dynamic>> _extractAnimeItems(dynamic json) {
  final root = _asMap(json);
  final data = _asMap(root['data']);
  for (final owner in [root, data]) {
    for (final key in const [
      'animes',
      'anime',
      'bangumi',
      'items',
      'results',
      'result',
      'list',
      'data',
    ]) {
      final items = owner[key];
      if (items is List) {
        return items.whereType<Map<String, dynamic>>().toList();
      }
    }
  }
  if (json is List) return json.whereType<Map<String, dynamic>>().toList();
  return const [];
}

List<Map<String, dynamic>> _extractEpisodeItems(dynamic json) {
  final root = _asMap(json);
  final data = _asMap(root['data']);
  final bangumi = _asMap(root['bangumi']);
  for (final owner in [root, data, bangumi]) {
    for (final key in const [
      'episodes',
      'episodeList',
      'items',
      'results',
      'result',
      'list',
      'data',
    ]) {
      final items = owner[key];
      if (items is List) {
        return items.whereType<Map<String, dynamic>>().toList();
      }
    }
  }
  return const [];
}

List<DanmuSearchResult> _extractSearchEpisodeResults(
  dynamic json, {
  required String fallbackAnimeTitle,
  int? fallbackEpisodeNumber,
}) {
  final root = _asMap(json);
  final rawAnimes = _extractAnimeItems(json);
  final results = <String, DanmuSearchResult>{};

  void addEpisode(
    Map<String, dynamic> episode,
    Map<String, dynamic> anime, {
    int? fallbackEpisodeNumber,
  }) {
    final episodeId = _stringValue(episode, const [
      'episodeId',
      'commentId',
      'id',
    ]);
    if (episodeId.isEmpty) return;
    final animeId = _stringValue(anime, const [
      'animeId',
      'bangumiId',
      'id',
    ]);
    final animeTitle = _stringValue(anime, const [
      'animeTitle',
      'title',
      'name',
      'animeName',
    ]);
    final animeType = _stringValue(anime, const ['type']);
    final animeTypeDescription = _stringValue(anime, const ['typeDescription']);
    final episodeTitle = _stringValue(episode, const [
      'episodeTitle',
      'title',
      'name',
      'episodeName',
    ]);
    final episodeNumber = _intValue(episode, const [
          'episodeNumber',
          'episode',
          'sort',
          'index',
        ]) ??
        fallbackEpisodeNumber;
    results[episodeId] = DanmuSearchResult(
      animeId: animeId,
      animeTitle: animeTitle.isEmpty ? fallbackAnimeTitle : animeTitle,
      episodeId: episodeId,
      episodeTitle: episodeTitle,
      episodeNumber: episodeNumber,
      type: animeType,
      typeDescription: animeTypeDescription,
    );
  }

  for (final anime in rawAnimes) {
    final episodes = _extractEpisodeItems(anime);
    for (var index = 0; index < episodes.length; index++) {
      addEpisode(
        episodes[index],
        anime,
        fallbackEpisodeNumber: fallbackEpisodeNumber ?? index + 1,
      );
    }
  }
  final rootEpisodes = _extractEpisodeItems(root);
  for (var index = 0; index < rootEpisodes.length; index++) {
    addEpisode(
      rootEpisodes[index],
      root,
      fallbackEpisodeNumber: fallbackEpisodeNumber ?? index + 1,
    );
  }
  if (json is List) {
    for (var itemIndex = 0; itemIndex < json.length; itemIndex++) {
      final item = json[itemIndex];
      if (item is! Map<String, dynamic>) continue;
      final episodes = _extractEpisodeItems(item);
      if (episodes.isEmpty) {
        addEpisode(
          item,
          item,
          fallbackEpisodeNumber: fallbackEpisodeNumber ?? itemIndex + 1,
        );
      } else {
        for (var index = 0; index < episodes.length; index++) {
          addEpisode(
            episodes[index],
            item,
            fallbackEpisodeNumber: fallbackEpisodeNumber ?? index + 1,
          );
        }
      }
    }
  }

  return _sortDanmuSearchResults(
    results.values.toList(growable: false),
    preferredEpisode: fallbackEpisodeNumber,
  );
}

List<DanmuSearchResult> _sortDanmuSearchResults(
  List<DanmuSearchResult> results, {
  int? preferredEpisode,
}) {
  final sorted = List<DanmuSearchResult>.of(results);
  sorted.sort((a, b) {
    final episodeCompare = _episodeDistance(a.episodeNumber, preferredEpisode)
        .compareTo(_episodeDistance(b.episodeNumber, preferredEpisode));
    if (episodeCompare != 0) return episodeCompare;
    final typeCompare =
        _danmuResultTypePriority(a).compareTo(_danmuResultTypePriority(b));
    if (typeCompare != 0) return typeCompare;
    return a.displayTitle.compareTo(b.displayTitle);
  });
  return sorted;
}

int _episodeDistance(int? episode, int? preferredEpisode) {
  if (preferredEpisode == null || episode == null) return 0;
  return (episode - preferredEpisode).abs();
}

int _danmuResultTypePriority(DanmuSearchResult result) {
  final text = '${result.type}${result.typeDescription}${result.animeTitle}';
  if (text.contains('电影') || text.contains('電影') || text.contains('鐢靛奖')) {
    return 3;
  }
  if (text.contains('剧') ||
      text.contains('劇') ||
      text.contains('鍓') ||
      text.contains('番') ||
      text.contains('动漫') ||
      text.contains('動')) {
    return 0;
  }
  return 1;
}

Map<String, dynamic> _asMap(dynamic value) =>
    value is Map<String, dynamic> ? value : const {};

String _stringValue(Map<String, dynamic> json, List<String> keys) {
  for (final key in keys) {
    final value = json[key];
    if (value == null) continue;
    final text = value.toString().trim();
    if (text.isNotEmpty) return text;
  }
  return '';
}

int? _intValue(Map<String, dynamic> json, List<String> keys) {
  for (final key in keys) {
    final value = json[key];
    if (value is num) return value.toInt();
    if (value is String) {
      final parsed = int.tryParse(value);
      if (parsed != null) return parsed;
    }
  }
  return null;
}

List<String> buildDanmuMatchFileNames({
  required String title,
  required String sourceFileName,
  int? season,
  int? episode,
}) {
  final raw = sourceFileName.trim();
  if (title.trim().isEmpty || season == null || episode == null) {
    return [if (raw.isNotEmpty) raw else title.trim()];
  }
  final safeTitle = title.trim().replaceAll(RegExp(r'[\\/:*?"<>|]+'), ' ');
  if (safeTitle.isEmpty) return [if (raw.isNotEmpty) raw else title.trim()];
  final marker =
      'S${season.toString().padLeft(2, '0')}E${episode.toString().padLeft(2, '0')}';
  final candidates = <String>[
    '$safeTitle.$marker',
    if (raw.isNotEmpty) raw,
  ];
  return LinkedHashSet<String>.of(candidates.map((value) => value.trim()))
      .where((value) => value.isNotEmpty)
      .toList(growable: false);
}

String buildDanmuMatchFileName({
  required String title,
  required String sourceFileName,
  int? season,
  int? episode,
}) {
  return buildDanmuMatchFileNames(
    title: title,
    sourceFileName: sourceFileName,
    season: season,
    episode: episode,
  ).first;
}
