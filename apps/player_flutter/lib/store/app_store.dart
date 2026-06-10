part of 'package:player_flutter/main.dart';

class AppStore extends ChangeNotifier {
  AppStore({this.scanner = const MediaScanService()});

  final MediaScanService scanner;
  final List<MediaSourceConfig> sources = [];
  final List<MediaItem> items = [];
  final Map<String, int> progress = {};
  final Map<String, int> durations = {};
  final Map<String, int> lastPlayedAt = {};
  final Map<String, String> folderOrientations = {};
  final Map<String, MediaMetadata> metadata = {};
  TmdbConfig tmdbConfig = const TmdbConfig();
  SyncConfig? syncConfig;
  bool loaded = false;
  bool metadataRefreshing = false;
  String tmdbLastStatus = '';
  final List<String> diagnosticLogs = [];

  Future<Directory> get appFilesDirectory async {
    var path = Directory.systemTemp.path;
    try {
      path = await appChannel.invokeMethod<String>('appFilesDir') ?? path;
    } on MissingPluginException {
      path = Directory.systemTemp.path;
    }
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

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final file = await configFile;
    final text = await file.exists()
        ? await file.readAsString()
        : prefs.getString('app_state');
    if (text != null && text.isNotEmpty) {
      await importState(text, persist: false);
    }
    await loadMetadataDatabase();
    loaded = true;
    notifyListeners();
    unawaited(refreshMissingMetadata());
  }

  Future<void> save() async {
    final text = exportState();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('app_state', text);
    await (await configFile).writeAsString(text);
  }

  Future<void> loadMetadataDatabase() async {
    try {
      final db = await metadataDatabaseFile;
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
    } catch (error) {
      addDiagnosticLog('metadata database load failed: $error');
    }
  }

  Future<void> saveMetadataToDatabase(
      String itemId, MediaMetadata value) async {
    try {
      final db = await metadataDatabaseFile;
      await RustCoreService.instance.metadataPutAsync(
        db.path,
        itemId,
        jsonEncode(value.toJson()),
      );
    } catch (error) {
      addDiagnosticLog('metadata database write failed: $error');
    }
  }

  Future<void> replaceMetadataDatabase() async {
    final db = await metadataDatabaseFile;
    await RustCoreService.instance.metadataReplaceAllAsync(db.path, metadata);
  }

  String exportState() {
    return const JsonEncoder.withIndent('  ').convert({
      'version': 1,
      'sources': sources.map((source) => source.toJson()).toList(),
      'items': items.map((item) => item.toJson()).toList(),
      'progress': progress,
      'durations': durations,
      'lastPlayedAt': lastPlayedAt,
      'folderOrientations': folderOrientations,
      'metadata': metadata.map((key, value) => MapEntry(key, value.toJson())),
      'tmdbConfig': tmdbConfig.toJson(),
      'syncConfig': syncConfig?.toJson(),
      'diagnosticLogs': diagnosticLogs,
    });
  }

  Future<void> importState(String text, {bool persist = true}) async {
    final json = jsonDecode(text) as Map<String, dynamic>;
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
          (value) => MediaItem.fromJson(value as Map<String, dynamic>)
              .withFreshIdentity(),
        ),
      );
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
      ..addAll((json['folderOrientations'] as Map<String, dynamic>? ?? {})
          .map((key, value) => MapEntry(key, value as String)));
    metadata
      ..clear()
      ..addAll((json['metadata'] as Map<String, dynamic>? ?? {}).map(
        (key, value) => MapEntry(
          key,
          MediaMetadata.fromJson(value as Map<String, dynamic>),
        ),
      ));
    final tmdb = json['tmdbConfig'];
    tmdbConfig = tmdb == null
        ? const TmdbConfig()
        : TmdbConfig.fromJson(tmdb as Map<String, dynamic>);
    final sync = json['syncConfig'];
    syncConfig =
        sync == null ? null : SyncConfig.fromJson(sync as Map<String, dynamic>);
    diagnosticLogs
      ..clear()
      ..addAll((json['diagnosticLogs'] as List<dynamic>? ?? const [])
          .whereType<String>());
    if (metadata.isNotEmpty) {
      unawaited(replaceMetadataDatabase());
    }
    if (persist) await save();
    notifyListeners();
  }

  Future<MediaSourceConfig> addLocalDirectory(String dir) async {
    final source = MediaSourceConfig.local(
      id: newId(),
      name: p.basename(dir).isEmpty ? '本地目录' : p.basename(dir),
      directory: dir,
    );
    sources.add(source);
    await save();
    notifyListeners();
    return source;
  }

  Future<MediaSourceConfig> addWebdavSource(WebdavSourceDraft draft) async {
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

  Future<void> removeSource(MediaSourceConfig source) async {
    sources.removeWhere((value) => value.id == source.id);
    items.removeWhere((item) => item.sourceId == source.id);
    metadata.removeWhere((itemId, _) => itemId.startsWith('${source.id}:'));
    await save();
    notifyListeners();
  }

  Future<void> rescanAll() async {
    final existing = List<MediaSourceConfig>.from(sources);
    items.clear();
    for (final source in existing) {
      await scanSourceIntoItems(source);
    }
    metadata
        .removeWhere((itemId, _) => !items.any((item) => item.id == itemId));
    await save();
    notifyListeners();
    unawaited(refreshMissingMetadata());
  }

  Future<void> rescanSource(MediaSourceConfig source) async {
    items.removeWhere((item) => item.sourceId == source.id);
    await scanSourceIntoItems(source);
    metadata
        .removeWhere((itemId, _) => !items.any((item) => item.id == itemId));
    await save();
    notifyListeners();
    unawaited(refreshMissingMetadata());
  }

  Future<void> scanSourceIntoItems(MediaSourceConfig source) async {
    for (final item in await scanner.scanSource(source)) {
      addOrReplaceItem(item);
    }
    items
        .sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
  }

  Future<void> addWebdavSelection(
      MediaSourceConfig source, WebdavEntry entry) async {
    final normalizedPath =
        entry.isDir ? normalizeRemoteDir(entry.path) : entry.path;
    final updated = source.copyWith(
      selectedPaths: {...source.selectedPaths, normalizedPath}.toList()..sort(),
    );
    replaceSource(updated);

    if (entry.isDir) {
      final client = WebdavClient.fromSource(updated);
      final entries = await client.scanVideos(entry.path, maxDepth: 8);
      for (final video in entries) {
        addOrReplaceItem(MediaItem.webdav(source: updated, entry: video));
      }
    } else if (isVideoName(entry.name)) {
      addOrReplaceItem(MediaItem.webdav(source: updated, entry: entry));
    }
    items
        .sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
    await save();
    notifyListeners();
    unawaited(refreshMissingMetadata());
  }

  Future<void> addLocalSelection(
      MediaSourceConfig source, LocalEntry entry) async {
    final normalizedPath = entry.path;
    final updated = source.copyWith(
      selectedPaths: {...source.selectedPaths, normalizedPath}.toList()..sort(),
    );
    replaceSource(updated);

    if (entry.isDir) {
      final found = await scanner.scanLocalPath(updated, entry.path);
      for (final item in found) {
        addOrReplaceItem(item);
      }
    } else if (isVideoName(entry.name)) {
      addOrReplaceItem(MediaItem.local(source: updated, path: entry.path));
    }
    items
        .sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
    await save();
    notifyListeners();
    unawaited(refreshMissingMetadata());
  }

  Future<void> removeLocalSelection(
      MediaSourceConfig source, LocalEntry entry) async {
    final updated = source.copyWith(
      selectedPaths:
          source.selectedPaths.where((path) => path != entry.path).toList(),
    );
    replaceSource(updated);
    items.removeWhere((item) => item.sourceId == source.id);
    await scanSourceIntoItems(updated);
    metadata
        .removeWhere((itemId, _) => !items.any((item) => item.id == itemId));
    await save();
    notifyListeners();
    unawaited(refreshMissingMetadata());
  }

  Future<void> removeWebdavSelection(
      MediaSourceConfig source, WebdavEntry entry) async {
    final normalizedPath =
        entry.isDir ? normalizeRemoteDir(entry.path) : entry.path;
    final updated = source.copyWith(
      selectedPaths:
          source.selectedPaths.where((path) => path != normalizedPath).toList(),
    );
    replaceSource(updated);
    items.removeWhere((item) => item.sourceId == source.id);
    await scanSourceIntoItems(updated);
    metadata
        .removeWhere((itemId, _) => !items.any((item) => item.id == itemId));
    await save();
    notifyListeners();
    unawaited(refreshMissingMetadata());
  }

  void addOrReplaceItem(MediaItem item) {
    items.removeWhere((value) => value.id == item.id);
    items.add(item);
  }

  void replaceSource(MediaSourceConfig source) {
    final index = sources.indexWhere((value) => value.id == source.id);
    if (index >= 0) sources[index] = source;
  }

  Future<void> setSyncConfig(SyncConfig config) async {
    syncConfig = config;
    await save();
    notifyListeners();
  }

  Future<void> setTmdbConfig(TmdbConfig config) async {
    tmdbConfig = config;
    await save();
    notifyListeners();
    unawaited(refreshMissingMetadata(force: true));
  }

  Future<void> refreshMissingMetadata({bool force = false}) async {
    if (!tmdbConfig.enabled || metadataRefreshing) return;
    metadataRefreshing = true;
    tmdbLastStatus = 'TMDB refresh started';
    addDiagnosticLog(
        'TMDB refresh started, force=$force, items=${items.length}');
    notifyListeners();
    try {
      final service = TmdbMetadataService(tmdbConfig, log: addDiagnosticLog);
      var matched = 0;
      var failed = 0;
      var skipped = 0;
      final targets = <MediaItem>[];
      for (final item in List<MediaItem>.from(items)) {
        addDiagnosticLog('TMDB item: ${describeMediaItem(item)}');
        final cached = metadata[item.id];
        if (!force &&
            cached != null &&
            cached.schemaVersion >= currentMetadataSchemaVersion) {
          skipped++;
          addDiagnosticLog('TMDB skip cached: ${describeMediaItem(item)}');
          continue;
        }
        targets.add(item);
      }

      var cursor = 0;
      Future<void> worker() async {
        while (true) {
          if (cursor >= targets.length) return;
          final item = targets[cursor++];
          if (!metadataRefreshing) return;
          addDiagnosticLog('TMDB worker item: ${describeMediaItem(item)}');
          MediaMetadata? value;
          try {
            value = await service.lookup(item);
          } catch (error) {
            failed++;
            tmdbLastStatus = 'TMDB error: ${describeMediaItem(item)} - $error';
            addDiagnosticLog(tmdbLastStatus);
            notifyListeners();
            continue;
          }
          if (value != null) {
            metadata[item.id] = value;
            matched++;
            addDiagnosticLog(
                'TMDB matched item=${describeMediaItem(item)} tmdb=${value.tmdbId} type=${value.mediaType} poster=${value.posterPath} still=${value.stillPath}');
            await saveMetadataToDatabase(item.id, value);
            notifyListeners();
          } else {
            failed++;
            tmdbLastStatus = 'TMDB no match: ${describeMediaItem(item)}';
            addDiagnosticLog(tmdbLastStatus);
            notifyListeners();
          }
        }
      }

      final workerCount = math.min(4, math.max(1, targets.length));
      await Future.wait([
        for (var i = 0; i < workerCount; i++) worker(),
      ]);
      await save();
      tmdbLastStatus =
          'TMDB refresh done: $matched matched, $failed failed, $skipped skipped';
      addDiagnosticLog(tmdbLastStatus);
    } finally {
      metadataRefreshing = false;
      notifyListeners();
    }
  }

  void addDiagnosticLog(String message) {
    final time = DateTime.now().toIso8601String();
    diagnosticLogs.add('$time $message');
    if (diagnosticLogs.length > 1000) {
      diagnosticLogs.removeRange(0, diagnosticLogs.length - 1000);
    }
  }

  String exportDiagnosticLogs() => diagnosticLogs.join('\n');

  Future<void> clearDiagnosticLogs() async {
    diagnosticLogs.clear();
    tmdbLastStatus = '';
    await save();
    notifyListeners();
  }

  Future<void> updateProgress(String itemId, Duration position,
      [Duration? duration]) async {
    progress[itemId] = position.inMilliseconds;
    if (duration != null && duration > Duration.zero) {
      durations[itemId] = duration.inMilliseconds;
    }
    lastPlayedAt[itemId] = DateTime.now().millisecondsSinceEpoch;
    await save();
    notifyListeners();
  }

  Future<void> rememberDuration(String itemId, Duration duration) async {
    if (duration <= Duration.zero) return;
    final milliseconds = duration.inMilliseconds;
    if (durations[itemId] == milliseconds) return;
    durations[itemId] = milliseconds;
    await save();
    notifyListeners();
  }

  Future<void> rememberFolderOrientation(MediaItem item, bool landscape) async {
    folderOrientations[mediaFolderKey(item)] =
        landscape ? 'landscape' : 'portrait';
    await save();
    notifyListeners();
  }
}
