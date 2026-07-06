part of 'package:player_flutter/main.dart';

class LocalBrowserPage extends StatefulWidget {
  const LocalBrowserPage(
      {required this.store, required this.source, super.key});

  final AppStore store;
  final MediaSourceConfig source;

  @override
  State<LocalBrowserPage> createState() => _LocalBrowserPageState();
}

class _LocalBrowserPageState extends State<LocalBrowserPage> {
  late String path = widget.source.directory;
  late Future<List<LocalEntry>> future = load();
  bool adding = false;

  MediaSourceConfig get source => widget.store.sources.firstWhere(
        (value) => value.id == widget.source.id,
        orElse: () => widget.source,
      );

  bool get isWindowsRoot => Platform.isWindows && path.isEmpty;

  bool isWindowsDriveRoot(String value) =>
      Platform.isWindows && RegExp(r'^[A-Za-z]:[\\/]?$').hasMatch(value);

  Future<List<LocalEntry>> windowsDriveEntries() async {
    final entries = <LocalEntry>[];
    for (var code = 65; code <= 90; code++) {
      final root = '${String.fromCharCode(code)}:\\';
      if (await Directory(root).exists()) {
        entries.add(LocalEntry(name: root, path: root, isDir: true));
      }
    }
    return entries;
  }

  Future<List<LocalEntry>> load() async {
    final granted =
        await ensureLocalStorageAccess(context, showDeniedMessage: false);
    if (!granted) {
      throw Exception('没有本地存储访问权限，请在系统设置中允许访问视频或所有文件。');
    }

    if (isWindowsRoot) return windowsDriveEntries();

    final dir = Directory(path);
    if (!await dir.exists()) {
      throw Exception(localAccessHelp(path));
    }

    return RustCoreService.instance.listLocalDirectoryAsync(path);
  }

  void refresh([String? next]) {
    setState(() {
      path = next ?? path;
      future = load();
    });
  }

  void goParent() {
    if (isWindowsDriveRoot(path)) {
      refresh('');
      return;
    }
    if (path != widget.source.directory) refresh(p.dirname(path));
  }

  String get title {
    if (path == widget.source.directory) return widget.source.name;
    if (isWindowsDriveRoot(path)) return path;
    return p.basename(path);
  }

  Future<void> addEntry(LocalEntry entry, {bool asSeries = false}) async {
    setState(() => adding = true);
    try {
      await widget.store.addLocalSelection(source, entry, asSeries: asSeries);
      if (mounted) {
        showSnack(context, entry.isDir ? '已添加文件夹，视频会显示在首页' : '已添加视频到首页');
      }
    } catch (e) {
      if (mounted) showSnack(context, '添加失败：$e');
    } finally {
      if (mounted) setState(() => adding = false);
    }
  }

  Future<void> removeEntry(LocalEntry entry) async {
    setState(() => adding = true);
    try {
      await widget.store.removeLocalSelection(source, entry);
      if (mounted) showSnack(context, entry.isDir ? '已取消此文件夹' : '已取消此视频');
    } catch (e) {
      if (mounted) showSnack(context, '取消失败：$e');
    } finally {
      if (mounted) setState(() => adding = false);
    }
  }

  SourcePathSelectionState selectionState(LocalEntry entry) => widget.store
      .sourcePathSelectionState(source, entry.path, isDir: entry.isDir);

  bool isManualSeries(LocalEntry entry) =>
      sourceManualSeriesPath(source, entry.path, isDir: entry.isDir);

  Future<void> setSeriesEntry(LocalEntry entry, bool enabled) async {
    setState(() => adding = true);
    try {
      await widget.store.setManualSeriesPath(
        source,
        entry.path,
        isDir: entry.isDir,
        enabled: enabled,
      );
      if (mounted) showSnack(context, enabled ? '已设为剧集' : '已取消剧集设置');
    } catch (e) {
      if (mounted) showSnack(context, '设置失败：$e');
    } finally {
      if (mounted) setState(() => adding = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope<void>(
      canPop: path == widget.source.directory,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) goParent();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(title),
          actions: [
            IconButton(
                tooltip: '刷新',
                onPressed: refresh,
                icon: const Icon(Icons.refresh)),
          ],
        ),
        body: FutureBuilder<List<LocalEntry>>(
          future: future,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return ErrorView(
                message: '${snapshot.error}',
                onRetry: refresh,
                action: Platform.isAndroid
                    ? const OutlinedButton(
                        onPressed: openAppSettings, child: Text('打开权限设置'))
                    : null,
              );
            }
            final entries = snapshot.data ?? [];
            if (entries.isEmpty) {
              return EmptyState(
                icon: Icons.folder_off_outlined,
                title: '目录为空',
                message: '没有发现视频或子目录。请检查目录权限，或重新选择更上一级目录。',
                action: OutlinedButton(
                    onPressed: refresh, child: const Text('重新加载')),
              );
            }
            return ListView(
              children: [
                if (path != widget.source.directory)
                  ListTile(
                    leading: const Icon(Icons.drive_folder_upload_outlined),
                    title: const Text('返回上级'),
                    onTap: goParent,
                  ),
                for (final entry in entries)
                  ListTile(
                    leading:
                        Icon(entry.isDir ? Icons.folder : Icons.movie_outlined),
                    title: Text(entry.name,
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle:
                        Text(entry.isDir ? '文件夹' : readableBytes(entry.size)),
                    trailing: SourceEntryMenu(
                      selectionState: selectionState(entry),
                      manualSeries: isManualSeries(entry),
                      enabled:
                          !adding && (entry.isDir || isVideoName(entry.name)),
                      onAdd: () => addEntry(entry),
                      onRemove: () => removeEntry(entry),
                      onSeriesOn: () => addEntry(entry, asSeries: true),
                      onSeriesOff: () => setSeriesEntry(entry, false),
                    ),
                    onTap: () {
                      if (entry.isDir) {
                        refresh(entry.path);
                      } else if (isVideoName(entry.name)) {
                        openPlayer(context, widget.store,
                            MediaItem.local(source: source, path: entry.path));
                      }
                    },
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}
