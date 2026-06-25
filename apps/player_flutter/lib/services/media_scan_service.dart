part of 'package:player_flutter/main.dart';

class MediaScanService {
  const MediaScanService();

  Future<List<MediaItem>> scanSource(MediaSourceConfig source) {
    return scanSourceStream(source).toList();
  }

  Stream<MediaItem> scanSourceStream(MediaSourceConfig source) {
    return source.type == SourceType.local
        ? scanLocalDirectoryStream(source)
        : scanWebdavSelectionsStream(source);
  }

  Future<List<MediaItem>> scanLocalDirectory(MediaSourceConfig source) async {
    return scanLocalDirectoryStream(source).toList();
  }

  Stream<MediaItem> scanLocalDirectoryStream(MediaSourceConfig source) async* {
    for (final path in source.selectedPaths) {
      yield* scanLocalPathStream(source, path);
    }
  }

  Future<List<MediaItem>> scanLocalPath(
      MediaSourceConfig source, String path) async {
    return scanLocalPathStream(source, path).toList();
  }

  Stream<MediaItem> scanLocalPathStream(
      MediaSourceConfig source, String path) async* {
    final file = File(path);
    if (await file.exists()) {
      if (isVideoName(path)) {
        yield MediaItem.local(
          source: source,
          path: path,
          size: await file.length(),
        );
      }
      return;
    }

    final dir = Directory(path);
    if (!await dir.exists()) return;

    await for (final entity in dir.list(recursive: true, followLinks: false)) {
      if (entity is! File || !isVideoName(entity.path)) continue;
      yield MediaItem.local(
        source: source,
        path: entity.path,
        size: await entity.length(),
      );
    }
  }

  Future<List<MediaItem>> scanWebdavSelections(MediaSourceConfig source) async {
    return scanWebdavSelectionsStream(source).toList();
  }

  Stream<MediaItem> scanWebdavSelectionsStream(
      MediaSourceConfig source) async* {
    final client = WebdavClient.fromSource(source);
    for (final path in source.selectedPaths) {
      if (path.endsWith('/')) {
        await for (final entry in client.scanVideosStream(path, maxDepth: 8)) {
          yield MediaItem.webdav(source: source, entry: entry);
        }
      } else if (isVideoName(path)) {
        final entry = await client.findFile(path);
        if (entry != null) {
          yield MediaItem.webdav(source: source, entry: entry);
        }
      }
    }
  }
}
