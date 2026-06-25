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
  _RustTwoStringDart? _mediaSeriesTitleJson;
  _RustTwoStringDart? _tmdbGetJson;
  _RustStringDart? _danmuLoadJson;
  _RustStringDart? _danmuVisibleJson;
  _RustStringDart? _danmuClearJson;
  _RustFourStringDart? _metadataPutJson;
  _RustThreeStringDart? _metadataCacheImagesJson;
  _RustStringDart? _metadataGetAllJson;
  _RustTwoStringDart? _metadataReplaceAllJson;
  _RustThreeStringDart? _metadataPruneJson;
  _RustStringDart? _appStateGetJson;
  _RustTwoStringDart? _appStatePutJson;
  _RustThreeStringDart? _metadataCachedImageJson;
  _RustTwoStringDart? _metadataPutCachedImageJson;
  _RustStringDart? _libraryHomeJson;
  _RustTwoStringDart? _libraryShowDetailJson;
  _RustStringDart? _libraryRecentJson;
  _RustFourStringDart? _parseWebdavEntriesJson;
  _RustFreeDart? _freeString;
  Object? _loadError;

  bool get available => _ensureLoaded();

  bool get _bindingsReady =>
      _scanLocalVideosJson != null &&
      _listLocalDirectoryJson != null &&
      _parseMediaIdentityJson != null &&
      _mediaSeriesTitleJson != null &&
      _tmdbGetJson != null &&
      _metadataPutJson != null &&
      _metadataCacheImagesJson != null &&
      _metadataGetAllJson != null &&
      _metadataReplaceAllJson != null &&
      _metadataPruneJson != null &&
      _appStateGetJson != null &&
      _appStatePutJson != null &&
      _metadataCachedImageJson != null &&
      _metadataPutCachedImageJson != null &&
      _libraryHomeJson != null &&
      _libraryShowDetailJson != null &&
      _libraryRecentJson != null &&
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

  String mediaSeriesTitle(SourceType sourceType, String path) {
    _ensureAvailable();
    final source = sourceType == SourceType.webdav ? 'webdav' : 'local';
    final text = _callTwoString(_mediaSeriesTitleJson, source, path);
    return jsonDecode(text) as String? ?? '';
  }

  String tmdbGetJson(String url, String accessToken) {
    _ensureAvailable();
    return _callTwoString(_tmdbGetJson, url, accessToken);
  }

  Future<String> tmdbGetJsonAsync(String url, String accessToken) {
    final args = [url, accessToken];
    return Isolate.run(() => _rustTmdbGetJsonWorker(args));
  }

  RustDanmuLoadResult danmuLoad(Map<String, dynamic> input) {
    _ensureAvailable();
    if (_danmuLoadJson == null) {
      throw StateError('Rust danmu is not available: missing load symbol');
    }
    final text = _callString(_danmuLoadJson, [jsonEncode(input)]);
    return RustDanmuLoadResult.fromJson(
        jsonDecode(text) as Map<String, dynamic>);
  }

  Future<RustDanmuLoadResult> danmuLoadAsync(Map<String, dynamic> input) {
    final args = [jsonEncode(input)];
    return Isolate.run(() => _rustDanmuLoadWorker(args));
  }

  List<RustDanmuRenderItem> danmuVisible(Map<String, dynamic> input) {
    _ensureAvailable();
    if (_danmuVisibleJson == null) {
      throw StateError('Rust danmu is not available: missing visible symbol');
    }
    final text = _callString(_danmuVisibleJson, [jsonEncode(input)]);
    final data = jsonDecode(text) as Map<String, dynamic>;
    final items = data['items'] as List<dynamic>? ?? const [];
    return items
        .map((value) =>
            RustDanmuRenderItem.fromJson(value as Map<String, dynamic>))
        .toList(growable: false);
  }

  void danmuClear(int sessionId) {
    if (sessionId <= 0) return;
    _ensureAvailable();
    if (_danmuClearJson == null) return;
    _callString(_danmuClearJson, [jsonEncode(sessionId)]);
  }

  void metadataPut(
      String dbPath, String titleKey, String itemId, String metadataJson) {
    _ensureAvailable();
    _callFourString(_metadataPutJson, dbPath, titleKey, itemId, metadataJson);
  }

  Future<void> metadataPutAsync(
      String dbPath, String titleKey, String itemId, String metadataJson) {
    final args = [dbPath, titleKey, itemId, metadataJson];
    return Isolate.run(() => _rustMetadataPutWorker(args));
  }

  void metadataCacheImages(
      String dbPath, String metadataJson, String imageBaseUrl) {
    _ensureAvailable();
    _callThreeString(
        _metadataCacheImagesJson, dbPath, metadataJson, imageBaseUrl);
  }

  Future<void> metadataCacheImagesAsync(
      String dbPath, String metadataJson, String imageBaseUrl) {
    final args = [dbPath, metadataJson, imageBaseUrl];
    return Isolate.run(() => _rustMetadataCacheImagesWorker(args));
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

  void metadataPrune(
      String dbPath, List<String> liveItemIds, List<String> liveTitleKeys) {
    _ensureAvailable();
    _callThreeString(
      _metadataPruneJson,
      dbPath,
      jsonEncode(liveItemIds),
      jsonEncode(liveTitleKeys),
    );
  }

  Future<void> metadataPruneAsync(
      String dbPath, List<String> liveItemIds, List<String> liveTitleKeys) {
    final args = [dbPath, jsonEncode(liveItemIds), jsonEncode(liveTitleKeys)];
    return Isolate.run(() => _rustMetadataPruneWorker(args));
  }

  String appStateGet(String dbPath) {
    _ensureAvailable();
    return _callString(_appStateGetJson, [dbPath]);
  }

  Future<String> appStateGetAsync(String dbPath) {
    final args = [dbPath];
    return Isolate.run(() => _rustAppStateGetWorker(args));
  }

  void appStatePut(String dbPath, String stateJson) {
    _ensureAvailable();
    _callTwoString(_appStatePutJson, dbPath, stateJson);
  }

  Future<void> appStatePutAsync(String dbPath, String stateJson) {
    final args = [dbPath, stateJson];
    return Isolate.run(() => _rustAppStatePutWorker(args));
  }

  Uint8List? metadataCachedImage(String dbPath, String imagePath, String size) {
    _ensureAvailable();
    final text = _callThreeString(
      _metadataCachedImageJson,
      dbPath,
      imagePath,
      size,
    );
    final value = jsonDecode(text);
    if (value is! Map<String, dynamic>) return null;
    final encoded = value['bytesBase64'] as String?;
    if (encoded == null || encoded.isEmpty) return null;
    return base64Decode(encoded);
  }

  Future<Uint8List?> metadataCachedImageAsync(
      String dbPath, String imagePath, String size) {
    final args = [dbPath, imagePath, size];
    return Isolate.run(() => _rustMetadataCachedImageWorker(args));
  }

  void metadataPutCachedImage(
    String dbPath,
    String imagePath,
    String size,
    String url,
    String? contentType,
    Uint8List bytes,
  ) {
    _ensureAvailable();
    final text = jsonEncode({
      'path': imagePath,
      'size': size,
      'url': url,
      'contentType': contentType,
      'bytesBase64': base64Encode(bytes),
    });
    _callTwoString(_metadataPutCachedImageJson, dbPath, text);
  }

  Future<void> metadataPutCachedImageAsync(
    String dbPath,
    String imagePath,
    String size,
    String url,
    String? contentType,
    Uint8List bytes,
  ) {
    final args = [
      dbPath,
      imagePath,
      size,
      url,
      contentType ?? '',
      base64Encode(bytes),
    ];
    return Isolate.run(() => _rustMetadataPutCachedImageWorker(args));
  }

  String libraryHomeJson(String dbPath) {
    _ensureAvailable();
    return _callString(_libraryHomeJson, [dbPath]);
  }

  Future<String> libraryHomeJsonAsync(String dbPath) {
    final args = [dbPath];
    return Isolate.run(() => _rustLibraryHomeJsonWorker(args));
  }

  String libraryShowDetailJson(String dbPath, String folderKey) {
    _ensureAvailable();
    return _callTwoString(_libraryShowDetailJson, dbPath, folderKey);
  }

  Future<String> libraryShowDetailJsonAsync(String dbPath, String folderKey) {
    final args = [dbPath, folderKey];
    return Isolate.run(() => _rustLibraryShowDetailJsonWorker(args));
  }

  String libraryRecentJson(String dbPath) {
    _ensureAvailable();
    return _callString(_libraryRecentJson, [dbPath]);
  }

  Future<String> libraryRecentJsonAsync(String dbPath) {
    final args = [dbPath];
    return Isolate.run(() => _rustLibraryRecentJsonWorker(args));
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
      _library ??= _openNativeLibrary();
      _scanLocalVideosJson = _library!
          .lookupFunction<_RustStringFn, _RustStringDart>(
              'player_core_scan_local_videos_json');
      _listLocalDirectoryJson = _library!
          .lookupFunction<_RustStringFn, _RustStringDart>(
              'player_core_list_local_directory_json');
      _parseMediaIdentityJson = _library!
          .lookupFunction<_RustTwoStringFn, _RustTwoStringDart>(
              'player_core_parse_media_identity_json');
      _mediaSeriesTitleJson =
          _lookupOptionalTwoString('player_core_media_series_title_json');
      _tmdbGetJson = _library!
          .lookupFunction<_RustTwoStringFn, _RustTwoStringDart>(
              'player_core_tmdb_get_json');
      _danmuLoadJson = _lookupOptionalString('player_core_danmu_load_json');
      _danmuVisibleJson =
          _lookupOptionalString('player_core_danmu_visible_json');
      _danmuClearJson = _lookupOptionalString('player_core_danmu_clear_json');
      _metadataPutJson = _library!
          .lookupFunction<_RustFourStringFn, _RustFourStringDart>(
              'player_core_metadata_put_json');
      _metadataCacheImagesJson = _library!
          .lookupFunction<_RustThreeStringFn, _RustThreeStringDart>(
              'player_core_metadata_cache_images_json');
      _metadataGetAllJson = _library!
          .lookupFunction<_RustStringFn, _RustStringDart>(
              'player_core_metadata_get_all_json');
      _metadataReplaceAllJson = _library!
          .lookupFunction<_RustTwoStringFn, _RustTwoStringDart>(
              'player_core_metadata_replace_all_json');
      _metadataPruneJson = _library!
          .lookupFunction<_RustThreeStringFn, _RustThreeStringDart>(
              'player_core_metadata_prune_json');
      _appStateGetJson = _library!
          .lookupFunction<_RustStringFn, _RustStringDart>(
              'player_core_app_state_get_json');
      _appStatePutJson = _library!
          .lookupFunction<_RustTwoStringFn, _RustTwoStringDart>(
              'player_core_app_state_put_json');
      _metadataCachedImageJson = _library!
          .lookupFunction<_RustThreeStringFn, _RustThreeStringDart>(
              'player_core_metadata_cached_image_json');
      _metadataPutCachedImageJson = _library!
          .lookupFunction<_RustTwoStringFn, _RustTwoStringDart>(
              'player_core_metadata_put_cached_image_json');
      _libraryHomeJson = _library!
          .lookupFunction<_RustStringFn, _RustStringDart>(
              'player_core_library_home_json');
      _libraryShowDetailJson = _library!
          .lookupFunction<_RustTwoStringFn, _RustTwoStringDart>(
              'player_core_library_show_detail_json');
      _libraryRecentJson = _library!
          .lookupFunction<_RustStringFn, _RustStringDart>(
              'player_core_library_recent_json');
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

  ffi.DynamicLibrary _openNativeLibrary() {
    if (Platform.isAndroid) {
      return ffi.DynamicLibrary.open('libplayer_core.so');
    }

    final name = _desktopLibraryName;
    final cwd = Directory.current.path;
    final candidates = [
      name,
      p.join(cwd, name),
      p.normalize(p.join(cwd, '..', '..', 'target', 'debug', name)),
      p.normalize(p.join(cwd, '..', '..', 'target', 'release', name)),
    ];

    Object? lastError;
    for (final candidate in candidates) {
      try {
        return ffi.DynamicLibrary.open(candidate);
      } catch (error) {
        lastError = error;
      }
    }
    throw ArgumentError('Failed to load dynamic library $name: $lastError');
  }

  _RustStringDart? _lookupOptionalString(String name) {
    try {
      return _library!.lookupFunction<_RustStringFn, _RustStringDart>(name);
    } catch (_) {
      return null;
    }
  }

  _RustTwoStringDart? _lookupOptionalTwoString(String name) {
    try {
      return _library!
          .lookupFunction<_RustTwoStringFn, _RustTwoStringDart>(name);
    } catch (_) {
      return null;
    }
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
  return RustCoreService._().tmdbGetJson(args[0], args[1]);
}

RustDanmuLoadResult _rustDanmuLoadWorker(List<String> args) {
  return RustCoreService._()
      .danmuLoad(jsonDecode(args[0]) as Map<String, dynamic>);
}

void _rustMetadataPutWorker(List<String> args) {
  RustCoreService._().metadataPut(args[0], args[1], args[2], args[3]);
}

void _rustMetadataCacheImagesWorker(List<String> args) {
  RustCoreService._().metadataCacheImages(args[0], args[1], args[2]);
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

void _rustMetadataPruneWorker(List<String> args) {
  final liveItemIds = (jsonDecode(args[1]) as List<dynamic>).cast<String>();
  final liveTitleKeys = (jsonDecode(args[2]) as List<dynamic>).cast<String>();
  RustCoreService._().metadataPrune(args[0], liveItemIds, liveTitleKeys);
}

String _rustAppStateGetWorker(List<String> args) {
  return RustCoreService._().appStateGet(args[0]);
}

void _rustAppStatePutWorker(List<String> args) {
  RustCoreService._().appStatePut(args[0], args[1]);
}

Uint8List? _rustMetadataCachedImageWorker(List<String> args) {
  return RustCoreService._().metadataCachedImage(args[0], args[1], args[2]);
}

void _rustMetadataPutCachedImageWorker(List<String> args) {
  RustCoreService._().metadataPutCachedImage(
    args[0],
    args[1],
    args[2],
    args[3],
    args[4].isEmpty ? null : args[4],
    base64Decode(args[5]),
  );
}

String _rustLibraryHomeJsonWorker(List<String> args) {
  return RustCoreService._().libraryHomeJson(args[0]);
}

String _rustLibraryShowDetailJsonWorker(List<String> args) {
  return RustCoreService._().libraryShowDetailJson(args[0], args[1]);
}

String _rustLibraryRecentJsonWorker(List<String> args) {
  return RustCoreService._().libraryRecentJson(args[0]);
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

class RustDanmuLoadResult {
  const RustDanmuLoadResult({
    required this.sessionId,
    required this.count,
    required this.matchedEpisodeId,
    required this.matchedTitle,
    required this.matchedEpisode,
    required this.logs,
  });

  final int sessionId;
  final int count;
  final String matchedEpisodeId;
  final String matchedTitle;
  final String matchedEpisode;
  final List<String> logs;

  factory RustDanmuLoadResult.fromJson(Map<String, dynamic> json) {
    return RustDanmuLoadResult(
      sessionId: (json['session_id'] as num?)?.toInt() ?? 0,
      count: (json['count'] as num?)?.toInt() ?? 0,
      matchedEpisodeId: json['matched_episode_id'] as String? ?? '',
      matchedTitle: json['matched_title'] as String? ?? '',
      matchedEpisode: json['matched_episode'] as String? ?? '',
      logs: (json['logs'] as List<dynamic>? ?? const [])
          .map((value) => value.toString())
          .toList(growable: false),
    );
  }
}

class RustDanmuRenderItem {
  const RustDanmuRenderItem({
    required this.id,
    required this.timeMs,
    required this.mode,
    required this.color,
    required this.text,
    required this.left,
    required this.top,
    required this.textWidth,
  });

  final int id;
  final int timeMs;
  final int mode;
  final int color;
  final String text;
  final double left;
  final double top;
  final double textWidth;

  factory RustDanmuRenderItem.fromJson(Map<String, dynamic> json) {
    return RustDanmuRenderItem(
      id: (json['id'] as num?)?.toInt() ?? 0,
      timeMs: (json['time_ms'] as num?)?.toInt() ?? 0,
      mode: (json['mode'] as num?)?.toInt() ?? 1,
      color: (json['color'] as num?)?.toInt() ?? 0xFFFFFF,
      text: json['text'] as String? ?? '',
      left: (json['left'] as num?)?.toDouble() ?? 0,
      top: (json['top'] as num?)?.toDouble() ?? 0,
      textWidth: (json['text_width'] as num?)?.toDouble() ?? 0,
    );
  }
}
