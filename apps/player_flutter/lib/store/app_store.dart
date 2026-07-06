part of 'package:player_flutter/main.dart';

enum SourcePathSelectionState { none, partial, full }

class AppStore extends ChangeNotifier {
  AppStore({this.scanner = const MediaScanService()});

  static const _tmdbAutoMatchFlagKey = 'tmdb_auto_match_complete';

  final MediaScanService scanner;
  final List<MediaSourceConfig> sources = [];
  final List<MediaItem> items = [];
  final Map<String, int> progress = {};
  final Map<String, int> durations = {};
  final Map<String, int> lastPlayedAt = {};
  final Map<String, String> folderOrientations = {};
  final Map<String, MediaMetadata> metadata = {};
  final Map<String, int> _itemIndexById = {};
  final Map<String, Set<String>> _itemPathsBySource = {};
  TmdbConfig tmdbConfig = const TmdbConfig();
  DanmuConfig danmuConfig = const DanmuConfig();
  SyncConfig? syncConfig;
  final List<String> versionDirectoryRegexes = [];
  final List<String> episodeRegexes = [];
  bool loaded = false;
  bool metadataRefreshing = false;
  int metadataRevision = 0;
  bool diagnosticLoggingEnabled = false;
  String tmdbLastStatus = '';
  final List<String> diagnosticLogs = [];
  int diagnosticLogCount = 0;
  Future<void> _diagnosticLogWriteChain = Future.value();
  Future<void> _metadataDatabaseWriteChain = Future.value();
  Future<void> _backgroundDatabaseWriteChain = Future.value();
  final Map<String, Uint8List?> _imageCache = {};
  final Map<String, Uint8List?> _videoCoverCache = {};
  final Map<String, Future<Uint8List?>> _videoCoverRequests = {};
  final Set<String> _imageCacheMetadataWriteKeys = {};
  Future<void> _remoteVideoCoverChain = Future.value();
  int _lastScanNotifyMs = 0;
  int _libraryRevision = 0;
  int _pathParseLogCount = 0;
  static const int _diagnosticLogPreviewLimit = 100;

  String _desktopAppFilesPath() {
    return p.join(p.dirname(Platform.resolvedExecutable), 'rplayer_data');
  }

  Future<Directory> get appFilesDirectory async {
    String? path;
    try {
      path = await appChannel.invokeMethod<String>('appFilesDir');
    } on MissingPluginException {
      path = _desktopAppFilesPath();
    }
    path ??= _desktopAppFilesPath();
    final dir = Directory(path);
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  Future<File> get configFile async {
    final dir = await appFilesDirectory;
    return File(p.join(dir.path, 'player_config.json'));
  }

  Future<File> get metadataDatabaseFile async {
    final dir = await appFilesDirectory;
    return File(p.join(dir.path, 'metadata.sqlite'));
  }

  Future<File> get diagnosticLogFile async {
    final dir = await appFilesDirectory;
    return File(p.join(dir.path, 'player_diagnostic.log'));
  }

  Future<Directory> get videoCoverDirectory async {
    final dir =
        Directory(p.join((await appFilesDirectory).path, 'video_covers'));
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  Future<void> load() async {
    final file = await configFile;
    if (await file.exists()) {
      final text = await file.readAsString();
      importSettingsJson(jsonDecode(text) as Map<String, dynamic>);
    }
    await loadDiagnosticLogState();
    addDiagnosticLog('app load started', category: 'app');
    if (await file.exists()) {
      addDiagnosticLog('settings file loaded: ${file.path}',
          category: 'config');
    }
    await loadMediaStateDatabase();
    await loadMetadataDatabase();
    loaded = true;
    notifyListeners();
    addDiagnosticLog(
      'app load finished: sources=${sources.length}, items=${items.length}, metadata=${metadata.length}',
      category: 'app',
    );
  }

  Future<void> save() async {
    addDiagnosticLog('save started', category: 'app');
    await saveSettings();
    await saveMediaStateDatabase();
    await pruneMetadataDatabase();
    addDiagnosticLog('save finished', category: 'app');
  }

  Future<void> saveSettings({bool logEvent = true}) async {
    final text = exportSettings();
    final file = await configFile;
    await file.writeAsString(text);
    if (logEvent) {
      addDiagnosticLog('settings saved: ${file.path}', category: 'config');
    }
  }

  Future<void> saveMediaStateDatabase() async {
    final stopwatch = Stopwatch()..start();
    try {
      final db = await metadataDatabaseFile;
      addDiagnosticLog(
        'database write media state started: sources=${sources.length}, items=${items.length}',
        category: 'database',
      );
      final text = await exportMediaStateAsync();
      await RustCoreService.instance.appStatePutAsync(db.path, text);
      addDiagnosticLog(
        'database write media state finished: db=${db.path}, sources=${sources.length}, items=${items.length}, bytes=${text.length}, elapsed=${stopwatch.elapsedMilliseconds}ms',
        category: 'database',
      );
    } catch (error) {
      addDiagnosticLog('media state database write failed: $error',
          category: 'database');
      rethrow;
    }
  }

  Future<void> loadMediaStateDatabase() async {
    final stopwatch = Stopwatch()..start();
    try {
      final db = await metadataDatabaseFile;
      addDiagnosticLog('database read media state started: ${db.path}',
          category: 'database');
      final text = await RustCoreService.instance.appStateGetAsync(db.path);
      if (text.trim().isNotEmpty && text.trim() != '{}') {
        final decoded = await Isolate.run(
          () => jsonDecode(text) as Map<String, dynamic>,
        );
        importMediaStateJson(decoded);
      }
      addDiagnosticLog(
        'database read media state finished: sources=${sources.length}, items=${items.length}, elapsed=${stopwatch.elapsedMilliseconds}ms',
        category: 'database',
      );
    } catch (error) {
      addDiagnosticLog('media state database load failed: $error',
          category: 'database');
    }
  }

  Future<void> loadMetadataDatabase() async {
    final stopwatch = Stopwatch()..start();
    try {
      final db = await metadataDatabaseFile;
      addDiagnosticLog('database read metadata started: ${db.path}',
          category: 'database');
      final values =
          await RustCoreService.instance.metadataGetAllAsync(db.path);
      if (values.isNotEmpty) {
        metadata
          ..clear()
          ..addAll(values);
      } else if (metadata.isNotEmpty) {
        await RustCoreService.instance.metadataReplaceAllAsync(
          db.path,
          metadata,
        );
      }
      addDiagnosticLog(
        'database read metadata finished: rows=${values.length}, memory=${metadata.length}, elapsed=${stopwatch.elapsedMilliseconds}ms',
        category: 'database',
      );
    } catch (error) {
      addDiagnosticLog('metadata database load failed: $error',
          category: 'database');
    }
  }

  Future<void> pruneMetadataDatabase() async {
    final stopwatch = Stopwatch()..start();
    try {
      final liveItemIds = items.map((item) => item.id).toSet().toList();
      metadata.removeWhere((itemId, _) => !liveItemIds.contains(itemId));
      final db = await metadataDatabaseFile;
      addDiagnosticLog(
        'database prune metadata started: liveItems=${liveItemIds.length}',
        category: 'database',
      );
      await RustCoreService.instance.metadataPruneAsync(
        db.path,
        liveItemIds,
        const [],
      );
      addDiagnosticLog(
        'database prune metadata finished: memory=${metadata.length}, elapsed=${stopwatch.elapsedMilliseconds}ms',
        category: 'database',
      );
    } catch (error) {
      addDiagnosticLog('metadata database prune failed: $error',
          category: 'database');
    }
  }

  Future<void> saveMetadataToDatabase(
      String titleKey, String itemId, MediaMetadata value) async {
    final write = _metadataDatabaseWriteChain.then(
      (_) => _saveMetadataToDatabaseNow(titleKey, itemId, value),
    );
    _metadataDatabaseWriteChain = write.catchError((_) {});
    await write;
  }

  Future<void> _saveMetadataToDatabaseNow(
      String titleKey, String itemId, MediaMetadata value) async {
    final stopwatch = Stopwatch()..start();
    try {
      final db = await metadataDatabaseFile;
      final metadataJson = jsonEncode(value.toJson());
      final homeImageJson = jsonEncode(homeImageCacheMetadata(value));
      addDiagnosticLog(
        'database write metadata started: item=$itemId, titleKey=$titleKey, tmdb=${value.tmdbId}, type=${value.mediaType}',
        category: 'database',
      );
      await RustCoreService.instance.metadataPutAsync(
        db.path,
        titleKey,
        itemId,
        metadataJson,
      );
      addDiagnosticLog(
        'database write metadata core finished: item=$itemId, bytes=${metadataJson.length}',
        category: 'database',
      );
      _cacheHomePosterInBackground(
        dbPath: db.path,
        itemId: itemId,
        value: value,
        metadataJson: homeImageJson,
      );
      addDiagnosticLog(
        'database write metadata finished: item=$itemId, elapsed=${stopwatch.elapsedMilliseconds}ms',
        category: 'database',
      );
    } catch (error) {
      addDiagnosticLog('metadata database write failed: $error',
          category: 'database');
    }
  }

  Future<void> waitForPendingDatabaseWrites() async {
    await _metadataDatabaseWriteChain.catchError((_) {});
    await _backgroundDatabaseWriteChain.catchError((_) {});
  }

  Map<String, dynamic> homeImageCacheMetadata(MediaMetadata value) => {
        'posterPath': value.posterPath,
      };

  void _cacheHomePosterInBackground({
    required String dbPath,
    required String itemId,
    required MediaMetadata value,
    required String metadataJson,
  }) {
    final posterPath = value.posterPath?.trim();
    if (posterPath?.isNotEmpty != true) return;
    final cacheKey = 'w500:${_normalizedImagePath(posterPath!)}';
    if (!_imageCacheMetadataWriteKeys.add(cacheKey)) return;
    addDiagnosticLog(
      'database write image cache metadata queued: item=$itemId, poster=${value.posterPath}',
      category: 'database',
    );
    final write = _backgroundDatabaseWriteChain.catchError((_) {}).then(
      (_) async {
        try {
          await RustCoreService.instance.metadataCacheImagesAsync(
            dbPath,
            metadataJson,
            tmdbConfig.imageBaseUrl,
          );
          addDiagnosticLog(
            'database write image cache metadata finished: item=$itemId, jsonBytes=${metadataJson.length}',
            category: 'database',
          );
        } catch (error) {
          addDiagnosticLog(
            'database write image cache metadata failed: item=$itemId - $error',
            category: 'database',
          );
        }
      },
    );
    _backgroundDatabaseWriteChain = write.catchError((_) {});
    unawaited(write);
  }

  String _normalizedImagePath(String value) {
    final trimmed = value.trim();
    return trimmed.startsWith('/') ? trimmed : '/$trimmed';
  }

  Future<void> reloadDatabaseBackedState() async {
    addDiagnosticLog('database backed state reload requested',
        category: 'database');
    await loadMediaStateDatabase();
    await loadMetadataDatabase();
    notifyListeners();
  }

  Future<void> replaceMetadataDatabase() async {
    final db = await metadataDatabaseFile;
    addDiagnosticLog('database refresh metadata started: ${db.path}',
        category: 'database');
    final groups = mediaFolderGroups(items);
    var written = 0;
    for (final group in groups) {
      for (final item in group.items) {
        final value = metadata[item.id];
        if (value == null) continue;
        await saveMetadataToDatabase(group.key, item.id, value);
        written++;
      }
    }
    await pruneMetadataDatabase();
    addDiagnosticLog('database refresh metadata finished: written=$written',
        category: 'database');
  }

  String exportState() => exportSettings();

  String exportSettings() {
    return const JsonEncoder.withIndent('  ').convert({
      'version': 2,
      'tmdbConfig': tmdbConfig.toJson(),
      'danmuConfig': danmuConfig.toJson(),
      'syncConfig': syncConfig?.toJson(),
      'versionDirectoryRegexes': versionDirectoryRegexes,
      'episodeRegexes': episodeRegexes,
      'diagnosticLoggingEnabled': diagnosticLoggingEnabled,
    });
  }

  String exportMediaState() {
    return const JsonEncoder.withIndent('  ').convert({
      'version': 1,
      'sources': sources.map((source) => source.toJson()).toList(),
      'items': items.map((item) => item.toJson()).toList(),
      'progress': progress,
      'durations': durations,
      'lastPlayedAt': lastPlayedAt,
      'folderOrientations': folderOrientations,
    });
  }

  Future<String> exportMediaStateAsync() {
    final state = {
      'version': 1,
      'sources': sources.map((source) => source.toJson()).toList(),
      'items': items.map((item) => item.toJson()).toList(),
      'progress': Map<String, int>.from(progress),
      'durations': Map<String, int>.from(durations),
      'lastPlayedAt': Map<String, int>.from(lastPlayedAt),
      'folderOrientations': Map<String, String>.from(folderOrientations),
    };
    return Isolate.run(() => const JsonEncoder.withIndent('  ').convert(state));
  }

  void importSettingsJson(Map<String, dynamic> json) {
    final tmdb = json['tmdbConfig'];
    tmdbConfig = tmdb == null
        ? const TmdbConfig()
        : TmdbConfig.fromJson(tmdb as Map<String, dynamic>);
    final danmu = json['danmuConfig'];
    danmuConfig = danmu == null
        ? const DanmuConfig()
        : DanmuConfig.fromJson(danmu as Map<String, dynamic>);
    final sync = json['syncConfig'];
    syncConfig =
        sync == null ? null : SyncConfig.fromJson(sync as Map<String, dynamic>);
    versionDirectoryRegexes
      ..clear()
      ..addAll(normalizeRegexPatterns(
          json['versionDirectoryRegexes'] as List<dynamic>? ?? const []));
    episodeRegexes
      ..clear()
      ..addAll(normalizeRegexPatterns(
          json['episodeRegexes'] as List<dynamic>? ?? const []));
    syncParserRegexesToCore(logErrors: false);
    diagnosticLoggingEnabled =
        json['diagnosticLoggingEnabled'] as bool? ?? false;
  }

  void importMediaStateJson(Map<String, dynamic> json) {
    sources
      ..clear()
      ..addAll(
        (json['sources'] as List<dynamic>? ?? []).map(
          (value) => MediaSourceConfig.fromJson(value as Map<String, dynamic>),
        ),
      );
    items
      ..clear()
      ..addAll(
        (json['items'] as List<dynamic>? ?? []).map(
          (value) => MediaItem.fromJson(value as Map<String, dynamic>),
        ),
      );
    rebuildItemIndex();
    progress
      ..clear()
      ..addAll((json['progress'] as Map<String, dynamic>? ?? {})
          .map((key, value) => MapEntry(key, value as int)));
    durations
      ..clear()
      ..addAll((json['durations'] as Map<String, dynamic>? ?? {})
          .map((key, value) => MapEntry(key, value as int)));
    lastPlayedAt
      ..clear()
      ..addAll((json['lastPlayedAt'] as Map<String, dynamic>? ?? {})
          .map((key, value) => MapEntry(key, value as int)));
    folderOrientations
      ..clear()
      ..addAll((json['folderOrientations'] as Map<String, dynamic>? ?? {}).map(
          (key, value) =>
              MapEntry(normalizeMediaFolderKey(key), value as String)));
  }

  Future<void> importState(String text, {bool persist = true}) async {
    final json = jsonDecode(text) as Map<String, dynamic>;
    importSettingsJson(json);
    if (persist) await saveSettings();
    notifyListeners();
  }

  Future<MediaSourceConfig> addLocalDirectory(String dir) async {
    addDiagnosticLog('add local source: $dir', category: 'source');
    final source = MediaSourceConfig.local(
      id: newId(),
      name: localSourceName(dir),
      directory: dir,
    );
    sources.add(source);
    await save();
    notifyListeners();
    return source;
  }

  Future<MediaSourceConfig> addWebdavSource(WebdavSourceDraft draft) async {
    addDiagnosticLog('add webdav source: ${draft.baseUrl}${draft.directory}',
        category: 'source');
    final source = MediaSourceConfig.webdav(
      id: newId(),
      name: draft.name.isEmpty ? 'WebDAV' : draft.name,
      baseUrl: draft.baseUrl,
      username: draft.username,
      password: draft.password,
      directory: normalizeRemoteDir(draft.directory),
    );
    sources.add(source);
    await save();
    notifyListeners();
    return source;
  }

  Future<void> updateWebdavSource(
      MediaSourceConfig source, WebdavSourceDraft draft) async {
    addDiagnosticLog('update webdav source: ${source.name}',
        category: 'source');
    final updated = source.copyWith(
      name: draft.name.isEmpty ? source.name : draft.name,
      baseUrl: draft.baseUrl,
      username: draft.username,
      password: draft.password,
      directory: normalizeRemoteDir(draft.directory),
    );
    replaceSource(updated);
    await save();
    notifyListeners();
  }

  Future<void> removeSource(MediaSourceConfig source) async {
    addDiagnosticLog('remove source: ${source.name}', category: 'source');
    final removedItems =
        items.where((item) => item.sourceId == source.id).toList();
    final removedItemIds = removedItems.map((item) => item.id).toSet();
    sources.removeWhere((value) => value.id == source.id);
    items.removeWhere((item) => item.sourceId == source.id);
    rebuildItemIndex();
    markLibraryChanged();
    for (final itemId in removedItemIds) {
      progress.remove(itemId);
      durations.remove(itemId);
      lastPlayedAt.remove(itemId);
      metadata.remove(itemId);
    }
    final liveFolderKeys = mediaFolderGroups(items)
        .map((group) => normalizeMediaFolderKey(group.key))
        .toSet();
    folderOrientations.removeWhere(
      (key, _) => !liveFolderKeys.contains(normalizeMediaFolderKey(key)),
    );
    notifyListeners();
    await deleteVideoCoversForItems(removedItems);
    await save();
  }

  Future<void> rescanAll({bool forceMetadataRefresh = false}) async {
    addDiagnosticLog('rescan all sources: ${sources.length}', category: 'scan');
    final existing = List<MediaSourceConfig>.from(sources);
    final scanned = <MediaItem>[];
    for (final source in existing) {
      scanned.addAll(await scanSourceItems(source));
    }
    items
      ..clear()
      ..addAll(scanned);
    rebuildItemIndex();
    markLibraryChanged();
    metadata.removeWhere((itemId, _) => !_itemIndexById.containsKey(itemId));
    await save();
    notifyListeners();
    unawaited(refreshMissingMetadata(force: forceMetadataRefresh));
  }

  Future<void> rescanSource(MediaSourceConfig source) async {
    addDiagnosticLog('rescan source: ${source.name}', category: 'scan');
    final scanned = await scanSourceItems(source);
    items.removeWhere((item) => item.sourceId == source.id);
    items.addAll(scanned);
    items.sort(compareMediaItems);
    rebuildItemIndex();
    markLibraryChanged();
    metadata.removeWhere((itemId, _) => !_itemIndexById.containsKey(itemId));
    await save();
    notifyListeners();
    unawaited(refreshMissingMetadata());
  }

  Future<void> scanSourceIntoItems(MediaSourceConfig source) async {
    final scanned = await scanSourceItems(source);
    for (final item in scanned) {
      addOrReplaceItem(item);
    }
    items.sort(compareMediaItems);
    rebuildItemIndex();
  }

  Future<List<MediaItem>> scanSourceItems(MediaSourceConfig source) async {
    final stopwatch = Stopwatch()..start();
    addDiagnosticLog('scan source started: ${source.name}', category: 'scan');
    syncParserRegexesToCore();
    var count = 0;
    final scanned = <MediaItem>[];
    await for (final item in scanner.scanSourceStream(source)) {
      scanned.add(item);
      count++;
      notifyScanProgress(count);
    }
    scanned.sort(compareMediaItems);
    addDiagnosticLog(
      'scan source finished: ${source.name}, items=$count, elapsed=${stopwatch.elapsedMilliseconds}ms',
      category: 'scan',
    );
    return scanned;
  }

  Future<void> addWebdavSelection(MediaSourceConfig source, WebdavEntry entry,
      {bool asSeries = false}) async {
    addDiagnosticLog('add webdav selection: ${entry.path}', category: 'scan');
    final normalizedPath =
        entry.isDir ? normalizeRemoteDir(entry.path) : entry.path;
    final selectedPaths = {...source.selectedPaths, normalizedPath}.toList()
      ..sort();
    final seriesPaths = asSeries
        ? ({...source.seriesPaths, normalizedPath}.toList()..sort())
        : source.seriesPaths;
    final updated = source.copyWith(
      selectedPaths: selectedPaths,
      seriesPaths: seriesPaths,
    );
    replaceSource(updated);
    syncParserRegexesToCore();

    if (entry.isDir) {
      final client = WebdavClient.fromSource(updated);
      var count = 0;
      await for (final video
          in client.scanVideosStream(entry.path, maxDepth: 8)) {
        addOrReplaceItem(applyManualSeriesPath(
            updated, MediaItem.webdav(source: updated, entry: video)));
        count++;
        notifyScanProgress(count);
      }
    } else if (isVideoName(entry.name)) {
      addOrReplaceItem(applyManualSeriesPath(
          updated, MediaItem.webdav(source: updated, entry: entry)));
      notifyScanProgress(1);
    }
    items.sort(compareMediaItems);
    rebuildItemIndex();
    markLibraryChanged();
    await save();
    notifyListeners();
    unawaited(refreshMissingMetadata());
  }

  Future<void> addLocalSelection(MediaSourceConfig source, LocalEntry entry,
      {bool asSeries = false}) async {
    addDiagnosticLog('add local selection: ${entry.path}', category: 'scan');
    final normalizedPath = entry.path;
    final selectedPaths = {...source.selectedPaths, normalizedPath}.toList()
      ..sort();
    final seriesPaths = asSeries
        ? ({...source.seriesPaths, normalizedPath}.toList()..sort())
        : source.seriesPaths;
    final updated = source.copyWith(
      selectedPaths: selectedPaths,
      seriesPaths: seriesPaths,
    );
    if (sources.any((value) => value.id == updated.id)) {
      replaceSource(updated);
    } else {
      sources.add(updated);
    }
    syncParserRegexesToCore();

    if (entry.isDir) {
      var count = 0;
      await for (final item
          in scanner.scanLocalPathStream(updated, entry.path)) {
        addOrReplaceItem(item);
        count++;
        notifyScanProgress(count);
      }
    } else if (isVideoName(entry.name)) {
      addOrReplaceItem(applyManualSeriesPath(
          updated, MediaItem.local(source: updated, path: entry.path)));
      notifyScanProgress(1);
    }
    items.sort(compareMediaItems);
    rebuildItemIndex();
    markLibraryChanged();
    await save();
    notifyListeners();
    unawaited(refreshMissingMetadata());
  }

  Future<void> setManualSeriesPath(
    MediaSourceConfig source,
    String path, {
    required bool isDir,
    required bool enabled,
  }) async {
    final normalizedPath = sourcePathIdentity(source, path, isDir: isDir);
    final selectedPaths = enabled
        ? {...source.selectedPaths, normalizedPath}.toList()
        : List<String>.from(source.selectedPaths);
    final seriesPaths = enabled
        ? {...source.seriesPaths, normalizedPath}.toList()
        : source.seriesPaths.where((value) => value != normalizedPath).toList();
    final updated = source.copyWith(
      selectedPaths: selectedPaths..sort(),
      seriesPaths: seriesPaths..sort(),
    );
    replaceSource(updated);
    await rescanSource(updated);
  }

  Future<void> removeLocalSelection(
      MediaSourceConfig source, LocalEntry entry) async {
    addDiagnosticLog('remove local selection: ${entry.path}', category: 'scan');
    await removeSelectedPath(source, entry.path);
  }

  Future<void> removeWebdavSelection(
      MediaSourceConfig source, WebdavEntry entry) async {
    addDiagnosticLog('remove webdav selection: ${entry.path}',
        category: 'scan');
    final normalizedPath =
        entry.isDir ? normalizeRemoteDir(entry.path) : entry.path;
    await removeSelectedPath(source, normalizedPath);
  }

  Future<void> removeSelectedPath(
    MediaSourceConfig source,
    String selectedPath,
  ) async {
    addDiagnosticLog(
      'remove selected path: ${source.name} $selectedPath',
      category: 'scan',
    );
    final normalizedPath =
        source.type == SourceType.webdav && selectedPath.endsWith('/')
            ? normalizeRemoteDir(selectedPath)
            : sourcePathIdentity(source, selectedPath);
    final pathIsDir = sourceStoredPathIsDir(source, normalizedPath);
    final removedSelectedPaths = selectedPathsCoveredBy(source, normalizedPath);
    final removedItemIds = <String>{};
    final removedItems = <MediaItem>[];
    items.removeWhere((item) {
      final itemPath = sourceItemPath(source, item);
      final groupPath = item.groupPath;
      final coveredByRemovedPath = sourcePathCovers(
            source,
            normalizedPath,
            itemPath,
            containerIsDir: pathIsDir,
            targetIsDir: false,
          ) ||
          (groupPath.isNotEmpty &&
              sourcePathCovers(
                source,
                normalizedPath,
                groupPath,
                containerIsDir: pathIsDir,
                targetIsDir: true,
              ));
      if (item.sourceId != source.id || !coveredByRemovedPath) {
        return false;
      }
      removedItemIds.add(item.id);
      removedItems.add(item);
      return true;
    });
    addDiagnosticLog(
      'remove selected path removed items=${removedItemIds.length}',
      category: 'scan',
    );
    bool keepSelectedPath(String path) {
      if (removedSelectedPaths.contains(path)) return false;
      final selectedPathIsDir = sourceStoredPathIsDir(source, path);
      if (!sourcePathCovers(
        source,
        path,
        normalizedPath,
        containerIsDir: selectedPathIsDir,
        targetIsDir: pathIsDir,
      )) {
        return true;
      }
      return items.any((item) =>
          item.sourceId == source.id &&
          sourcePathCovers(
            source,
            path,
            sourceItemPath(source, item),
            containerIsDir: selectedPathIsDir,
            targetIsDir: false,
          ));
    }

    final selectedPaths = source.selectedPaths.where(keepSelectedPath).toList();
    final seriesPaths = source.seriesPaths.where(keepSelectedPath).toList();
    replaceSource(source.copyWith(
      selectedPaths: selectedPaths..sort(),
      seriesPaths: seriesPaths..sort(),
    ));
    rebuildItemIndex();
    markLibraryChanged();
    for (final itemId in removedItemIds) {
      progress.remove(itemId);
      durations.remove(itemId);
      lastPlayedAt.remove(itemId);
      metadata.remove(itemId);
    }
    metadata.removeWhere((itemId, _) => !_itemIndexById.containsKey(itemId));
    final liveFolderKeys = mediaFolderGroups(items)
        .map((group) => normalizeMediaFolderKey(group.key))
        .toSet();
    folderOrientations.removeWhere(
      (key, _) => !liveFolderKeys.contains(normalizeMediaFolderKey(key)),
    );
    notifyListeners();
    await deleteVideoCoversForItems(removedItems);
    await save();
  }

  void addOrReplaceItem(MediaItem item) {
    final index = _itemIndexById[item.id];
    if (index == null) {
      _itemIndexById[item.id] = items.length;
      items.add(item);
    } else {
      items[index] = item;
    }
    _itemPathsBySource
        .putIfAbsent(item.sourceId, () => <String>{})
        .add(itemStoredPath(item));
    logMediaPathParse(item);
  }

  void rebuildItemIndex() {
    _itemIndexById
      ..clear()
      ..addEntries(
        items.indexed.map((entry) => MapEntry(entry.$2.id, entry.$1)),
      );
    _itemPathsBySource.clear();
    for (final item in items) {
      _itemPathsBySource
          .putIfAbsent(item.sourceId, () => <String>{})
          .add(itemStoredPath(item));
    }
  }

  void markLibraryChanged() {
    _libraryRevision++;
    if (!metadataRefreshing) return;
    metadataRefreshing = false;
    tmdbLastStatus = 'TMDB refresh cancelled: library changed';
    addDiagnosticLog(tmdbLastStatus, category: 'match');
  }

  String itemStoredPath(MediaItem item) {
    if (item.type == SourceType.webdav) {
      final prefix = '${item.sourceId}:';
      return item.id.startsWith(prefix) ? item.id.substring(prefix.length) : '';
    }
    return item.uri.replaceAll('\\', '/');
  }

  void logMediaPathParse(MediaItem item) {
    if (!diagnosticLoggingEnabled) return;
    _pathParseLogCount++;
    if (_pathParseLogCount > 20 && _pathParseLogCount % 500 != 0) return;
    final source = item.type == SourceType.webdav ? 'webdav' : 'local';
    addDiagnosticLog(
      'path parse result sample=$_pathParseLogCount source=$source item=${item.id} title="${item.title}" folder="${item.folderTitle}" match="${item.matchTitle}" year=${item.matchYear} season=${item.season} episode=${item.episode} kind=${item.mediaKind} size=${item.size}',
      category: 'parse',
    );
  }

  void notifyScanProgress(int count) {
    final now = DateTime.now().millisecondsSinceEpoch;
    if (count == 1 || count % 250 == 0 || now - _lastScanNotifyMs >= 700) {
      _lastScanNotifyMs = now;
      notifyListeners();
    }
  }

  bool sourcePathAdded(
    MediaSourceConfig source,
    String path, {
    required bool isDir,
  }) =>
      sourcePathSelectionState(source, path, isDir: isDir) !=
      SourcePathSelectionState.none;

  SourcePathSelectionState sourcePathSelectionState(
    MediaSourceConfig source,
    String path, {
    required bool isDir,
  }) {
    final identity = sourcePathIdentity(source, path, isDir: isDir);
    if (source.selectedPaths.contains(identity)) {
      return SourcePathSelectionState.full;
    }
    final sourcePaths = _itemPathsBySource[source.id];
    if (!isDir) {
      return sourcePaths?.contains(identity) == true
          ? SourcePathSelectionState.full
          : SourcePathSelectionState.none;
    }
    final hasSelectedChild = source.selectedPaths.any((selectedPath) =>
        selectedPath != identity &&
        sourcePathCovers(
          source,
          identity,
          selectedPath,
          containerIsDir: true,
          targetIsDir: sourceStoredPathIsDir(source, selectedPath),
        ));
    final hasVideoChild = sourcePaths?.any((itemPath) {
          return sourcePathCovers(
            source,
            identity,
            itemPath,
            containerIsDir: true,
            targetIsDir: false,
          );
        }) ==
        true;
    return hasSelectedChild || hasVideoChild
        ? SourcePathSelectionState.partial
        : SourcePathSelectionState.none;
  }

  MediaItem? itemById(String id) {
    final index = _itemIndexById[id];
    if (index == null || index < 0 || index >= items.length) return null;
    return items[index];
  }

  void replaceSource(MediaSourceConfig source) {
    final index = sources.indexWhere((value) => value.id == source.id);
    if (index >= 0) sources[index] = source;
  }

  Future<void> setSyncConfig(SyncConfig config) async {
    syncConfig = config;
    addDiagnosticLog('sync config updated: ${config.baseUrl}',
        category: 'sync');
    await saveSettings();
    notifyListeners();
  }

  Future<void> setTmdbConfig(TmdbConfig config) async {
    tmdbConfig = config.copyWith(apiBaseUrl: config.normalizedApiBaseUrl);
    addDiagnosticLog(
      'TMDB config updated: enabled=${tmdbConfig.enabled}, language=${tmdbConfig.language}, region=${tmdbConfig.region}, api=${tmdbConfig.normalizedApiBaseUrl}',
      category: 'tmdb',
    );
    await saveSettings();
    notifyListeners();
    unawaited(refreshMissingMetadata());
  }

  List<String> normalizeRegexPatterns(Iterable<dynamic> patterns) {
    final seen = <String>{};
    final normalized = <String>[];
    for (final value in patterns) {
      if (value is! String) continue;
      final pattern = value.trim();
      if (pattern.isEmpty || !seen.add(pattern)) continue;
      normalized.add(pattern);
    }
    return normalized;
  }

  void syncParserRegexesToCore({bool logErrors = true}) {
    try {
      RustCoreService.instance
          .setVersionDirectoryRegexes(versionDirectoryRegexes);
      RustCoreService.instance.setEpisodeRegexes(episodeRegexes);
    } catch (error) {
      if (logErrors) {
        addDiagnosticLog('parser regex sync failed: $error', category: 'parse');
      }
    }
  }

  Future<void> setVersionDirectoryRegexes(List<String> patterns) async {
    final normalized = normalizeRegexPatterns(patterns);
    RustCoreService.instance.setVersionDirectoryRegexes(normalized);
    versionDirectoryRegexes
      ..clear()
      ..addAll(normalized);
    addDiagnosticLog(
      'version regex config updated: count=${versionDirectoryRegexes.length}',
      category: 'parse',
    );
    await saveSettings();
    notifyListeners();
  }

  Future<void> addVersionDirectoryRegex(String pattern) async {
    await setVersionDirectoryRegexes([...versionDirectoryRegexes, pattern]);
  }

  Future<void> removeVersionDirectoryRegexAt(int index) async {
    if (index < 0 || index >= versionDirectoryRegexes.length) return;
    final next = List<String>.from(versionDirectoryRegexes)..removeAt(index);
    await setVersionDirectoryRegexes(next);
  }

  Future<void> setEpisodeRegexes(List<String> patterns) async {
    final normalized = normalizeRegexPatterns(patterns);
    RustCoreService.instance.setEpisodeRegexes(normalized);
    episodeRegexes
      ..clear()
      ..addAll(normalized);
    addDiagnosticLog(
      'episode regex config updated: count=${episodeRegexes.length}',
      category: 'parse',
    );
    await saveSettings();
    notifyListeners();
  }

  Future<void> addEpisodeRegex(String pattern) async {
    await setEpisodeRegexes([...episodeRegexes, pattern]);
  }

  Future<void> removeEpisodeRegexAt(int index) async {
    if (index < 0 || index >= episodeRegexes.length) return;
    final next = List<String>.from(episodeRegexes)..removeAt(index);
    await setEpisodeRegexes(next);
  }

  Future<void> setDanmuConfig(DanmuConfig config) async {
    danmuConfig = config.copyWith(
      apiBaseUrl: config.normalizedApiBaseUrl,
      apiToken: config.normalizedApiToken,
    );
    addDiagnosticLog(
      'danmu config updated: enabled=${danmuConfig.enabled}, api=${danmuConfig.requestBaseUrl}, maxLines=${danmuConfig.maxLines}, topPadding=${danmuConfig.topPadding.round()}',
      category: 'danmu',
    );
    notifyListeners();
    await saveSettings();
  }

  Future<void> setDiagnosticLoggingEnabled(bool value) async {
    diagnosticLoggingEnabled = value;
    await saveSettings();
    notifyListeners();
    if (value) addDiagnosticLog('diagnostic logging enabled', category: 'log');
  }

  Future<void> refreshMissingMetadata({bool force = false}) async {
    if (!tmdbConfig.enabled) {
      addDiagnosticLog('metadata refresh skipped: TMDB disabled',
          category: 'match');
      return;
    }
    if (metadataRefreshing) {
      addDiagnosticLog('metadata refresh skipped: already running',
          category: 'match');
      return;
    }
    final stopwatch = Stopwatch()..start();
    final libraryRevision = _libraryRevision;
    metadataRefreshing = true;
    tmdbLastStatus = 'TMDB refresh started';
    addDiagnosticLog(
      'TMDB refresh started, force=$force, items=${items.length}, cached=${metadata.length}',
      category: 'match',
    );
    notifyListeners();
    try {
      final service = TmdbMetadataService(
        tmdbConfig,
        log: (message) => addDiagnosticLog(message, category: 'tmdb'),
      );
      await loadMetadataDatabase();
      final autoMatchFingerprint = _tmdbAutoMatchFingerprint();
      final autoMatchState = force ? null : await _tmdbAutoMatchState();
      if (!force &&
          _tmdbAutoMatchCompletedFor(autoMatchState, autoMatchFingerprint)) {
        tmdbLastStatus = 'TMDB refresh skipped: already tried current library';
        addDiagnosticLog(tmdbLastStatus, category: 'match');
        return;
      }
      final previousFailedItems =
          force ? const <String>{} : tmdbAutoMatchFailedItems(autoMatchState);
      final failedItems = <String>{};
      var matched = 0;
      var failed = 0;
      var skipped = 0;
      final targetItems = <MediaItem>[];
      var checked = 0;
      for (final item in List<MediaItem>.from(items)) {
        checked++;
        if (checked <= 20 || checked % 500 == 0) {
          addDiagnosticLog(
            'TMDB item queued check sample=$checked: ${describeMediaItem(item)}',
            category: 'match',
          );
        }
        final cached = metadata[item.id];
        if (!force && cached != null && metadataCompleteForItem(item, cached)) {
          skipped++;
          if (skipped <= 20 || skipped % 500 == 0) {
            addDiagnosticLog(
              'TMDB skip cached sample=$skipped: ${describeMediaItem(item)}',
              category: 'match',
            );
          }
          continue;
        }
        final failedKey = tmdbAutoMatchFailedItemKey(item);
        if (!force && previousFailedItems.contains(failedKey)) {
          failedItems.add(failedKey);
          skipped++;
          if (skipped <= 20 || skipped % 500 == 0) {
            addDiagnosticLog(
              'TMDB skip previous failed sample=$skipped: ${describeMediaItem(item)}',
              category: 'match',
            );
          }
          continue;
        }
        targetItems.add(item);
      }
      final targetGroups = mediaFolderGroups(
        targetItems,
        separateItemIds: explicitlySelectedItemIds(targetItems),
      );
      final allGroupsByKey = {
        for (final group in mediaFolderGroups(
          items,
          separateItemIds: explicitlySelectedItemIds(items),
        ))
          group.key: group,
      };
      final workerCount = _tmdbMatchWorkerCount(targetGroups.length, force);
      addDiagnosticLog(
        'TMDB match plan: targetItems=${targetItems.length}, targetGroups=${targetGroups.length}, workers=$workerCount',
        category: 'match',
      );

      final backgroundWrites = <Future<void>>[];
      var cursor = 0;
      var processedGroups = 0;
      var lastMetadataNotifyMs = DateTime.now().millisecondsSinceEpoch;
      Future<void> worker() async {
        while (true) {
          if (cursor >= targetGroups.length) return;
          final group = targetGroups[cursor++];
          if (!metadataRefreshStillCurrent(libraryRevision)) return;
          addDiagnosticLog(
            'TMDB worker group: ${group.title} key=${group.key} items=${group.items.length}',
            category: 'match',
          );
          Map<String, MediaMetadata> values;
          try {
            final fullGroup = allGroupsByKey[group.key] ?? group;
            final cachedTitle = mediaGroupMetadata(fullGroup, metadata);
            values = await service.lookupGroup(
              tmdbLookupGroup(group, cachedTitle: cachedTitle),
              cachedTitle: cachedTitle,
            );
          } catch (error) {
            if (!metadataRefreshStillCurrent(libraryRevision)) return;
            failed += group.items.length;
            failedItems.addAll(group.items.map(tmdbAutoMatchFailedItemKey));
            tmdbLastStatus = 'TMDB error: ${group.title} - $error';
            addDiagnosticLog(tmdbLastStatus, category: 'match');
            notifyListeners();
            continue;
          }
          if (!metadataRefreshStillCurrent(libraryRevision)) return;
          if (values.isNotEmpty) {
            final entries = values.entries
                .where((entry) => _itemIndexById.containsKey(entry.key))
                .toList(growable: false);
            for (final entry in entries) {
              if (!metadataRefreshStillCurrent(libraryRevision)) return;
              metadata[entry.key] = entry.value;
              metadataRevision++;
              matched++;
              addDiagnosticLog(
                'TMDB matched item=${entry.key} tmdb=${entry.value.tmdbId} type=${entry.value.mediaType} episode=${entry.value.episodeName} poster=${entry.value.posterPath} still=${entry.value.stillPath}',
                category: 'match',
              );
            }
            if (entries.isNotEmpty) {
              final first = entries.first;
              await saveMetadataToDatabase(group.key, first.key, first.value);
              notifyListeners();
              await Future<void>.delayed(Duration.zero);
            }
            final remaining = entries.skip(1).toList(growable: false);
            if (remaining.isNotEmpty) {
              backgroundWrites.add(_saveMetadataEntriesForLibraryRevision(
                group.key,
                remaining,
                libraryRevision,
              ));
            }
          } else {
            failed += group.items.length;
            failedItems.addAll(group.items.map(tmdbAutoMatchFailedItemKey));
            tmdbLastStatus = 'TMDB no match: ${group.title}';
            addDiagnosticLog(tmdbLastStatus, category: 'match');
          }
          processedGroups++;
          final now = DateTime.now().millisecondsSinceEpoch;
          if (processedGroups % 5 == 0 || now - lastMetadataNotifyMs >= 1000) {
            lastMetadataNotifyMs = now;
            notifyListeners();
            await Future<void>.delayed(Duration.zero);
          }
        }
      }

      await Future.wait([
        for (var i = 0; i < workerCount; i++) worker(),
      ]);
      if (!metadataRefreshStillCurrent(libraryRevision)) return;
      if (backgroundWrites.isNotEmpty) {
        unawaited(_finishTmdbAutoMatchAfterBackgroundWrites(
          backgroundWrites,
          autoMatchFingerprint,
          Set<String>.from(failedItems),
          libraryRevision,
          stopwatch,
          matched,
          failed,
          skipped,
        ));
        tmdbLastStatus =
            'TMDB refresh visible data ready: $matched matched, $failed failed, $skipped skipped';
        addDiagnosticLog(tmdbLastStatus, category: 'match');
        return;
      }
      await _markTmdbAutoMatchComplete(autoMatchFingerprint, failedItems);
      metadataRevision++;
      tmdbLastStatus =
          'TMDB refresh done: $matched matched, $failed failed, $skipped skipped';
      addDiagnosticLog(
        '$tmdbLastStatus, elapsed=${stopwatch.elapsedMilliseconds}ms',
        category: 'match',
      );
    } finally {
      if (libraryRevision == _libraryRevision) {
        metadataRefreshing = false;
        notifyListeners();
      }
    }
  }

  int _tmdbMatchWorkerCount(int groupCount, bool force) {
    if (groupCount <= 0) return 0;
    final maxWorkers = force ? 8 : 6;
    return math.min(maxWorkers, groupCount);
  }

  bool metadataRefreshStillCurrent(int libraryRevision) =>
      metadataRefreshing && libraryRevision == _libraryRevision;

  Future<void> _saveMetadataEntriesForLibraryRevision(
    String titleKey,
    List<MapEntry<String, MediaMetadata>> entries,
    int libraryRevision,
  ) async {
    var written = 0;
    for (final entry in entries) {
      if (libraryRevision != _libraryRevision ||
          !_itemIndexById.containsKey(entry.key)) {
        addDiagnosticLog(
          'TMDB background metadata write cancelled: written=$written',
          category: 'match',
        );
        return;
      }
      await saveMetadataToDatabase(titleKey, entry.key, entry.value);
      written++;
    }
    addDiagnosticLog(
      'TMDB background metadata write finished: written=$written',
      category: 'match',
    );
  }

  Future<void> _finishTmdbAutoMatchAfterBackgroundWrites(
    List<Future<void>> writes,
    String autoMatchFingerprint,
    Set<String> failedItems,
    int libraryRevision,
    Stopwatch stopwatch,
    int matched,
    int failed,
    int skipped,
  ) async {
    try {
      await Future.wait(writes);
      if (libraryRevision != _libraryRevision) return;
      await _markTmdbAutoMatchComplete(autoMatchFingerprint, failedItems);
      metadataRevision++;
      tmdbLastStatus =
          'TMDB refresh done: $matched matched, $failed failed, $skipped skipped';
      addDiagnosticLog(
        '$tmdbLastStatus, elapsed=${stopwatch.elapsedMilliseconds}ms',
        category: 'match',
      );
      notifyListeners();
    } catch (error) {
      addDiagnosticLog('TMDB background metadata write failed: $error',
          category: 'match');
    }
  }

  Set<String> explicitlySelectedItemIds(Iterable<MediaItem> values) {
    final sourceById = {for (final source in sources) source.id: source};
    return values
        .where((item) {
          final source = sourceById[item.sourceId];
          return source != null && itemExplicitlySelectedFile(source, item);
        })
        .map((item) => item.id)
        .toSet();
  }

  MediaFolderGroup tmdbLookupGroup(
    MediaFolderGroup group, {
    MediaMetadata? cachedTitle,
  }) {
    if (cachedTitle != null || group.items.length != 1) return group;
    final item = group.representative;
    final source =
        sources.where((source) => source.id == item.sourceId).firstOrNull;
    final explicitlySelectedFile =
        source != null && itemExplicitlySelectedFile(source, item);
    final usefulFileTitle =
        isUsefulTmdbSearchQuery(tmdbSearchQueryFromText(item.title));
    if (!explicitlySelectedFile && !usefulFileTitle) {
      return group;
    }
    final lookupItem = singleFileTmdbLookupItem(item);
    return MediaFolderGroup(
      key: group.key,
      title: mediaGroupDisplayTitle(lookupItem),
      items: [lookupItem],
      representative: lookupItem,
      latestPlayedAt: group.latestPlayedAt,
    );
  }

  String _tmdbAutoMatchFingerprint() {
    final values = items.map(tmdbAutoMatchItemFingerprint).toList()..sort();
    return [
      'schema=$currentMetadataSchemaVersion',
      'language=${tmdbConfig.language}',
      'region=${tmdbConfig.region}',
      'api=${tmdbConfig.normalizedApiBaseUrl}',
      'token=${_stableTextHash(tmdbConfig.accessToken.trim())}',
      'count=${items.length}',
      ...values,
    ].join('\n');
  }

  String _stableTextHash(String value) {
    var hash = 0x811c9dc5;
    for (final codeUnit in value.codeUnits) {
      hash ^= codeUnit;
      hash = (hash * 0x01000193) & 0xffffffff;
    }
    return hash.toRadixString(16).padLeft(8, '0');
  }

  Future<Map<String, dynamic>?> _tmdbAutoMatchState() async {
    try {
      final db = await metadataDatabaseFile;
      return await RustCoreService.instance.metadataGetFlagAsync(
        db.path,
        _tmdbAutoMatchFlagKey,
      );
    } catch (error) {
      addDiagnosticLog('TMDB auto-match flag read failed: $error',
          category: 'match');
      return null;
    }
  }

  bool _tmdbAutoMatchCompletedFor(
      Map<String, dynamic>? state, String fingerprint) {
    return state?['fingerprint'] == fingerprint;
  }

  Future<void> _markTmdbAutoMatchComplete(
    String fingerprint,
    Set<String> failedItems,
  ) async {
    try {
      final db = await metadataDatabaseFile;
      await RustCoreService.instance.metadataPutFlagAsync(
        db.path,
        _tmdbAutoMatchFlagKey,
        {
          'fingerprint': fingerprint,
          'itemCount': items.length,
          'schemaVersion': currentMetadataSchemaVersion,
          'failedItems': failedItems.toList()..sort(),
          'completedAt': DateTime.now().millisecondsSinceEpoch,
        },
      );
    } catch (error) {
      addDiagnosticLog('TMDB auto-match flag write failed: $error',
          category: 'match');
    }
  }

  Future<List<TmdbSearchCandidate>> searchTmdbCandidates(String query) async {
    if (!tmdbConfig.enabled) {
      throw StateError('请先在设置中配置 TMDB 访问令牌');
    }
    final service = TmdbMetadataService(
      tmdbConfig,
      log: (message) => addDiagnosticLog(message, category: 'tmdb'),
    );
    return service.searchCandidates(query);
  }

  Future<void> rematchLibraryDetail(
    LibraryShowDetail detail,
    TmdbSearchCandidate candidate,
  ) async {
    if (!tmdbConfig.enabled) {
      throw StateError('请先在设置中配置 TMDB 访问令牌');
    }
    final groupItems = detail.files
        .map((file) => itemById(file.itemId))
        .whereType<MediaItem>()
        .toList()
      ..sort(compareMediaItems);
    if (groupItems.isEmpty) {
      throw StateError('没有找到可替换的本地视频');
    }
    final representative = groupItems.first;
    final group = MediaFolderGroup(
      key: detail.folderKey,
      title: candidate.title.trim().isNotEmpty
          ? candidate.title
          : mediaGroupDisplayTitle(representative),
      items: groupItems,
      representative: representative,
      latestPlayedAt: groupItems.fold<int>(
        0,
        (latest, item) => math.max(latest, lastPlayedAt[item.id] ?? 0),
      ),
    );
    final stopwatch = Stopwatch()..start();
    metadataRefreshing = true;
    tmdbLastStatus = '手动识别中：${candidate.title}';
    addDiagnosticLog(
      'manual TMDB rematch started: folder=${detail.folderKey}, type=${candidate.mediaType}, tmdb=${candidate.tmdbId}, items=${group.items.length}',
      category: 'match',
    );
    notifyListeners();
    try {
      final service = TmdbMetadataService(
        tmdbConfig,
        log: (message) => addDiagnosticLog(message, category: 'tmdb'),
      );
      final values = await service.lookupGroupByCandidate(group, candidate);
      if (values.isEmpty) {
        throw StateError('TMDB 没有返回可写入的数据');
      }
      for (final item in group.items) {
        metadata.remove(item.id);
      }
      var written = 0;
      for (final entry in values.entries) {
        metadata[entry.key] = entry.value;
        await saveMetadataToDatabase(group.key, entry.key, entry.value);
        written++;
      }
      await pruneMetadataDatabase();
      await loadMetadataDatabase();
      metadataRevision++;
      tmdbLastStatus = '手动识别完成：${candidate.title}';
      addDiagnosticLog(
        'manual TMDB rematch finished: written=$written, elapsed=${stopwatch.elapsedMilliseconds}ms',
        category: 'match',
      );
    } catch (error) {
      tmdbLastStatus = '手动识别失败：$error';
      addDiagnosticLog(tmdbLastStatus, category: 'match');
      rethrow;
    } finally {
      metadataRefreshing = false;
      notifyListeners();
    }
  }

  Future<void> refreshLibraryDetail(LibraryShowDetail detail) async {
    if (!tmdbConfig.enabled) {
      throw StateError('请先在设置中配置 TMDB 访问令牌');
    }
    if (metadataRefreshing) {
      throw StateError('已有 TMDB 刷新正在进行');
    }
    final groupItems = detail.files
        .map((file) => itemById(file.itemId))
        .whereType<MediaItem>()
        .toList()
      ..sort(compareMediaItems);
    if (groupItems.isEmpty) {
      throw StateError('没有找到可刷新的本地视频');
    }
    final representative = groupItems.first;
    final title = detail.representative?.showTitle?.trim();
    final group = MediaFolderGroup(
      key: detail.folderKey,
      title: title?.isNotEmpty == true
          ? title!
          : mediaGroupDisplayTitle(representative),
      items: groupItems,
      representative: representative,
      latestPlayedAt: groupItems.fold<int>(
        0,
        (latest, item) => math.max(latest, lastPlayedAt[item.id] ?? 0),
      ),
    );
    final stopwatch = Stopwatch()..start();
    metadataRefreshing = true;
    tmdbLastStatus = '正在刷新：${group.title}';
    addDiagnosticLog(
      'single TMDB refresh started: folder=${detail.folderKey}, title=${group.title}, items=${group.items.length}',
      category: 'match',
    );
    notifyListeners();
    try {
      final service = TmdbMetadataService(
        tmdbConfig,
        log: (message) => addDiagnosticLog(message, category: 'tmdb'),
      );
      final values = await service.lookupGroup(group);
      if (values.isEmpty) {
        throw StateError('TMDB 没有返回可写入的数据');
      }
      for (final item in group.items) {
        metadata.remove(item.id);
      }
      var written = 0;
      for (final entry in values.entries) {
        metadata[entry.key] = entry.value;
        await saveMetadataToDatabase(group.key, entry.key, entry.value);
        written++;
      }
      await pruneMetadataDatabase();
      await loadMetadataDatabase();
      await save();
      metadataRevision++;
      tmdbLastStatus = '刷新完成：${group.title}';
      addDiagnosticLog(
        'single TMDB refresh finished: written=$written, elapsed=${stopwatch.elapsedMilliseconds}ms',
        category: 'match',
      );
    } catch (error) {
      tmdbLastStatus = '刷新失败：$error';
      addDiagnosticLog(tmdbLastStatus, category: 'match');
      rethrow;
    } finally {
      metadataRefreshing = false;
      notifyListeners();
    }
  }

  bool metadataCompleteForItem(MediaItem item, MediaMetadata value) {
    if (value.schemaVersion < currentMetadataSchemaVersion) return false;
    if (value.mediaType != 'tv') return true;
    final episode = inferredEpisodeNumber(item);
    if (episode == null) return true;
    final season = inferredSeasonNumber(item);
    final hasMatchedEpisode = value.episodeTmdbId != null ||
        value.episodeName?.trim().isNotEmpty == true ||
        value.episodeOverview?.trim().isNotEmpty == true ||
        value.releaseDate?.trim().isNotEmpty == true ||
        value.stillPath?.trim().isNotEmpty == true;
    if (hasMatchedEpisode) return true;
    return value.seasonEpisodes.any((entry) {
      final entryEpisode = (entry['episodeNumber'] as num?)?.toInt();
      if (entryEpisode != episode) return false;
      final entrySeason = (entry['seasonNumber'] as num?)?.toInt();
      return season == null || entrySeason == null || entrySeason == season;
    });
  }

  void addDiagnosticLog(String message, {String category = 'app'}) {
    if (!diagnosticLoggingEnabled) return;
    final time = DateTime.now().toIso8601String();
    final line = '$time [$category] $message';
    diagnosticLogs.add(line);
    diagnosticLogCount++;
    if (diagnosticLogs.length > _diagnosticLogPreviewLimit) {
      diagnosticLogs.removeRange(
        0,
        diagnosticLogs.length - _diagnosticLogPreviewLimit,
      );
    }
    _diagnosticLogWriteChain = _diagnosticLogWriteChain
        .catchError((_) {})
        .then((_) => appendDiagnosticLogLine(line));
  }

  Future<void> loadDiagnosticLogState() async {
    final file = await diagnosticLogFile;
    if (!await file.exists()) {
      diagnosticLogs.clear();
      diagnosticLogCount = 0;
      return;
    }
    final recent = <String>[];
    var count = 0;
    await for (final chunk in file
        .openRead()
        .transform(utf8.decoder)
        .transform(const LineSplitter())) {
      if (chunk.isEmpty) continue;
      count++;
      recent.add(chunk);
      if (recent.length > _diagnosticLogPreviewLimit) {
        recent.removeAt(0);
      }
    }
    diagnosticLogs
      ..clear()
      ..addAll(recent);
    diagnosticLogCount = count;
  }

  Future<void> appendDiagnosticLogLine(String line) async {
    final file = await diagnosticLogFile;
    await file.writeAsString('$line\n', mode: FileMode.append, flush: true);
  }

  Future<String> exportDiagnosticLogFile() async {
    await _diagnosticLogWriteChain;
    final timestamp = DateTime.now()
        .toIso8601String()
        .replaceAll(':', '-')
        .replaceAll('.', '-');
    final fileName = 'player_diagnostic_logs_$timestamp.txt';
    final source = await diagnosticLogFile;
    final bytes =
        await source.exists() ? await source.readAsBytes() : Uint8List(0);
    final picked = await FilePicker.platform.saveFile(
      dialogTitle: '导出诊断日志',
      fileName: fileName,
      type: FileType.custom,
      allowedExtensions: const ['txt'],
      bytes: bytes,
    );
    if (picked != null) return picked;
    final dir = await appFilesDirectory;
    final file = File(p.join(dir.path, fileName));
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }

  Future<String> exportConfigFile() async {
    await saveSettings();
    final timestamp = DateTime.now()
        .toIso8601String()
        .replaceAll(':', '-')
        .replaceAll('.', '-');
    final fileName = 'player_config_$timestamp.json';
    final bytes = Uint8List.fromList(utf8.encode(exportSettings()));
    final picked = await FilePicker.platform.saveFile(
      dialogTitle: '导出配置文件',
      fileName: fileName,
      type: FileType.custom,
      allowedExtensions: const ['json'],
      bytes: bytes,
    );
    if (picked != null) return picked;
    final dir = await appFilesDirectory;
    final file = File(p.join(dir.path, fileName));
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }

  Future<String> exportDatabaseFile() async {
    addDiagnosticLog('database export started', category: 'database');
    await saveMediaStateDatabase();
    await pruneMetadataDatabase();
    final db = await metadataDatabaseFile;
    final timestamp = DateTime.now()
        .toIso8601String()
        .replaceAll(':', '-')
        .replaceAll('.', '-');
    final fileName = 'metadata_$timestamp.sqlite';
    final bytes = await db.readAsBytes();
    final picked = await FilePicker.platform.saveFile(
      dialogTitle: '导出元数据数据库',
      fileName: fileName,
      type: FileType.custom,
      allowedExtensions: const ['sqlite', 'db'],
      bytes: bytes,
    );
    if (picked != null) {
      addDiagnosticLog('database exported: $picked bytes=${bytes.length}',
          category: 'database');
      return picked;
    }
    final dir = await appFilesDirectory;
    final file = File(p.join(dir.path, fileName));
    await file.writeAsBytes(bytes, flush: true);
    addDiagnosticLog('database exported: ${file.path} bytes=${bytes.length}',
        category: 'database');
    return file.path;
  }

  Future<String> libraryHomeJson() async {
    final db = await metadataDatabaseFile;
    final stopwatch = Stopwatch()..start();
    addDiagnosticLog('library home query started', category: 'database');
    final text = await RustCoreService.instance.libraryHomeJsonAsync(db.path);
    addDiagnosticLog(
      'library home query finished: bytes=${text.length}, elapsed=${stopwatch.elapsedMilliseconds}ms',
      category: 'database',
    );
    return text;
  }

  Future<List<LibraryHomeEntry>> loadLibraryHome() async {
    final text = await libraryHomeJson();
    return (jsonDecode(text) as List<dynamic>)
        .whereType<Map<String, dynamic>>()
        .map(LibraryHomeEntry.fromJson)
        .toList();
  }

  Future<String> libraryShowDetailJson(String folderKey) async {
    final db = await metadataDatabaseFile;
    final stopwatch = Stopwatch()..start();
    addDiagnosticLog('library show detail query started: $folderKey',
        category: 'database');
    final text = await RustCoreService.instance.libraryShowDetailJsonAsync(
      db.path,
      folderKey,
    );
    addDiagnosticLog(
      'library show detail query finished: $folderKey, bytes=${text.length}, elapsed=${stopwatch.elapsedMilliseconds}ms',
      category: 'database',
    );
    return text;
  }

  Future<LibraryShowDetail> loadLibraryShowDetail(String folderKey) async {
    final text = await libraryShowDetailJson(folderKey);
    return LibraryShowDetail.fromJson(jsonDecode(text) as Map<String, dynamic>);
  }

  Future<String> libraryRecentJson() async {
    final db = await metadataDatabaseFile;
    final stopwatch = Stopwatch()..start();
    addDiagnosticLog('library recent query started', category: 'database');
    final text = await RustCoreService.instance.libraryRecentJsonAsync(db.path);
    addDiagnosticLog(
      'library recent query finished: bytes=${text.length}, elapsed=${stopwatch.elapsedMilliseconds}ms',
      category: 'database',
    );
    return text;
  }

  Future<List<LibraryRecentEntry>> loadLibraryRecent() async {
    final text = await libraryRecentJson();
    return (jsonDecode(text) as List<dynamic>)
        .whereType<Map<String, dynamic>>()
        .map(LibraryRecentEntry.fromJson)
        .toList();
  }

  Future<void> clearDiagnosticLogs() async {
    await _diagnosticLogWriteChain;
    diagnosticLogs.clear();
    diagnosticLogCount = 0;
    tmdbLastStatus = '';
    final file = await diagnosticLogFile;
    if (await file.exists()) {
      await file.writeAsString('', flush: true);
    }
    await saveSettings(logEvent: false);
    notifyListeners();
  }

  Uint8List? cachedTmdbImageMemoryBytes(String imagePath, String size) {
    if (imagePath.trim().isEmpty) return null;
    return _imageCache['$size:${_normalizedImagePath(imagePath)}'];
  }

  Future<void> preloadCachedTmdbImages(
    Iterable<MapEntry<String, String>> images,
  ) async {
    final seen = <String>{};
    final pending = <Future<void>>[];
    for (final image in images) {
      if (image.key.trim().isEmpty) continue;
      final cacheKey = '${image.value}:${_normalizedImagePath(image.key)}';
      if (!seen.add(cacheKey) || _imageCache.containsKey(cacheKey)) continue;
      pending.add(cachedTmdbImageBytes(
        image.key,
        image.value,
        downloadOnMiss: false,
      ).then((_) {}));
      if (pending.length >= 80) break;
    }
    await Future.wait(pending);
  }

  Future<Uint8List?> cachedTmdbImageBytes(
    String imagePath,
    String size, {
    bool downloadOnMiss = true,
  }) async {
    if (imagePath.trim().isEmpty) return null;
    final normalized = imagePath.startsWith('/') ? imagePath : '/$imagePath';
    final key = '$size:$normalized';
    if (_imageCache.containsKey(key)) {
      addDiagnosticLog('image memory cache hit: $key', category: 'cache');
      return _imageCache[key];
    }
    final db = await metadataDatabaseFile;
    try {
      addDiagnosticLog('image database cache read: $key', category: 'cache');
      final bytes = await RustCoreService.instance.metadataCachedImageAsync(
        db.path,
        normalized,
        size,
      );
      if (bytes != null && bytes.isNotEmpty) {
        _imageCache[key] = bytes;
        addDiagnosticLog('image database cache hit: $key bytes=${bytes.length}',
            category: 'cache');
        return bytes;
      }
      addDiagnosticLog('image database cache miss: $key', category: 'cache');
    } catch (error) {
      addDiagnosticLog('cached image read failed: $key - $error',
          category: 'cache');
    }
    if (!downloadOnMiss) return null;
    final url = tmdbImageUrl(
      normalized,
      size,
      imageBaseUrl: tmdbConfig.imageBaseUrl,
    );
    if (url == null) {
      _imageCache[key] = null;
      return null;
    }
    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        addDiagnosticLog(
          'image download failed status=${response.statusCode}: $key',
          category: 'cache',
        );
        _imageCache[key] = null;
        return null;
      }
      final bytes = response.bodyBytes;
      if (bytes.isEmpty) {
        addDiagnosticLog('image download empty: $key', category: 'cache');
        _imageCache[key] = null;
        return null;
      }
      final contentType = response.headers['content-type'];
      await RustCoreService.instance.metadataPutCachedImageAsync(
        db.path,
        normalized,
        size,
        url,
        contentType,
        bytes,
      );
      addDiagnosticLog(
          'image downloaded and cached: $key bytes=${bytes.length}',
          category: 'cache');
      _imageCache[key] = bytes;
      return bytes;
    } catch (error) {
      addDiagnosticLog('cached image download failed: $key - $error',
          category: 'cache');
      _imageCache[key] = null;
      return null;
    }
  }

  Future<Uint8List?> videoCoverBytes(MediaItem item) async {
    final key = _videoCoverKey(item);
    if (_videoCoverCache.containsKey(key)) return _videoCoverCache[key];
    final file = File(p.join((await videoCoverDirectory).path, '$key.jpg'));
    if (await file.exists()) {
      final bytes = await file.readAsBytes();
      if (bytes.isNotEmpty) {
        _videoCoverCache[key] = bytes;
        return bytes;
      }
    }
    final pending = _videoCoverRequests[key];
    if (pending != null) return pending;
    final request = _loadVideoCoverBytes(item, key, file);
    _videoCoverRequests[key] = request;
    try {
      return await request;
    } finally {
      _videoCoverRequests.remove(key);
    }
  }

  Future<void> deleteVideoCoversForItems(Iterable<MediaItem> items) async {
    final keys = items.map(_videoCoverKey).toSet();
    if (keys.isEmpty) return;
    for (final key in keys) {
      _videoCoverCache.remove(key);
    }
    try {
      final dir = await videoCoverDirectory;
      var deleted = 0;
      for (final key in keys) {
        final file = File(p.join(dir.path, '$key.jpg'));
        if (!await file.exists()) continue;
        await file.delete();
        deleted++;
      }
      if (deleted > 0) {
        addDiagnosticLog('video covers deleted: $deleted', category: 'cache');
      }
    } catch (error) {
      addDiagnosticLog('video cover cleanup failed: $error', category: 'cache');
    }
  }

  Future<Uint8List?> _loadVideoCoverBytes(
      MediaItem item, String key, File file) async {
    final remote = item.type == SourceType.webdav;
    final headers = remote
        ? sources
                .where((source) => source.id == item.sourceId)
                .firstOrNull
                ?.headers ??
            const <String, String>{}
        : const <String, String>{};
    try {
      Future<Uint8List?> load() => appChannel.invokeMethod<Uint8List>(
            'videoThumbnail',
            {
              'uri': item.uri,
              'remote': remote,
              'headers': headers,
            },
          );
      final bytes = remote ? await _queueRemoteVideoCover(load) : await load();
      final resolvedBytes = bytes?.isNotEmpty == true
          ? bytes
          : await _mediaKitVideoCoverBytes(item, headers);
      if (resolvedBytes == null || resolvedBytes.isEmpty) {
        _videoCoverCache[key] = null;
        return null;
      }
      _videoCoverCache[key] = resolvedBytes;
      await file.writeAsBytes(resolvedBytes, flush: true);
      return resolvedBytes;
    } on MissingPluginException {
      final bytes = await _mediaKitVideoCoverBytes(item, headers);
      if (bytes == null || bytes.isEmpty) {
        _videoCoverCache[key] = null;
        return null;
      }
      _videoCoverCache[key] = bytes;
      await file.writeAsBytes(bytes, flush: true);
      return bytes;
    } on PlatformException catch (error) {
      addDiagnosticLog('platform video cover unavailable: ${item.id} - $error',
          category: 'cache');
      final bytes = await _mediaKitVideoCoverBytes(item, headers);
      if (bytes == null || bytes.isEmpty) {
        _videoCoverCache[key] = null;
        return null;
      }
      _videoCoverCache[key] = bytes;
      await file.writeAsBytes(bytes, flush: true);
      return bytes;
    }
  }

  Future<Uint8List?> _mediaKitVideoCoverBytes(
      MediaItem item, Map<String, String> headers) async {
    if (Platform.isAndroid || Platform.isIOS) return null;
    final player = Player();
    try {
      await player.setVolume(0);
      await player.open(
        Media(
          item.type == SourceType.local
              ? Uri.file(item.uri).toString()
              : item.uri,
          httpHeaders: headers.isEmpty ? null : headers,
          start: const Duration(seconds: 1),
        ),
      );
      final watch = Stopwatch()..start();
      while (watch.elapsed < const Duration(seconds: 6)) {
        final state = player.state;
        if ((state.width ?? 0) > 0 &&
            (state.height ?? 0) > 0 &&
            state.position > Duration.zero) {
          break;
        }
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      final bytes = await player.screenshot(format: 'image/jpeg');
      if (bytes == null || bytes.isEmpty) {
        addDiagnosticLog('media_kit video cover empty: ${item.id}',
            category: 'cache');
        return null;
      }
      return bytes;
    } catch (error) {
      addDiagnosticLog('media_kit video cover unavailable: ${item.id} - $error',
          category: 'cache');
      return null;
    } finally {
      await player.dispose();
    }
  }

  Future<Uint8List?> _queueRemoteVideoCover(
      Future<Uint8List?> Function() load) {
    final run =
        _remoteVideoCoverChain.then((_) => load(), onError: (_) => load());
    _remoteVideoCoverChain = run.then<void>((_) {}, onError: (_) {});
    return run;
  }

  String _videoCoverKey(MediaItem item) {
    return _stableTextHash([
      item.id,
      item.uri,
      item.size ?? -1,
    ].join('\t'));
  }

  Future<void> updateProgress(String itemId, Duration position,
      [Duration? duration]) async {
    progress[itemId] = position.inMilliseconds;
    if (duration != null && duration > Duration.zero) {
      durations[itemId] = duration.inMilliseconds;
    }
    lastPlayedAt[itemId] = DateTime.now().millisecondsSinceEpoch;
    addDiagnosticLog(
      'playback progress update: item=$itemId position=${position.inMilliseconds} duration=${duration?.inMilliseconds}',
      category: 'playback',
    );
    await save();
    notifyListeners();
  }

  Future<void> rememberDuration(String itemId, Duration duration) async {
    if (duration <= Duration.zero) return;
    final milliseconds = duration.inMilliseconds;
    if (durations[itemId] == milliseconds) return;
    durations[itemId] = milliseconds;
    addDiagnosticLog(
        'playback duration remembered: item=$itemId duration=$milliseconds',
        category: 'playback');
    await save();
    notifyListeners();
  }

  Future<void> rememberFolderOrientation(MediaItem item, bool landscape) async {
    final key = mediaFolderKey(item);
    final orientation = landscape ? 'landscape' : 'portrait';
    folderOrientations[key] = orientation;
    addDiagnosticLog(
      'folder orientation remembered: key=$key orientation=$orientation',
      category: 'ui',
    );
    await save();
    notifyListeners();
  }
}

String tmdbAutoMatchItemFingerprint(MediaItem item) {
  return [
    item.id,
    item.size ?? -1,
    item.matchTitle,
    item.matchYear ?? '',
    item.season ?? '',
    item.episode ?? '',
    item.mediaKind,
    item.groupPath,
    item.folderTitle,
    item.versionName,
    item.versionDirPath,
    item.manualSeries,
  ].join('\t');
}

String tmdbAutoMatchFailedItemKey(MediaItem item) {
  return [
    item.id,
    item.size ?? -1,
    item.matchTitle,
    item.groupPath,
    item.manualSeries,
  ].join('\t');
}

Set<String> tmdbAutoMatchFailedItems(Map<String, dynamic>? state) {
  return (state?['failedItems'] as List<dynamic>? ?? const [])
      .whereType<String>()
      .toSet();
}
