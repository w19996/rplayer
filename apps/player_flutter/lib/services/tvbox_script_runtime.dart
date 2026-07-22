part of 'package:player_flutter/main.dart';

class TvboxScriptRuntime {
  TvboxScriptRuntime._();

  static final _jsRuntimes = <String, QuickJsRuntime2>{};
  static final _jsInit = <String, Future<void>>{};
  static final _jsResolvers = <String, _TvboxJsModuleResolver>{};
  static final _proxy = _TvboxLocalProxyServer();
  static TvboxSite? _recentPythonSite;

  static bool canHandle(String api) =>
      Platform.isWindows && (_isJsApi(api) || _isPythonApi(api));

  static Future<String> call(
    TvboxSite site,
    String action, [
    Map<String, Object?> arguments = const {},
  ]) {
    if (_isJsApi(site.apiUrl)) return _callJs(site, action, arguments);
    if (_isPythonApi(site.apiUrl)) {
      if (!Platform.isWindows) {
        throw UnsupportedError('Python 源由 Android 原生运行时处理');
      }
      return _callPython(site, action, arguments);
    }
    throw UnsupportedError('当前平台仅支持 TVBox JS/Python 脚本源');
  }

  static Future<String> _callJs(
    TvboxSite site,
    String action,
    Map<String, Object?> arguments,
  ) async {
    final key = '${site.key}\n${site.apiUrl}\n${site.ext}';
    await (_jsInit[key] ??= _initJs(site, key));
    _proxy.recentJsKey = key;
    final runtime = _jsRuntimes[key]!;
    final call = switch (action) {
      'home' => "__tvboxCall('home', [true])",
      'category' =>
        "__tvboxCall('category', [${jsonEncode(arguments['typeId'] ?? '')}, ${jsonEncode(arguments['page'] ?? '1')}, true, {}])",
      'detail' => "__tvboxCall('detail', [${jsonEncode(arguments['id'] ?? '')}])",
      'search' => "__tvboxCall('search', [${jsonEncode(arguments['keyword'] ?? '')}, false])",
      'player' =>
        "__tvboxCall('play', [${jsonEncode(arguments['flag'] ?? '')}, ${jsonEncode(arguments['id'] ?? '')}, []])",
      'action' => "__tvboxCall('action', [${jsonEncode(arguments['value'] ?? '')}])",
      _ => throw ArgumentError('未知 Spider 操作：$action'),
    };
    final result = await runtime.handlePromise(
      runtime.evaluate(call),
      timeout: const Duration(seconds: 30),
    );
    if (result.isError) throw StateError(result.stringResult);
    return result.stringResult.isEmpty ? '{}' : result.stringResult;
  }

  static Future<void> _initJs(TvboxSite site, String key) async {
    await _proxy.ensureStarted();
    final resolver = _TvboxJsModuleResolver(site);
    final runtime = QuickJsRuntime2(
      moduleHandler: resolver.loadCachedModule,
      stackSize: 4 * 1024 * 1024,
    );
    _jsRuntimes[key] = runtime;
    _jsResolvers[key] = resolver;
    runtime.evaluate(_jsHost);
    (runtime.localContext['setToGlobalObject'] as JSInvokable).invoke([
      '_tvboxHttp',
      (String url, [dynamic options]) => _proxy.syncHttp(url, options),
    ]);
    final code = await resolver.loadRootModule();
    if (_isInvalidJsModule(code)) throw StateError('JS Spider 内容无效');
    await resolver.prefetchImports(site.apiUrl, code);
    final net = await resolver.loadBuiltinModule('net.js');
    if (!_isInvalidJsModule(net)) runtime.evaluate(net, sourceUrl: 'net.js');
    final template = await resolver.loadBuiltinModule('模板.js');
    if (!_isInvalidJsModule(template)) {
      resolver.cacheModule('模板.js', template);
      final preload = runtime.evaluate(
        "import tpl from '模板.js';"
        "globalThis.muban = tpl && tpl.muban;"
        "globalThis.getMubans = tpl && tpl.getMubans;",
        name: 'tv_box_template.js',
        evalFlags: JSEvalFlag.MODULE,
      );
      if (preload.isError) {
        debugPrint('TVBox JS 模板预载失败: ${preload.stringResult}');
      }
    }
    final moduleCode = _normalizeJsModule(code);
    resolver.cacheModule(site.apiUrl, moduleCode);
    final loaded = runtime.evaluate(
      moduleCode,
      name: site.apiUrl,
      evalFlags: JSEvalFlag.MODULE,
    );
    if (loaded.isError) throw StateError(loaded.stringResult);
    final root = runtime.evaluate(
      _spiderRootModule(site.apiUrl, key),
      name: 'tv_box_root.js',
      evalFlags: JSEvalFlag.MODULE,
    );
    if (root.isError) throw StateError(root.stringResult);
    final init = runtime.evaluate(_spiderInitScript(site, key));
    if (init.isError) throw StateError(init.stringResult);
  }

  static String _normalizeJsModule(String code) {
    var value = code.trimLeft();
    if (value.contains('__JS_SPIDER__')) {
      value = value.replaceAll(
      RegExp(r'\b__JS_SPIDER__\s*='),
        'export default ',
      );
    }
    return value;
  }

  static const _jsHost = '''
    function __tvboxString(value) {
      if (value === undefined || value === null) return '';
      if (typeof value === 'string') return value;
      return JSON.stringify(value);
    }
    function __tvboxCall(name, args) {
      const spider = globalThis.__JS_SPIDER__;
      if (!spider || typeof spider[name] !== 'function') return '{}';
      return Promise.resolve(spider[name].apply(spider, args)).then(__tvboxString);
    }
    function __tvboxProxy(params) {
      const spider = globalThis.__JS_SPIDER__;
      if (!spider || typeof spider.proxy !== 'function') return '[]';
      if (params && params.from === 'catvod') {
        const path = String(params.url || '').split('/');
        const header = JSON.parse(params.header || '{}');
        return Promise.resolve(spider.proxy(path, header)).then(__tvboxString);
      }
      return Promise.resolve(spider.proxy(params || {})).then(__tvboxString);
    }
    function _http(url, options) {
      return _tvboxHttp(url, options || {});
    }
    const req = (url, options) => _http(url, options || {});
    const http = req;
    function joinUrl(parent, child) { return new URL(child, parent).toString(); }
    function getProxy(local) { return 'http://127.0.0.1:9978/proxy?do=js'; }
    function js2Proxy(dynamic, siteType, siteKey, url, headers) {
      return getProxy(!dynamic) + '&from=catvod&siteType=' + siteType +
        '&siteKey=' + encodeURIComponent(siteKey || '') +
        '&header=' + encodeURIComponent(JSON.stringify(headers || {})) +
        '&url=' + encodeURIComponent(url || '');
    }
    const local = {
      get: function(key, fallback) {
        const value = globalThis.__tvboxLocalStorage &&
          globalThis.__tvboxLocalStorage[String(key)];
        return value === undefined ? (fallback || '') : value;
      },
      set: function(key, value) {
        globalThis.__tvboxLocalStorage = globalThis.__tvboxLocalStorage || {};
        globalThis.__tvboxLocalStorage[String(key)] = String(value);
      },
      delete: function(key) {
        if (globalThis.__tvboxLocalStorage) delete globalThis.__tvboxLocalStorage[String(key)];
      }
    };
  ''';

  static String _spiderRootModule(String api, String key) => '''
    import * as spider from ${jsonEncode(api)};

    if (!globalThis.__JS_SPIDER__) {
      if (spider.__jsEvalReturn) {
        globalThis.req = http;
        globalThis.__JS_SPIDER__ = spider.__jsEvalReturn();
        globalThis.__JS_SPIDER__.is_cat = true;
      } else if (spider.default) {
        globalThis.__JS_SPIDER__ =
          typeof spider.default === 'function' ? spider.default() : spider.default;
      }
    }
    globalThis[${jsonEncode(key)}] = globalThis.__JS_SPIDER__;
  ''';

  static String _spiderInitScript(TvboxSite site, String key) {
    final ext = site.ext.trim();
    final parsedExt = ext.startsWith('{') || ext.startsWith('[');
    final catConfig = {
      'stype': 3,
      'skey': site.key,
      'ext': parsedExt ? jsonDecode(ext) : site.ext,
    };
    return '''
      globalThis.__JS_SPIDER__ = globalThis[${jsonEncode(key)}];
      if (!globalThis.__JS_SPIDER__) throw new Error('JS Spider 未导出对象');
      if (typeof globalThis.__JS_SPIDER__.init === 'function') {
        globalThis.__JS_SPIDER__.init(
          globalThis.__JS_SPIDER__.is_cat
            ? ${jsonEncode(catConfig)}
            : ${parsedExt ? ext : jsonEncode(site.ext)}
        );
      }
    ''';
  }

  static bool _isInvalidJsModule(String content) {
    final trim = content.trimLeft().replaceFirst('\uFEFF', '').trimLeft();
    final lower = trim.toLowerCase();
    return trim.isEmpty ||
        lower.startsWith('<') ||
        lower.startsWith('{"code":404') ||
        lower.startsWith('404') ||
        lower.startsWith('not found');
  }

  static Future<String> _readText(
    String value, [
    Map<String, String> headers = const {},
  ]) async {
    final uri = Uri.tryParse(_tvboxUrlWithAsciiHost(value));
    if (uri != null && (uri.scheme == 'http' || uri.scheme == 'https')) {
      final response = await http
          .get(uri, headers: headers)
          .timeout(const Duration(seconds: 20));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException('脚本返回 HTTP ${response.statusCode}');
      }
      return utf8.decode(response.bodyBytes, allowMalformed: true);
    }
    return File(value).readAsString();
  }

  static Future<String> _callPython(
    TvboxSite site,
    String action,
    Map<String, Object?> arguments,
  ) async {
    await _proxy.ensureStarted();
    _recentPythonSite = site;
    final root = await _runtimeRoot();
    final runner = File(p.join(root.path, 'python_runner.py'));
    final python = await _pythonExecutable(root);
    final input = jsonEncode({
      'action': action,
      'key': site.key,
      'api': site.apiUrl,
      'ext': site.ext,
      'configJson': site.configJson,
      'cacheDir': p.join((await _dataRoot()).path, 'tvbox', 'python'),
      'args': arguments,
    });
    final process = await Process.start(
      python.path,
      [runner.path],
      workingDirectory: root.path,
      environment: {'PYTHONIOENCODING': 'utf-8'},
    );
    process.stdin.write(input);
    await process.stdin.close();
    final output = await process.stdout.transform(utf8.decoder).join();
    final error = await process.stderr.transform(utf8.decoder).join();
    final exitCode =
        await process.exitCode.timeout(const Duration(seconds: 35));
    if (exitCode != 0) {
      throw StateError(error.trim().ifEmpty('Python Spider 执行失败'));
    }
    final decoded = jsonDecode(output);
    if (decoded is! Map || decoded['ok'] != true) {
      throw StateError('${decoded is Map ? decoded['error'] : output}');
    }
    return '${decoded['result'] ?? '{}'}';
  }

  static Future<RemotePlayback> finishPlayback(
    TvboxSite site,
    Map<String, dynamic> value,
  ) async {
    await _proxy.ensureStarted();
    final raw = value['url'];
    var resolved = raw is List ? (raw.length > 1 ? raw[1] : raw.firstOrNull) : raw;
    if (resolved == null || '$resolved'.isEmpty) {
      throw const FormatException('播放接口未返回地址');
    }
    var url = '$resolved';
    if (url.startsWith('video://')) {
      url = url.substring('video://'.length);
      value['parse'] = 1;
    } else if (url.startsWith('tvbox-drive://')) {
      url = url.substring('tvbox-drive://'.length);
      value['parse'] = 0;
    } else if (url.startsWith('proxy://')) {
      url = 'http://127.0.0.1:${_TvboxLocalProxyServer.port}/proxy?${url.substring('proxy://'.length)}';
      value['parse'] = 0;
    }
    final headers = {
      ...site.headers,
      ..._tvboxHeaders(value['header']),
      ..._tvboxHeaders(value['headers']),
    };
    final playUrl = '${value['playUrl'] ?? ''}$url';
    final parse = '${value['parse'] ?? '1'}' == '1' || '${value['jx'] ?? '0'}' == '1';
    final format = '${value['format'] ?? ''}'.trim();
    final danmaku = '${value['danmaku'] ?? ''}'.trim();
    final playbackUrl = !parse ? _proxy.localPlaybackUrl(playUrl, headers) : playUrl;
    final inferredMimeType = format.isEmpty && _tvboxLooksHls(playbackUrl)
        ? 'application/x-mpegURL'
        : null;
    return RemotePlayback(
      playbackUrl,
      headers,
      mimeType: format.isEmpty ? inferredMimeType : format,
      danmaku: danmaku.isEmpty ? null : danmaku,
    );
  }

  static Future<File> _pythonExecutable(Directory runtimeRoot) async {
    final embedded = File(p.join(runtimeRoot.path, 'python', 'python.exe'));
    if (await embedded.exists()) return embedded;
    final local = await _findExecutable(
        'py', ['-3.13', '-c', 'import sys; print(sys.executable)']);
    if (local != null) return File(local);
    final fallback = await _findExecutable(
        'python', ['-c', 'import sys; print(sys.executable)']);
    if (fallback != null) return File(fallback);
    throw StateError('未找到 Windows Python 3.13 运行时');
  }

  static Future<String?> _findExecutable(
      String command, List<String> args) async {
    try {
      final result =
          await Process.run(command, args).timeout(const Duration(seconds: 5));
      if (result.exitCode == 0) {
        final path = '${result.stdout}'.trim().split(RegExp(r'\r?\n')).last;
        if (path.isNotEmpty && await File(path).exists()) return path;
      }
    } catch (_) {}
    return null;
  }

  static Future<Directory> _runtimeRoot() async {
    final release = Directory(p.join(
      p.dirname(Platform.resolvedExecutable),
      'tvbox_runtime',
    ));
    if (await release.exists()) return release;
    return Directory(
        p.join(Directory.current.path, 'windows', 'tvbox_runtime'));
  }

  static Future<Directory> _dataRoot() async {
    final dir = Directory(p.join(
      p.dirname(Platform.resolvedExecutable),
      'rplayer_data',
    ));
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  static bool _isJsApi(String api) {
    final value = api.toLowerCase();
    return value.endsWith('.js') || value.contains('.js?');
  }

  static bool _isPythonApi(String api) {
    final value = api.toLowerCase();
    return value.endsWith('.py') || value.contains('.py?');
  }

  static Future<List<Object?>> _callPythonProxy(Map<String, String> params) async {
    final site = _recentPythonSite;
    if (site == null) return const [];
    final text = await _callPython(site, 'proxy', params);
    final decoded = jsonDecode(text);
    return decoded is List ? decoded.cast<Object?>() : const [];
  }

  static Future<List<Object?>> _callJsProxy(Map<String, String> params) async {
    final key = _proxy.recentJsKey;
    final runtime = key == null ? null : _jsRuntimes[key];
    if (runtime == null) return const [];
    final result = await runtime.handlePromise(
      runtime.evaluate('__tvboxProxy(${jsonEncode(params)})'),
      timeout: const Duration(seconds: 30),
    );
    if (result.isError || result.stringResult.isEmpty) return const [];
    final decoded = jsonDecode(result.stringResult);
    if (decoded is Map && decoded.containsKey('content')) {
      final buffer = decoded['buffer'];
      return [
        200,
        decoded['contentType'] ?? decoded['type'] ?? 'application/octet-stream',
        decoded['content'] ?? '',
        if (buffer != null) {'buffer': buffer},
      ];
    }
    return decoded is List ? decoded.cast<Object?>() : const [];
  }
}

extension on String {
  String ifEmpty(String fallback) => isEmpty ? fallback : this;
}

class _TvboxLocalProxyServer {
  static const port = 9978;

  HttpServer? _server;
  Future<void>? _starting;
  String? recentJsKey;
  final _cache = <String, String>{};
  final _playbackHeaders = <String, Map<String, String>>{};

  Future<void> ensureStarted() {
    if (!Platform.isWindows) return Future.value();
    if (_server != null) return Future.value();
    return _starting ??= HttpServer.bind(InternetAddress.loopbackIPv4, port)
        .then((server) {
      _server = server;
      server.listen(_handle, onError: (_) {});
    }).whenComplete(() => _starting = null);
  }

  String localPlaybackUrl(String url, Map<String, String> headers) {
    final resolved = localProxyUrl(url);
    if (!_tvboxLooksHls(resolved) ||
        resolved.startsWith('http://127.0.0.1:$port/')) {
      return resolved;
    }
    final key = _sha256(resolved + jsonEncode(Map.fromEntries(
      headers.entries.toList()..sort((a, b) => a.key.compareTo(b.key)),
    )));
    _playbackHeaders[key] = headers;
    return 'http://127.0.0.1:$port/playlist.m3u8?key=$key&url=${Uri.encodeComponent(resolved)}';
  }

  String localProxyUrl(String url) => url.startsWith('proxy://')
      ? 'http://127.0.0.1:$port/proxy?${url.substring('proxy://'.length)}'
      : url;

  Map<String, Object?> syncHttp(String url, dynamic options) {
    final opts = options is Map ? options : const {};
    final method = '${opts['method'] ?? opts['type'] ?? 'GET'}'.toUpperCase();
    final headers = _stringMap(opts['headers']);
    final body = opts['body'] ?? opts['data'];
    final args = <String>['-L', '-sS', '-i', '-X', method];
    headers.forEach((key, value) => args.addAll(['-H', '$key: $value']));
    if (body != null) args.addAll(['--data-binary', '$body']);
    args.add(url);
    final result = Process.runSync('curl.exe', args, stdoutEncoding: utf8, stderrEncoding: utf8);
    if (result.exitCode != 0) {
      return {'ok': false, 'status': 500, 'url': url, 'content': '${result.stderr}'};
    }
    final parsed = _splitHttpResponse('${result.stdout}');
    return {
      'ok': parsed.$1 >= 200 && parsed.$1 < 300,
      'status': parsed.$1,
      'url': url,
      'headers': parsed.$2,
      'content': parsed.$3,
    };
  }

  Future<void> _handle(HttpRequest request) async {
    try {
      if (request.uri.path == '/cache') return _handleCache(request);
      if (request.uri.path == '/playlist.m3u8') return _serveM3u8(request);
      if (request.uri.path == '/segment.ts') return _serveSegment(request);
      if (request.uri.path == '/proxy' || request.uri.path == '/') {
        return _handleProxy(request);
      }
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
    } catch (error) {
      request.response.statusCode = HttpStatus.internalServerError;
      request.response.write(error.toString());
      await request.response.close();
    }
  }

  Future<void> _handleCache(HttpRequest request) async {
    final key = request.uri.queryParameters['key'] ?? '';
    switch (request.uri.queryParameters['do']) {
      case 'get':
        request.response.write(_cache[key] ?? '');
      case 'set':
        final fields = await _formFields(request);
        _cache[key] = fields['value'] ?? '';
        request.response.write('succeed');
      case 'del':
        _cache.remove(key);
        request.response.write('succeed');
      default:
        request.response.statusCode = HttpStatus.badRequest;
    }
    await request.response.close();
  }

  Future<void> _handleProxy(HttpRequest request) async {
    final params = <String, String>{
      ...request.uri.queryParameters,
    };
    request.headers.forEach((name, values) => params[name] = values.join(','));
    final result = params['do'] == 'py'
        ? await TvboxScriptRuntime._callPythonProxy(params)
        : await TvboxScriptRuntime._callJsProxy(params);
    await _writeProxyResult(request, result);
  }

  Future<void> _serveM3u8(HttpRequest request) async {
    final url = request.uri.queryParameters['url'] ?? '';
    final key = request.uri.queryParameters['key'] ?? '';
    final download = await _download(url, _playbackHeaders[key] ?? const {});
    if (download.statusCode < 200 || download.statusCode >= 300) {
      request.response.statusCode = download.statusCode;
      request.response.add(download.bodyBytes);
      return request.response.close();
    }
    request.response.headers.contentType =
        ContentType('application', 'vnd.apple.mpegurl');
    request.response.write(_rewriteM3u8(url, utf8.decode(download.bodyBytes, allowMalformed: true), key));
    await request.response.close();
  }

  Future<void> _serveSegment(HttpRequest request) async {
    final url = request.uri.queryParameters['url'] ?? '';
    final key = request.uri.queryParameters['key'] ?? '';
    final download = await _download(url, _playbackHeaders[key] ?? const {});
    request.response.statusCode = download.statusCode;
    final type = download.headers['content-type'];
    if (type != null) request.response.headers.set(HttpHeaders.contentTypeHeader, type);
    request.response.add(download.bodyBytes);
    await request.response.close();
  }

  Future<void> _writeProxyResult(HttpRequest request, List<Object?> result) async {
    if (result.length < 3) {
      request.response.statusCode = HttpStatus.internalServerError;
      request.response.write('proxy failed');
      return request.response.close();
    }
    request.response.statusCode = (result[0] as num?)?.toInt() ?? 200;
    request.response.headers.contentType =
        ContentType.parse('${result[1] ?? 'application/octet-stream'}');
    if (result.length > 3 && result[3] is Map) {
      _stringMap(result[3]).forEach(request.response.headers.set);
    }
    final body = result[2];
    if (body is List) {
      request.response.add(body.map((value) => (value as num).toInt()).toList());
    } else if (result.length > 4 && '${result[4]}' == '1' && '$body'.contains('base64,')) {
      request.response.add(base64Decode('$body'.split('base64,').last));
    } else if (result.length > 3 && result[3] is Map && '${(result[3] as Map)['buffer']}' == '2') {
      request.response.add(base64Decode('$body'));
    } else {
      request.response.write(body ?? '');
    }
    await request.response.close();
  }

  Future<http.Response> _download(String url, Map<String, String> headers) =>
      http.get(Uri.parse(url), headers: headers).timeout(const Duration(seconds: 30));

  String _rewriteM3u8(String sourceUrl, String content, String key) {
    final base = Uri.parse(sourceUrl);
    String rewrite(String value) {
      final absolute = base.resolve(value).toString();
      final path = Uri.parse(absolute).path.toLowerCase();
      return path.endsWith('.m3u8')
          ? 'http://127.0.0.1:$port/playlist.m3u8?key=$key&url=${Uri.encodeComponent(absolute)}'
          : 'http://127.0.0.1:$port/segment.ts?key=$key&url=${Uri.encodeComponent(absolute)}';
    }
    final uriPattern = RegExp('URI="([^"]+)"');
    return const LineSplitter().convert(content).map((line) {
      if (line.isEmpty) return line;
      if (line.startsWith('#')) {
        return line.replaceAllMapped(uriPattern, (match) => 'URI="${rewrite(match.group(1)!)}"');
      }
      return rewrite(line.trim());
    }).join('\n');
  }

  Future<Map<String, String>> _formFields(HttpRequest request) async {
    final body = await utf8.decoder.bind(request).join();
    return Uri.splitQueryString(body);
  }

  static Map<String, String> _stringMap(Object? value) {
    if (value is Map) {
      return value.map((key, value) => MapEntry('$key', '$value'));
    }
    if (value is String && value.trim().startsWith('{')) {
      final decoded = jsonDecode(value);
      if (decoded is Map) return _stringMap(decoded);
    }
    return const {};
  }

  static (int, Map<String, String>, String) _splitHttpResponse(String text) {
    final parts = text.split(RegExp(r'\r?\n\r?\n'));
    final header = parts.length > 1 ? parts[parts.length - 2] : '';
    final body = parts.length > 1 ? parts.last : text;
    final lines = header.split(RegExp(r'\r?\n'));
    final status = int.tryParse(lines.first.split(' ').elementAtOrNull(1) ?? '') ?? 200;
    final headers = <String, String>{};
    for (final line in lines.skip(1)) {
      final index = line.indexOf(':');
      if (index > 0) headers[line.substring(0, index).trim()] = line.substring(index + 1).trim();
    }
    return (status, headers, body);
  }

  static String _sha256(String value) {
    // ponytail: non-cryptographic key is enough for local header lookup; use crypto if collisions matter.
    return value.hashCode.toUnsigned(32).toRadixString(16);
  }
}

class _TvboxJsModuleResolver {
  _TvboxJsModuleResolver(this.site);

  final TvboxSite site;
  final _cache = <String, String>{};

  Future<String> loadRootModule() =>
      TvboxScriptRuntime._readText(site.apiUrl, site.headers);

  Future<String> loadBuiltinModule(String name) async {
    final cached = _cache[name];
    if (cached != null) return cached;
    try {
      final value = await rootBundle
          .loadString('android/app/src/main/assets/js/lib/$name');
      _cache[name] = value;
      return value;
    } catch (_) {
      return '';
    }
  }

  void cacheModule(String name, String code) {
    _cache[name] = code;
    _cache[_basename(name)] = code;
  }

  String loadCachedModule(String name) {
    final key = _resolveModuleName(site.apiUrl, name);
    final value = _cache[key] ?? _cache[name] ?? _cache[_basename(name)];
    if (value == null) throw StateError('Module Not found: $name');
    return value;
  }

  Future<void> prefetchImports(String base, String code,
      [Set<String>? loading]) async {
    loading ??= <String>{};
    for (final importName in _imports(code)) {
      final resolved = _resolveModuleName(base, importName);
      if (!loading.add(resolved) || _cache.containsKey(resolved)) continue;
      final content = await _loadModule(resolved);
      if (TvboxScriptRuntime._isInvalidJsModule(content)) continue;
      final normalized = TvboxScriptRuntime._normalizeJsModule(content);
      cacheModule(resolved, normalized);
      await prefetchImports(resolved, normalized, loading);
    }
  }

  Future<String> _loadModule(String name) async {
    final builtin = await loadBuiltinModule(_basename(name));
    if (builtin.isNotEmpty) return builtin;
    return TvboxScriptRuntime._readText(name, site.headers);
  }

  static Iterable<String> _imports(String code) sync* {
    final patterns = [
      RegExp(r'''import\s+(?:[^'"]*?\s+from\s+)?['"]([^'"]+)['"]'''),
      RegExp(r'''export\s+[^'"]*?\s+from\s+['"]([^'"]+)['"]'''),
    ];
    for (final pattern in patterns) {
      for (final match in pattern.allMatches(code)) {
        final value = match.group(1);
        if (value != null && value.isNotEmpty) yield value;
      }
    }
  }

  static String _resolveModuleName(String base, String name) {
    final uri = Uri.tryParse(name);
    if (uri != null && (uri.scheme == 'http' || uri.scheme == 'https')) {
      return _tvboxUrlWithAsciiHost(name);
    }
    final baseUri = Uri.tryParse(_tvboxUrlWithAsciiHost(base));
    if (baseUri != null &&
        (baseUri.scheme == 'http' || baseUri.scheme == 'https')) {
      return baseUri.resolve(name).toString();
    }
    if (p.isAbsolute(name)) return name;
    return p.normalize(p.join(p.dirname(base), name));
  }

  static String _basename(String name) => Uri.tryParse(name)?.pathSegments.lastOrNull ??
      p.basename(name);
}
