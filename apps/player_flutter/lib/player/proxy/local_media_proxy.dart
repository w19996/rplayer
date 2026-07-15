part of 'package:player_flutter/main.dart';

class LocalMediaProxy {
  LocalMediaProxy({
    this.maximumCacheBytes = 32 * 1024 * 1024,
    this.maximumEntryBytes = 4 * 1024 * 1024,
  });

  final int maximumCacheBytes;
  final int maximumEntryBytes;
  final _entries = <String, PlayerMediaSource>{};
  final _cache = <String, _ProxyCacheEntry>{};
  HttpServer? _server;
  int _cacheBytes = 0;

  Future<PlayerMediaSource?> prepare(
    PlayerMediaSource source, {
    void Function(String message)? log,
  }) async {
    if (!source.isRemote) return source.copyWith(nativeProxyReady: true);
    if (!await _supportsRange(source)) {
      log?.call('local proxy disabled: upstream does not support byte ranges');
      return null;
    }
    final server = await _ensureServer();
    final id = _randomToken(32);
    _entries[id] = source;
    final uri = Uri(
      scheme: 'http',
      host: InternetAddress.loopbackIPv4.address,
      port: server.port,
      pathSegments: ['media', id],
    );
    log?.call('local proxy ready: range=true seek=true port=${server.port}');
    return source.copyWith(
      uri: uri.toString(),
      httpHeaders: const {},
      nativeProxyReady: true,
    );
  }

  Future<bool> _supportsRange(PlayerMediaSource source) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
    try {
      final request = await client.getUrl(Uri.parse(source.uri));
      source.httpHeaders.forEach(request.headers.set);
      request.headers.set(HttpHeaders.rangeHeader, 'bytes=0-0');
      final response = await request.close();
      await response.drain<void>();
      return response.statusCode == HttpStatus.partialContent &&
          response.headers.value(HttpHeaders.contentRangeHeader) != null;
    } catch (_) {
      return false;
    } finally {
      client.close(force: true);
    }
  }

  Future<HttpServer> _ensureServer() async {
    final current = _server;
    if (current != null) return current;
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server = server;
    unawaited(_serve(server));
    return server;
  }

  Future<void> _serve(HttpServer server) async {
    await for (final request in server) {
      unawaited(_handle(request));
    }
  }

  Future<void> _handle(HttpRequest request) async {
    final segments = request.uri.pathSegments;
    final id = segments.length == 2 && segments.first == 'media'
        ? segments.last
        : null;
    final entry = id == null ? null : _entries[id];
    if (entry == null) {
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
      return;
    }
    if (request.method != 'GET' && request.method != 'HEAD') {
      request.response.statusCode = HttpStatus.methodNotAllowed;
      await request.response.close();
      return;
    }
    final range = request.headers.value(HttpHeaders.rangeHeader);
    final cacheKey = range == null ? '' : '${entry.uri}|$range';
    final cached = range == null ? null : _cache.remove(cacheKey);
    if (cached != null) {
      _cache[cacheKey] = cached;
      request.response.statusCode = cached.statusCode;
      cached.headers.forEach(request.response.headers.set);
      request.response.headers
          .set(HttpHeaders.contentLengthHeader, cached.bytes.length);
      if (request.method != 'HEAD') {
        await request.response.addStream(
          Stream<List<int>>.value(cached.bytes),
        );
      }
      await request.response.close();
      return;
    }
    try {
      await _forward(request, entry, range, cacheKey);
    } catch (error) {
      try {
        request.response.statusCode = HttpStatus.badGateway;
        request.response.write('upstream failed: $error');
        await request.response.close();
      } catch (_) {
        await request.response.close();
      }
    }
  }

  Future<void> _forward(
    HttpRequest incoming,
    PlayerMediaSource source,
    String? range,
    String cacheKey,
  ) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 10);
    try {
      final ifRange = incoming.headers.value(HttpHeaders.ifRangeHeader);
      final response = await _openUpstream(
        client,
        source,
        method: incoming.method,
        range: range,
        ifRange: ifRange,
      );
      final responseHeaders = <String, String>{};
      for (final name in const [
        HttpHeaders.acceptRangesHeader,
        HttpHeaders.contentLengthHeader,
        HttpHeaders.contentRangeHeader,
        HttpHeaders.contentTypeHeader,
        HttpHeaders.etagHeader,
        HttpHeaders.lastModifiedHeader,
      ]) {
        final value = response.headers.value(name);
        if (value != null) {
          responseHeaders[name] = value;
        }
      }
      if (incoming.method == 'HEAD') {
        await response.drain<void>();
        incoming.response.statusCode = response.statusCode;
        responseHeaders.forEach(incoming.response.headers.set);
        await incoming.response.close();
        return;
      }
      final expected = response.contentLength;
      if (range != null && expected >= 0 && expected <= maximumEntryBytes) {
        final builder = BytesBuilder(copy: false);
        await _copyWithRetry(
          client: client,
          source: source,
          initial: response,
          ifRange: ifRange,
          write: (chunk) async => builder.add(chunk),
        );
        final bytes = builder.takeBytes();
        incoming.response.statusCode = response.statusCode;
        responseHeaders.forEach(incoming.response.headers.set);
        incoming.response.headers.contentLength = bytes.length;
        await incoming.response.addStream(Stream<List<int>>.value(bytes));
        _putCache(
          cacheKey,
          _ProxyCacheEntry(
            bytes: bytes,
            statusCode: response.statusCode,
            headers: responseHeaders,
          ),
        );
      } else {
        incoming.response.statusCode = response.statusCode;
        responseHeaders.forEach(incoming.response.headers.set);
        await _copyWithRetry(
          client: client,
          source: source,
          initial: response,
          ifRange: ifRange,
          write: (chunk) => incoming.response.addStream(
            Stream<List<int>>.value(chunk),
          ),
        );
      }
      await incoming.response.close();
    } finally {
      client.close();
    }
  }

  Future<HttpClientResponse> _openUpstream(
    HttpClient client,
    PlayerMediaSource source, {
    required String method,
    String? range,
    String? ifRange,
  }) async {
    Object? lastError;
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        final request = await client.openUrl(method, Uri.parse(source.uri));
        source.httpHeaders.forEach(request.headers.set);
        if (range != null) {
          request.headers.set(HttpHeaders.rangeHeader, range);
        }
        if (ifRange != null) {
          request.headers.set(HttpHeaders.ifRangeHeader, ifRange);
        }
        return await request.close();
      } catch (error) {
        lastError = error;
      }
    }
    throw HttpException('upstream open failed: $lastError');
  }

  Future<void> _copyWithRetry({
    required HttpClient client,
    required PlayerMediaSource source,
    required HttpClientResponse initial,
    required Future<void> Function(List<int> chunk) write,
    String? ifRange,
  }) async {
    var response = initial;
    final contentRange = _ProxyByteRange.parse(
      response.headers.value(HttpHeaders.contentRangeHeader),
    );
    final start = contentRange?.start ?? 0;
    final expected = contentRange == null
        ? response.contentLength
        : contentRange.end - contentRange.start + 1;
    final end =
        contentRange?.end ?? (expected >= 0 ? start + expected - 1 : null);
    var copied = 0;
    var retries = 0;
    while (true) {
      Object? streamError;
      try {
        await for (final chunk in response) {
          await write(chunk);
          copied += chunk.length;
        }
      } catch (error) {
        streamError = error;
      }
      if (expected < 0 || copied >= expected) return;
      if (retries >= 2 || end == null) {
        throw HttpException(
          'upstream disconnected after $copied/$expected bytes: $streamError',
        );
      }
      retries++;
      response = await _openUpstream(
        client,
        source,
        method: 'GET',
        range: 'bytes=${start + copied}-$end',
        ifRange: ifRange,
      );
      if (response.statusCode != HttpStatus.partialContent) {
        throw HttpException(
          'upstream retry ignored Range: ${response.statusCode}',
        );
      }
    }
  }

  void _putCache(String key, _ProxyCacheEntry entry) {
    if (key.isEmpty || entry.bytes.length > maximumEntryBytes) return;
    final old = _cache.remove(key);
    if (old != null) _cacheBytes -= old.bytes.length;
    _cache[key] = entry;
    _cacheBytes += entry.bytes.length;
    while (_cacheBytes > maximumCacheBytes && _cache.isNotEmpty) {
      final oldest = _cache.keys.first;
      _cacheBytes -= _cache.remove(oldest)!.bytes.length;
    }
  }

  String _randomToken(int bytes) {
    final random = math.Random.secure();
    final values = Uint8List.fromList(
      List<int>.generate(bytes, (_) => random.nextInt(256)),
    );
    return base64UrlEncode(values).replaceAll('=', '');
  }

  Future<void> dispose() async {
    _entries.clear();
    _cache.clear();
    _cacheBytes = 0;
    await _server?.close(force: true);
    _server = null;
  }
}

class _ProxyCacheEntry {
  const _ProxyCacheEntry({
    required this.bytes,
    required this.statusCode,
    required this.headers,
  });

  final Uint8List bytes;
  final int statusCode;
  final Map<String, String> headers;
}

class _ProxyByteRange {
  const _ProxyByteRange(this.start, this.end);

  final int start;
  final int end;

  static _ProxyByteRange? parse(String? value) {
    final match = RegExp(r'^bytes (\d+)-(\d+)/(?:\d+|\*)$').firstMatch(
      value ?? '',
    );
    if (match == null) return null;
    return _ProxyByteRange(
      int.parse(match.group(1)!),
      int.parse(match.group(2)!),
    );
  }
}
