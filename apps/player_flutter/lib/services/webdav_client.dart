part of 'package:player_flutter/main.dart';

class WebdavClient {
  const WebdavClient(this.source);

  factory WebdavClient.fromSource(MediaSourceConfig source) =>
      WebdavClient(source);

  factory WebdavClient.fromSync(SyncConfig config) =>
      WebdavClient(config.asSource());

  final MediaSourceConfig source;

  Future<List<WebdavEntry>> scanVideos(String path,
      {required int maxDepth}) async {
    return scanVideosStream(path, maxDepth: maxDepth).toList();
  }

  Stream<WebdavEntry> scanVideosStream(String path,
      {required int maxDepth}) async* {
    Stream<WebdavEntry> walk(String current, int depth) async* {
      final entries = await list(current);
      for (final entry in entries) {
        if (entry.isDir && depth < maxDepth) {
          yield* walk(entry.path, depth + 1);
        } else if (!entry.isDir && isVideoName(entry.name)) {
          yield entry;
        }
      }
    }

    yield* walk(path, 0);
  }

  Future<WebdavEntry?> findFile(String path) async {
    final parent = parentPath(path);
    final name = Uri.decodeComponent(
        path.split('/').where((part) => part.isNotEmpty).lastOrNull ?? path);
    final entries = await list(parent);
    for (final entry in entries) {
      if (!entry.isDir && (entry.path == path || entry.name == name)) {
        return entry;
      }
    }
    return null;
  }

  Future<List<WebdavEntry>> list(String path) async {
    final uri = source.resolve(path);
    final request = http.Request('PROPFIND', uri)
      ..headers.addAll(source.headers)
      ..headers['Depth'] = '1'
      ..headers['Content-Type'] = 'application/xml'
      ..body = '''<?xml version="1.0" encoding="utf-8" ?>
<d:propfind xmlns:d="DAV:">
  <d:prop>
    <d:resourcetype/>
    <d:getcontentlength/>
    <d:displayname/>
  </d:prop>
</d:propfind>''';
    final streamed = await request.send();
    final body = await streamed.stream.bytesToString();
    if (streamed.statusCode < 200 || streamed.statusCode >= 300) {
      throw Exception('WebDAV ${streamed.statusCode}: $body');
    }
    return parseWebdavEntries(body, source, uri, path);
  }

  Future<void> putText(String path, String text) async {
    final response = await http.put(source.resolve(path),
        headers: source.headers, body: text);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('WebDAV ${response.statusCode}: ${response.body}');
    }
  }

  Future<void> putBytes(String path, List<int> bytes) async {
    final response = await http.put(source.resolve(path),
        headers: source.headers, body: bytes);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('WebDAV ${response.statusCode}: ${response.body}');
    }
  }

  Future<void> ensureParentCollections(String filePath) async {
    final normalized = filePath.startsWith('/') ? filePath : '/$filePath';
    final parts =
        normalized.split('/').where((part) => part.isNotEmpty).toList();
    if (parts.length <= 1) return;

    var current = '';
    for (final part in parts.take(parts.length - 1)) {
      current = '$current/$part';
      final request = http.Request('MKCOL', source.resolve('$current/'))
        ..headers.addAll(source.headers);
      final streamed = await request.send();
      if (streamed.statusCode == 405) continue;
      if (streamed.statusCode < 200 || streamed.statusCode >= 300) {
        final body = await streamed.stream.bytesToString();
        throw Exception('WebDAV ${streamed.statusCode}: $body');
      }
    }
  }

  Future<String> getText(String path) async {
    final response =
        await http.get(source.resolve(path), headers: source.headers);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('WebDAV ${response.statusCode}: ${response.body}');
    }
    return response.body;
  }

  Future<List<int>> getBytes(String path) async {
    final response =
        await http.get(source.resolve(path), headers: source.headers);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('WebDAV ${response.statusCode}: ${response.body}');
    }
    return response.bodyBytes;
  }
}

List<WebdavEntry> parseWebdavEntries(
    String body, MediaSourceConfig source, Uri requestUri, String currentPath) {
  return RustCoreService.instance.parseWebdavEntries(
    body: body,
    baseUrl: source.baseUrl,
    requestUrl: requestUri.toString(),
    currentPath: currentPath,
  );
}

extension FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
