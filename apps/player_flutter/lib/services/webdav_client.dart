part of 'package:player_flutter/main.dart';

abstract class RemoteFileClient {
  Stream<WebdavEntry> scanVideosStream(String path, {required int maxDepth});
  Future<WebdavEntry?> findFile(String path);
  Future<List<WebdavEntry>> list(String path);
  Future<RemotePlayback> playback(MediaItem item);
}

RemoteFileClient remoteClientForSource(MediaSourceConfig source) =>
    source.type == SourceType.openlist
        ? OpenlistClient.fromSource(source)
        : WebdavClient.fromSource(source);

class RemotePlayback {
  const RemotePlayback(this.uri, this.headers, {this.mimeType});

  final String uri;
  final Map<String, String> headers;
  final String? mimeType;
}

Future<RemotePlayback> playbackForItem(AppStore store, MediaItem item) async {
  MediaSourceConfig? source;
  for (final candidate in store.sources) {
    if (candidate.id == item.sourceId) {
      source = candidate;
      break;
    }
  }
  if (source != null && isRemoteSourceType(item.type)) {
    return remoteClientForSource(source).playback(item);
  }
  final uri = Uri.tryParse(item.uri);
  if (uri != null && (uri.scheme == 'http' || uri.scheme == 'https')) {
    return RemotePlayback(item.uri, const {});
  }
  return RemotePlayback(Uri.file(item.uri).toString(), const {});
}

class WebdavClient implements RemoteFileClient {
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

  @override
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

  @override
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

  @override
  Future<RemotePlayback> playback(MediaItem item) async {
    return RemotePlayback(item.uri, source.headers);
  }

  @override
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

  Future<void> putFile(
    String path,
    File file, {
    void Function(int sent, int total)? onProgress,
  }) async {
    final total = await file.length();
    final request = http.StreamedRequest('PUT', source.resolve(path))
      ..headers.addAll(source.headers)
      ..contentLength = total;
    var sent = 0;
    onProgress?.call(sent, total);
    final responseFuture = request.send();
    await request.sink.addStream(file.openRead().map((chunk) {
      sent += chunk.length;
      onProgress?.call(sent, total);
      return chunk;
    }));
    await request.sink.close();
    final response = await responseFuture;
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final body = await response.stream.bytesToString();
      throw Exception('WebDAV ${response.statusCode}: $body');
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

  Future<void> getFile(
    String path,
    File file, {
    void Function(int received, int total)? onProgress,
  }) async {
    if (!await file.parent.exists()) await file.parent.create(recursive: true);
    final request = http.Request('GET', source.resolve(path))
      ..headers.addAll(source.headers);
    final response = await request.send();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final body = await response.stream.bytesToString();
      throw Exception('WebDAV ${response.statusCode}: $body');
    }
    final total = response.contentLength ?? -1;
    var received = 0;
    onProgress?.call(received, total);
    final sink = file.openWrite();
    try {
      await for (final chunk in response.stream) {
        received += chunk.length;
        sink.add(chunk);
        onProgress?.call(received, total);
      }
    } finally {
      await sink.close();
    }
  }
}

class OpenlistClient implements RemoteFileClient {
  OpenlistClient(this.source);

  factory OpenlistClient.fromSource(MediaSourceConfig source) =>
      OpenlistClient(source);

  final MediaSourceConfig source;
  String? _token;

  Uri _api(String path) {
    final base = source.baseUrl.endsWith('/')
        ? source.baseUrl.substring(0, source.baseUrl.length - 1)
        : source.baseUrl;
    return Uri.parse('$base$path');
  }

  Future<Map<String, String>> _headers() async {
    final headers = {'Content-Type': 'application/json'};
    if (source.username.isEmpty && source.password.isEmpty) return headers;
    _token ??= await _login();
    return {...headers, 'Authorization': _token!};
  }

  Future<String> _login() async {
    final response = await http.post(
      _api('/api/auth/login'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'username': source.username,
        'password': source.password,
        'otp_code': source.otpCode,
      }),
    );
    final data = _openlistJson(response, 'OpenList login');
    final token = (data['data'] as Map?)?['token'] as String?;
    if (token == null || token.isEmpty) {
      throw Exception('OpenList login failed: missing token');
    }
    return token;
  }

  Future<Map<String, dynamic>> _post(
      String path, Map<String, dynamic> body) async {
    final response = await http.post(
      _api(path),
      headers: await _headers(),
      body: jsonEncode(body),
    );
    return _openlistJson(response, 'OpenList $path');
  }

  @override
  Future<List<WebdavEntry>> list(String path) async {
    final normalized = normalizeRemoteDir(path);
    final json = await _post('/api/fs/list', {
      'path': normalized,
      'password': '',
      'page': 1,
      'per_page': 0,
      'refresh': false,
    });
    final data = json['data'] as Map? ?? const {};
    final content = data['content'] as List? ?? const [];
    return content
        .whereType<Map>()
        .map((entry) => _entry(normalized, entry))
        .toList(growable: false);
  }

  WebdavEntry _entry(String parent, Map entry) {
    final name = entry['name'] as String? ?? '';
    final isDir = entry['is_dir'] == true;
    final path = _joinRemote(parent, name, isDir: isDir);
    final sign = entry['sign'] as String? ?? '';
    return WebdavEntry(
      name: name,
      path: path,
      url: _downloadUrl(path, sign),
      isDir: isDir,
      size: (entry['size'] as num?)?.toInt(),
    );
  }

  @override
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

  @override
  Future<WebdavEntry?> findFile(String path) async {
    final parent = parentPath(path);
    final entries = await list(parent);
    return entries
        .where((entry) => !entry.isDir && entry.path == path)
        .firstOrNull;
  }

  @override
  Future<RemotePlayback> playback(MediaItem item) async {
    final path = sourceItemPath(source, item);
    final json = await _post('/api/fs/get', {
      'path': path,
      'password': '',
    });
    final data = json['data'] as Map? ?? const {};
    final url = (data['url'] ?? data['raw_url']) as String?;
    if (url == null || url.isEmpty) {
      final sign = data['sign'] as String? ?? '';
      return RemotePlayback(
        sign.isEmpty ? item.uri : _downloadUrl(path, sign),
        const {},
      );
    }
    return RemotePlayback(
      url,
      _openlistPlaybackHeaders(data['header'] ?? data['headers']),
    );
  }

  String _downloadUrl(String path, String sign) {
    final base = source.baseUrl.endsWith('/')
        ? source.baseUrl.substring(0, source.baseUrl.length - 1)
        : source.baseUrl;
    final encoded = path
        .split('/')
        .where((part) => part.isNotEmpty)
        .map(Uri.encodeComponent)
        .join('/');
    final url = '$base/d/$encoded';
    return sign.isEmpty ? url : '$url?sign=${Uri.encodeQueryComponent(sign)}';
  }
}

Map<String, String> _openlistPlaybackHeaders(Object? value) {
  if (value is Map) {
    return value.map((key, value) => MapEntry('$key', '$value'));
  }
  if (value is String && value.trim().isNotEmpty) {
    try {
      final decoded = jsonDecode(value);
      if (decoded is Map) {
        return decoded.map((key, value) => MapEntry('$key', '$value'));
      }
    } catch (_) {}
  }
  return const {};
}

Map<String, dynamic> _openlistJson(http.Response response, String label) {
  final body = jsonDecode(response.body) as Map<String, dynamic>;
  final code = (body['code'] as num?)?.toInt() ?? response.statusCode;
  if (response.statusCode < 200 || response.statusCode >= 300 || code != 200) {
    throw Exception('$label $code: ${body['message'] ?? response.body}');
  }
  return body;
}

String _joinRemote(String parent, String name, {required bool isDir}) {
  final root = normalizeRemoteDir(parent);
  final path = root == '/' ? '/$name' : '$root$name';
  return isDir ? normalizeRemoteDir(path) : path;
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
