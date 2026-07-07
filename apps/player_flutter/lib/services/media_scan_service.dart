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
      if (!isVideoName(path)) return;
      final items = await _localVideoSeedsToItems(source, [
        _LocalVideoSeed(path, await file.length()),
      ]);
      for (final item in items) {
        yield item;
      }
      return;
    }

    final dir = Directory(path);
    if (!await dir.exists()) return;

    final chunk = <_LocalVideoSeed>[];

    Future<List<MediaItem>> flushChunk() async {
      if (chunk.isEmpty) return const [];
      final seeds = List<_LocalVideoSeed>.of(chunk);
      chunk.clear();
      return _localVideoSeedsToItems(source, seeds);
    }

    await for (final entity in dir.list(recursive: true, followLinks: false)) {
      if (entity is! File || !isVideoName(entity.path)) continue;
      chunk.add(_LocalVideoSeed(entity.path, await entity.length()));
      if (chunk.length >= 100) {
        for (final item in await flushChunk()) {
          yield item;
        }
        await Future<void>.delayed(Duration.zero);
      }
    }
    for (final item in await flushChunk()) {
      yield item;
    }
  }

  Future<List<MediaItem>> scanLocalPathItemsAsync(
      MediaSourceConfig source, String path) {
    return scanLocalPathStream(source, path).toList();
  }

  Future<List<MediaItem>> _localVideoSeedsToItems(
    MediaSourceConfig source,
    List<_LocalVideoSeed> seeds,
  ) {
    return Isolate.run(() => _localVideoSeedsToItemsWorker(source, seeds));
  }

  Future<List<MediaItem>> scanWebdavSelections(MediaSourceConfig source) async {
    return scanWebdavSelectionsStream(source).toList();
  }

  Stream<MediaItem> scanWebdavSelectionsStream(
      MediaSourceConfig source) async* {
    final client = remoteClientForSource(source);
    final chunk = <WebdavEntry>[];

    Future<List<MediaItem>> flushChunk() async {
      if (chunk.isEmpty) return const [];
      final entries = List<WebdavEntry>.of(chunk);
      chunk.clear();
      return Isolate.run(() => _webdavEntriesToItemsWorker(source, entries));
    }

    for (final path in source.selectedPaths) {
      if (path.endsWith('/')) {
        await for (final entry in client.scanVideosStream(path, maxDepth: 8)) {
          chunk.add(entry);
          if (chunk.length >= 100) {
            for (final item in await flushChunk()) {
              yield item;
            }
            await Future<void>.delayed(Duration.zero);
          }
        }
      } else if (isVideoName(path)) {
        final entry = await client.findFile(path);
        if (entry != null) {
          chunk.add(entry);
        }
      }
    }
    for (final item in await flushChunk()) {
      yield item;
    }
  }
}

class _LocalVideoSeed {
  const _LocalVideoSeed(this.path, this.size);

  final String path;
  final int size;
}

List<MediaItem> _localVideoSeedsToItemsWorker(
  MediaSourceConfig source,
  List<_LocalVideoSeed> seeds,
) {
  return seeds
      .map(
        (seed) => MediaItem.local(
          source: source,
          path: seed.path,
          size: seed.size,
        ),
      )
      .map((item) => applyManualSeriesPath(source, item))
      .toList(growable: false);
}

List<MediaItem> _webdavEntriesToItemsWorker(
  MediaSourceConfig source,
  List<WebdavEntry> entries,
) {
  return entries
      .map((entry) => MediaItem.remote(source: source, entry: entry))
      .map((item) => applyManualSeriesPath(source, item))
      .toList(growable: false);
}
