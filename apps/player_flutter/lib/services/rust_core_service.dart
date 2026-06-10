part of 'package:player_flutter/main.dart';

typedef _RustStringFn = ffi.Pointer<Utf8> Function(ffi.Pointer<Utf8>);
typedef _RustStringDart = ffi.Pointer<Utf8> Function(ffi.Pointer<Utf8>);
typedef _RustTwoStringFn = ffi.Pointer<Utf8> Function(
    ffi.Pointer<Utf8>, ffi.Pointer<Utf8>);
typedef _RustTwoStringDart = ffi.Pointer<Utf8> Function(
    ffi.Pointer<Utf8>, ffi.Pointer<Utf8>);
typedef _RustThreeStringFn = ffi.Pointer<Utf8> Function(
    ffi.Pointer<Utf8>, ffi.Pointer<Utf8>, ffi.Pointer<Utf8>);
typedef _RustThreeStringDart = ffi.Pointer<Utf8> Function(
    ffi.Pointer<Utf8>, ffi.Pointer<Utf8>, ffi.Pointer<Utf8>);
typedef _RustFourStringFn = ffi.Pointer<Utf8> Function(
    ffi.Pointer<Utf8>, ffi.Pointer<Utf8>, ffi.Pointer<Utf8>, ffi.Pointer<Utf8>);
typedef _RustFourStringDart = ffi.Pointer<Utf8> Function(
    ffi.Pointer<Utf8>, ffi.Pointer<Utf8>, ffi.Pointer<Utf8>, ffi.Pointer<Utf8>);
typedef _RustFreeFn = ffi.Void Function(ffi.Pointer<Utf8>);
typedef _RustFreeDart = void Function(ffi.Pointer<Utf8>);

class RustCoreService {
  RustCoreService._();

  static final RustCoreService instance = RustCoreService._();

  ffi.DynamicLibrary? _library;
  _RustStringDart? _scanLocalVideosJson;
  _RustStringDart? _listLocalDirectoryJson;
  _RustTwoStringDart? _parseMediaIdentityJson;
  _RustThreeStringDart? _tmdbGetJson;
  _RustThreeStringDart? _metadataPutJson;
  _RustStringDart? _metadataGetAllJson;
  _RustTwoStringDart? _metadataReplaceAllJson;
  _RustFourStringDart? _parseWebdavEntriesJson;
  _RustFreeDart? _freeString;
  Object? _loadError;

  bool get available => _ensureLoaded();

  bool get _bindingsReady =>
      _scanLocalVideosJson != null &&
      _listLocalDirectoryJson != null &&
      _parseMediaIdentityJson != null &&
      _tmdbGetJson != null &&
      _metadataPutJson != null &&
      _metadataGetAllJson != null &&
      _metadataReplaceAllJson != null &&
      _parseWebdavEntriesJson != null &&
      _freeString != null;

  List<RustScannedVideo> scanLocalVideos(String root) {
    _ensureAvailable();
    final text = _callString(_scanLocalVideosJson, [root]);
    final data = jsonDecode(text) as List<dynamic>;
    return data
        .map(
            (value) => RustScannedVideo.fromJson(value as Map<String, dynamic>))
        .toList();
  }

  Future<List<RustScannedVideo>> scanLocalVideosAsync(String root) {
    final args = [root];
    return Isolate.run(() => _rustScanLocalVideosWorker(args));
  }

  List<LocalEntry> listLocalDirectory(String root) {
    _ensureAvailable();
    final text = _callString(_listLocalDirectoryJson, [root]);
    final data = jsonDecode(text) as List<dynamic>;
    return data.map((value) {
      final json = value as Map<String, dynamic>;
      return LocalEntry(
        name: json['name'] as String? ?? '',
        path: json['path'] as String? ?? '',
        isDir: json['is_dir'] == true,
        size: (json['size'] as num?)?.toInt(),
      );
    }).toList();
  }

  Future<List<LocalEntry>> listLocalDirectoryAsync(String root) {
    final args = [root];
    return Isolate.run(() => _rustListLocalDirectoryWorker(args));
  }

  RustMediaIdentity parseMediaIdentity(String folderName, String fileName) {
    _ensureAvailable();
    final text = _callTwoString(_parseMediaIdentityJson, folderName, fileName);
    return RustMediaIdentity.fromJson(jsonDecode(text) as Map<String, dynamic>);
  }

  String tmdbGetJson(String url, String accessToken, String proxyUrl) {
    _ensureAvailable();
    return _callThreeString(_tmdbGetJson, url, accessToken, proxyUrl);
  }

  Future<String> tmdbGetJsonAsync(
      String url, String accessToken, String proxyUrl) {
    final args = [url, accessToken, proxyUrl];
    return Isolate.run(() => _rustTmdbGetJsonWorker(args));
  }

  void metadataPut(String dbPath, String itemId, String metadataJson) {
    _ensureAvailable();
    _callThreeString(_metadataPutJson, dbPath, itemId, metadataJson);
  }

  Future<void> metadataPutAsync(
      String dbPath, String itemId, String metadataJson) {
    final args = [dbPath, itemId, metadataJson];
    return Isolate.run(() => _rustMetadataPutWorker(args));
  }

  Map<String, MediaMetadata> metadataGetAll(String dbPath) {
    _ensureAvailable();
    final text = _callString(_metadataGetAllJson, [dbPath]);
    final data = jsonDecode(text) as Map<String, dynamic>;
    return data.map(
      (key, value) => MapEntry(
        key,
        MediaMetadata.fromJson(value as Map<String, dynamic>),
      ),
    );
  }

  Future<Map<String, MediaMetadata>> metadataGetAllAsync(String dbPath) {
    final args = [dbPath];
    return Isolate.run(() => _rustMetadataGetAllJsonWorker(args)).then(
      (text) {
        final data = jsonDecode(text) as Map<String, dynamic>;
        return data.map(
          (key, value) => MapEntry(
            key,
            MediaMetadata.fromJson(value as Map<String, dynamic>),
          ),
        );
      },
    );
  }

  void metadataReplaceAll(String dbPath, Map<String, MediaMetadata> values) {
    _ensureAvailable();
    final text = jsonEncode(values.map((key, value) => MapEntry(
          key,
          value.toJson(),
        )));
    _callTwoString(_metadataReplaceAllJson, dbPath, text);
  }

  Future<void> metadataReplaceAllAsync(
      String dbPath, Map<String, MediaMetadata> values) {
    final text = jsonEncode(values.map((key, value) => MapEntry(
          key,
          value.toJson(),
        )));
    final args = [dbPath, text];
    return Isolate.run(() => _rustMetadataReplaceAllWorker(args));
  }

  List<WebdavEntry> parseWebdavEntries({
    required String body,
    required String baseUrl,
    required String requestUrl,
    required String currentPath,
  }) {
    _ensureAvailable();
    final text = _callFourString(
      _parseWebdavEntriesJson,
      body,
      baseUrl,
      requestUrl,
      currentPath,
    );
    final data = jsonDecode(text) as List<dynamic>;
    return data.map((value) {
      final json = value as Map<String, dynamic>;
      return WebdavEntry(
        name: json['name'] as String? ?? '',
        path: json['path'] as String? ?? '',
        url: json['url'] as String? ?? '',
        isDir: json['is_dir'] == true,
        size: (json['size'] as num?)?.toInt(),
      );
    }).toList();
  }

  RustMediaIdentity? tryParseMediaIdentity(String folderName, String fileName) {
    try {
      return parseMediaIdentity(folderName, fileName);
    } catch (_) {
      return null;
    }
  }

  bool _ensureLoaded() {
    if (_library != null && _bindingsReady) return true;
    if (_loadError != null) return false;
    try {
      _library ??= Platform.isAndroid
          ? ffi.DynamicLibrary.open('libplayer_core.so')
          : ffi.DynamicLibrary.open(_desktopLibraryName);
      _scanLocalVideosJson = _library!
          .lookupFunction<_RustStringFn, _RustStringDart>(
              'player_core_scan_local_videos_json');
      _listLocalDirectoryJson = _library!
          .lookupFunction<_RustStringFn, _RustStringDart>(
              'player_core_list_local_directory_json');
      _parseMediaIdentityJson = _library!
          .lookupFunction<_RustTwoStringFn, _RustTwoStringDart>(
              'player_core_parse_media_identity_json');
      _tmdbGetJson = _library!
          .lookupFunction<_RustThreeStringFn, _RustThreeStringDart>(
              'player_core_tmdb_get_json');
      _metadataPutJson = _library!
          .lookupFunction<_RustThreeStringFn, _RustThreeStringDart>(
              'player_core_metadata_put_json');
      _metadataGetAllJson = _library!
          .lookupFunction<_RustStringFn, _RustStringDart>(
              'player_core_metadata_get_all_json');
      _metadataReplaceAllJson = _library!
          .lookupFunction<_RustTwoStringFn, _RustTwoStringDart>(
              'player_core_metadata_replace_all_json');
      _parseWebdavEntriesJson = _library!
          .lookupFunction<_RustFourStringFn, _RustFourStringDart>(
              'player_core_parse_webdav_entries_json');
      _freeString = _library!.lookupFunction<_RustFreeFn, _RustFreeDart>(
          'player_core_free_string');
      return true;
    } catch (error) {
      _loadError = error;
      return false;
    }
  }

  void _ensureAvailable() {
    if (!_ensureLoaded()) {
      throw StateError('Rust core is not available: $_loadError');
    }
  }

  String get _desktopLibraryName {
    if (Platform.isWindows) return 'player_core.dll';
    if (Platform.isMacOS) return 'libplayer_core.dylib';
    return 'libplayer_core.so';
  }

  String _callString(_RustStringDart? function, List<String> args) {
    if (!_ensureLoaded() || function == null) {
      throw StateError('Rust core is not available: $_loadError');
    }
    final root = args.single.toNativeUtf8();
    try {
      return _decodeResponse(function(root));
    } finally {
      calloc.free(root);
    }
  }

  String _callTwoString(
      _RustTwoStringDart? function, String first, String second) {
    if (!_ensureLoaded() || function == null) {
      throw StateError('Rust core is not available: $_loadError');
    }
    final firstPtr = first.toNativeUtf8();
    final secondPtr = second.toNativeUtf8();
    try {
      return _decodeResponse(function(firstPtr, secondPtr));
    } finally {
      calloc
        ..free(firstPtr)
        ..free(secondPtr);
    }
  }

  String _callThreeString(_RustThreeStringDart? function, String first,
      String second, String third) {
    if (!_ensureLoaded() || function == null) {
      throw StateError('Rust core is not available: $_loadError');
    }
    final firstPtr = first.toNativeUtf8();
    final secondPtr = second.toNativeUtf8();
    final thirdPtr = third.toNativeUtf8();
    try {
      return _decodeResponse(function(firstPtr, secondPtr, thirdPtr));
    } finally {
      calloc
        ..free(firstPtr)
        ..free(secondPtr)
        ..free(thirdPtr);
    }
  }

  String _callFourString(_RustFourStringDart? function, String first,
      String second, String third, String fourth) {
    if (!_ensureLoaded() || function == null) {
      throw StateError('Rust core is not available: $_loadError');
    }
    final firstPtr = first.toNativeUtf8();
    final secondPtr = second.toNativeUtf8();
    final thirdPtr = third.toNativeUtf8();
    final fourthPtr = fourth.toNativeUtf8();
    try {
      return _decodeResponse(
          function(firstPtr, secondPtr, thirdPtr, fourthPtr));
    } finally {
      calloc
        ..free(firstPtr)
        ..free(secondPtr)
        ..free(thirdPtr)
        ..free(fourthPtr);
    }
  }

  String _decodeResponse(ffi.Pointer<Utf8> pointer) {
    if (pointer == ffi.nullptr) {
      throw StateError('Rust core returned a null response');
    }
    try {
      final responseText = pointer.toDartString();
      final response = jsonDecode(responseText) as Map<String, dynamic>;
      if (response['ok'] == true) {
        return response['data'] as String? ?? '';
      }
      throw StateError(
          response['error'] as String? ?? 'Unknown Rust core error');
    } finally {
      _freeString?.call(pointer);
    }
  }
}

List<RustScannedVideo> _rustScanLocalVideosWorker(List<String> args) {
  return RustCoreService._().scanLocalVideos(args[0]);
}

List<LocalEntry> _rustListLocalDirectoryWorker(List<String> args) {
  return RustCoreService._().listLocalDirectory(args[0]);
}

String _rustTmdbGetJsonWorker(List<String> args) {
  return RustCoreService._().tmdbGetJson(args[0], args[1], args[2]);
}

void _rustMetadataPutWorker(List<String> args) {
  RustCoreService._().metadataPut(args[0], args[1], args[2]);
}

String _rustMetadataGetAllJsonWorker(List<String> args) {
  final service = RustCoreService._();
  service._ensureAvailable();
  return service._callString(service._metadataGetAllJson, [args[0]]);
}

void _rustMetadataReplaceAllWorker(List<String> args) {
  final data = jsonDecode(args[1]) as Map<String, dynamic>;
  final values = data.map(
    (key, value) => MapEntry(
      key,
      MediaMetadata.fromJson(value as Map<String, dynamic>),
    ),
  );
  RustCoreService._().metadataReplaceAll(args[0], values);
}

class RustScannedVideo {
  const RustScannedVideo({
    required this.path,
    required this.fileName,
    required this.parentName,
    this.size,
  });

  final String path;
  final String fileName;
  final String parentName;
  final int? size;

  factory RustScannedVideo.fromJson(Map<String, dynamic> json) {
    return RustScannedVideo(
      path: json['path'] as String,
      fileName: json['file_name'] as String? ?? '',
      parentName: json['parent_name'] as String? ?? '',
      size: (json['size'] as num?)?.toInt(),
    );
  }
}

class RustMediaIdentity {
  const RustMediaIdentity({
    required this.rawTitle,
    required this.normalizedTitle,
    this.year,
    this.season,
    this.episode,
    required this.kind,
  });

  final String rawTitle;
  final String normalizedTitle;
  final int? year;
  final int? season;
  final int? episode;
  final String kind;

  factory RustMediaIdentity.fromJson(Map<String, dynamic> json) {
    return RustMediaIdentity(
      rawTitle: json['raw_title'] as String? ?? '',
      normalizedTitle: json['normalized_title'] as String? ?? '',
      year: (json['year'] as num?)?.toInt(),
      season: (json['season'] as num?)?.toInt(),
      episode: (json['episode'] as num?)?.toInt(),
      kind: json['kind'] as String? ?? 'Unknown',
    );
  }
}
