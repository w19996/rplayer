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
      'danmu load start: base=$baseUrl title=$title S$season E$episode candidates=${jsonEncode(fileNames)} matchBodies=${jsonEncode(fileNames.map((name) => {
            'fileName': name
          }).toList())}',
    );
    final result = await RustCoreService.instance.danmuLoadAsync({
      'base_url': baseUrl,
      'title': title,
      'file_names': fileNames,
      if (season != null) 'season': season,
      if (episode != null) 'episode': episode,
    });
    for (final line in result.logs) {
      _log(line);
    }
    _log(
      'danmu rust load finished: session=${result.sessionId} count=${result.count} episodeId=${result.matchedEpisodeId}',
    );
    return result;
  }

  void _log(String message) {
    log?.call(message);
  }
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
