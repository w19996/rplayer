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

  Future<List<LocalEntry>> load() async {
    final granted =
        await ensureLocalStorageAccess(context, showDeniedMessage: false);
    if (!granted) {
      throw Exception('没有本地存储访问权限，请在系统设置中允许访问视频或所有文件。');
    }

    final dir = Directory(path);
    if (!await dir.exists()) {
      throw Exception(localAccessHelp(path));
    }

    final entries = <LocalEntry>[];
    try {
      await for (final entity in dir.list(followLinks: false)) {
        final stat = await entity.stat();
        final isDir = stat.type == FileSystemEntityType.directory;
        final isFile = stat.type == FileSystemEntityType.file;
        if (!isDir && (!isFile || !isVideoName(entity.path))) continue;
        entries.add(
          LocalEntry(
            name: p.basename(entity.path),
            path: entity.path,
            isDir: isDir,
            size: isFile ? stat.size : null,
          ),
        );
      }
    } on FileSystemException catch (e) {
      throw Exception(localAccessHelp(e.path ?? path));
    }
    entries.sort((a, b) {
      if (a.isDir != b.isDir) return a.isDir ? -1 : 1;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return entries;
  }

  void refresh([String? next]) {
    setState(() {
      path = next ?? path;
      future = load();
    });
  }

  void goParent() {
    if (path != widget.source.directory) refresh(p.dirname(path));
  }

  Future<void> addEntry(LocalEntry entry) async {
    setState(() => adding = true);
    try {
      await widget.store.addLocalSelection(source, entry);
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

  bool isSelected(LocalEntry entry) =>
      source.selectedPaths.contains(entry.path);

  @override
  Widget build(BuildContext context) {
    return PopScope<void>(
      canPop: path == widget.source.directory,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) goParent();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(path == widget.source.directory
              ? widget.source.name
              : p.basename(path)),
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
                    trailing: isSelected(entry)
                        ? IconButton(
                            tooltip: entry.isDir ? '取消此文件夹' : '取消此视频',
                            onPressed: adding ? null : () => removeEntry(entry),
                            icon: const Icon(Icons.check_circle,
                                color: Color(0xFF2E7AF6)),
                          )
                        : IconButton(
                            tooltip: entry.isDir ? '添加此文件夹' : '添加此视频',
                            onPressed: adding ||
                                    (!entry.isDir && !isVideoName(entry.name))
                                ? null
                                : () => addEntry(entry),
                            icon: const Icon(Icons.add_circle_outline),
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
