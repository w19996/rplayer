part of 'package:player_flutter/main.dart';

class SourceLibraryPage extends StatelessWidget {
  const SourceLibraryPage({required this.store, super.key});

  final AppStore store;

  List<MediaSourceConfig> _sourcesOf(SourceType type) =>
      store.sources.where((source) => source.type == type).toList();

  Widget _sourceCard(BuildContext context, MediaSourceConfig source) {
    final count =
        store.items.where((item) => item.sourceId == source.id).length;
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 0, 22, 8),
      child: SourceCard(
        source: source,
        count: count,
        onOpen: () => Navigator.of(context).push(
          appSlideRoute(
            (_) => source.type == SourceType.webdav
                ? WebdavBrowserPage(store: store, source: source)
                : LocalBrowserPage(store: store, source: source),
          ),
        ),
        onAdded: () => Navigator.of(context).push(
          appSlideRoute(
            (_) => AddedSourceSelectionsPage(store: store, source: source),
          ),
        ),
        onEdit: source.type == SourceType.webdav
            ? () => Navigator.of(context).push(
                  appSlideRoute(
                    (_) => WebdavSourceFormPage(
                      store: store,
                      source: source,
                    ),
                  ),
                )
            : null,
        onDelete: () => store.removeSource(source),
      ),
    );
  }

  List<Widget> _sourceSection(
      BuildContext context, String title, List<MediaSourceConfig> sources) {
    if (sources.isEmpty) return const [];
    return [
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 22),
        child: SourceGroupTitle(title),
      ),
      for (final source in sources) _sourceCard(context, source),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final localSources = _sourcesOf(SourceType.local);
    final webdavSources = _sourcesOf(SourceType.webdav);

    return ColoredBox(
      color: Colors.white,
      child: SafeArea(
        bottom: false,
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(22, 18, 22, 22),
                child: Row(
                  children: [
                    const Spacer(),
                    const Text('资源库',
                        style: TextStyle(
                            fontSize: 22, fontWeight: FontWeight.w700)),
                    const Spacer(),
                    IconButton(
                      tooltip: '添加源',
                      onPressed: () => openAddSource(context, store),
                      icon: const Icon(Icons.add, size: 31),
                    ),
                  ],
                ),
              ),
            ),
            if (store.sources.isEmpty)
              SliverFillRemaining(
                child: EmptyState(
                  icon: Icons.folder_open_outlined,
                  title: '暂无文件源',
                  message: '点击右上角加号，添加本地目录或 WebDAV 目录。',
                  action: FilledButton.icon(
                    onPressed: () => openAddSource(context, store),
                    icon: const Icon(Icons.add),
                    label: const Text('添加新文件源'),
                  ),
                ),
              )
            else
              SliverList.list(
                children: [
                  ..._sourceSection(context, '本地目录', localSources),
                  ..._sourceSection(context, 'WebDAV', webdavSources),
                  const SizedBox(height: 22),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class AddedSourceSelectionsPage extends StatefulWidget {
  const AddedSourceSelectionsPage({
    required this.store,
    required this.source,
    super.key,
  });

  final AppStore store;
  final MediaSourceConfig source;

  @override
  State<AddedSourceSelectionsPage> createState() =>
      _AddedSourceSelectionsPageState();
}

class _AddedSourceSelectionsPageState extends State<AddedSourceSelectionsPage> {
  late String path = widget.source.directory;
  late Future<List<_AddedSourceEntry>> future = load();
  String? removingPath;

  MediaSourceConfig? get source => widget.store.sources
      .where((value) => value.id == widget.source.id)
      .firstOrNull;

  Future<List<_AddedSourceEntry>> load() async {
    final current = source;
    if (current == null) return const [];
    if (current.type == SourceType.webdav) {
      final entries = await WebdavClient.fromSource(current).list(path);
      return entries
          .map(_AddedSourceEntry.webdav)
          .where((entry) =>
              _entryVisibleInAddedBrowser(current, entry, widget.store))
          .toList();
    }

    final granted =
        await ensureLocalStorageAccess(context, showDeniedMessage: false);
    if (!granted) {
      throw Exception('没有本地存储访问权限，请在系统设置中允许视频访问权限。');
    }
    final dir = Directory(path);
    if (!await dir.exists()) {
      throw Exception(localAccessHelp(path));
    }
    final entries =
        await RustCoreService.instance.listLocalDirectoryAsync(path);
    return entries
        .map(_AddedSourceEntry.local)
        .where((entry) =>
            _entryVisibleInAddedBrowser(current, entry, widget.store))
        .toList();
  }

  void refresh([String? next]) {
    setState(() {
      path = next ?? path;
      future = load();
    });
  }

  void goParent() {
    final current = source;
    if (current == null || path == current.directory) return;
    refresh(
        current.type == SourceType.webdav ? parentPath(path) : p.dirname(path));
  }

  Future<void> _remove(MediaSourceConfig source, String path) async {
    setState(() => removingPath = path);
    try {
      final pending = widget.store.removeSelectedPath(source, path);
      refresh();
      await pending;
      if (mounted) {
        showSnack(context, '已取消添加');
      }
    } catch (err) {
      if (mounted) showSnack(context, '取消添加失败：$err');
    } finally {
      if (mounted) setState(() => removingPath = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentSource = source;
    return PopScope<void>(
      canPop: currentSource == null || path == currentSource.directory,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (source == null) {
          Navigator.of(context).pop();
        } else {
          goParent();
        }
      },
      child: Scaffold(
        appBar: AppBar(title: const Text('已添加')),
        body: AnimatedBuilder(
          animation: widget.store,
          builder: (context, _) {
            final current = source;
            if (current == null) {
              return const EmptyState(
                icon: Icons.folder_off_outlined,
                title: '源已删除',
                message: '这个文件源已经不存在。',
                action: SizedBox.shrink(),
              );
            }
            final paths = current.selectedPaths;
            if (paths.isEmpty) {
              return const EmptyState(
                icon: Icons.folder_open_outlined,
                title: '还没有添加资源',
                message: '进入源目录后选择文件或文件夹添加到媒体库。',
                action: SizedBox.shrink(),
              );
            }
            return FutureBuilder<List<_AddedSourceEntry>>(
              future: future,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return ErrorView(
                      message: '${snapshot.error}', onRetry: refresh);
                }
                final entries = snapshot.data ?? const [];
                if (entries.isEmpty) {
                  return EmptyState(
                    icon: Icons.folder_off_outlined,
                    title: '当前目录没有已添加资源',
                    message: '返回上级目录查看已添加的文件或文件夹。',
                    action: OutlinedButton(
                      onPressed: refresh,
                      child: const Text('重新加载'),
                    ),
                  );
                }
                final hasParent = path != current.directory;
                return ListView.builder(
                  itemExtent: 72,
                  cacheExtent: 1440,
                  itemCount: entries.length + (hasParent ? 1 : 0),
                  itemBuilder: (context, index) {
                    if (hasParent && index == 0) {
                      return ListTile(
                        leading: const Icon(Icons.drive_folder_upload_outlined),
                        title: const Text('返回上级'),
                        onTap: goParent,
                      );
                    }
                    final entry = entries[index - (hasParent ? 1 : 0)];
                    final selectionState = widget.store
                        .sourcePathSelectionState(current, entry.path,
                            isDir: entry.isDir);
                    final selected =
                        selectionState != SourcePathSelectionState.none;
                    final removing = removingPath == entry.path;
                    return ListTile(
                      leading: Icon(
                          entry.isDir ? Icons.folder : Icons.movie_outlined),
                      title: Text(
                        entry.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(entry.isDir
                          ? entry.path
                          : '${readableBytes(entry.size)} · ${entry.path}'),
                      trailing: selected
                          ? TextButton.icon(
                              onPressed: removing
                                  ? null
                                  : () =>
                                      unawaited(_remove(current, entry.path)),
                              icon: removing
                                  ? const SizedBox.square(
                                      dimension: 18,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2),
                                    )
                                  : Icon(selectionState ==
                                          SourcePathSelectionState.full
                                      ? Icons.check_circle
                                      : Icons.indeterminate_check_box),
                              label: const Text('取消添加'),
                            )
                          : entry.isDir
                              ? const Icon(Icons.chevron_right)
                              : null,
                      onTap: () {
                        if (entry.isDir) {
                          refresh(entry.path);
                        } else if (isVideoName(entry.name)) {
                          final item = entry.toMediaItem(current);
                          if (item != null) {
                            openPlayer(context, widget.store, item);
                          }
                        }
                      },
                    );
                  },
                );
              },
            );
          },
        ),
      ),
    );
  }
}

class _AddedSourceEntry {
  const _AddedSourceEntry({
    required this.name,
    required this.path,
    required this.isDir,
    required this.size,
    this.webdav,
    this.local,
  });

  factory _AddedSourceEntry.webdav(WebdavEntry entry) => _AddedSourceEntry(
        name: entry.name,
        path: entry.isDir ? normalizeRemoteDir(entry.path) : entry.path,
        isDir: entry.isDir,
        size: entry.size ?? 0,
        webdav: entry,
      );

  factory _AddedSourceEntry.local(LocalEntry entry) => _AddedSourceEntry(
        name: entry.name,
        path: entry.path,
        isDir: entry.isDir,
        size: entry.size ?? 0,
        local: entry,
      );

  final String name;
  final String path;
  final bool isDir;
  final int size;
  final WebdavEntry? webdav;
  final LocalEntry? local;

  MediaItem? toMediaItem(MediaSourceConfig source) {
    if (source.type == SourceType.webdav) {
      final entry = webdav;
      return entry == null
          ? null
          : MediaItem.webdav(source: source, entry: entry);
    }
    final entry = local;
    return entry == null
        ? null
        : MediaItem.local(source: source, path: entry.path);
  }
}

bool _entryVisibleInAddedBrowser(
  MediaSourceConfig source,
  _AddedSourceEntry entry,
  AppStore store,
) {
  if (store.sourcePathAdded(source, entry.path, isDir: entry.isDir)) {
    return entry.isDir || isVideoName(entry.name);
  }
  if (!entry.isDir) return false;
  return source.selectedPaths.any(
    (path) => sourcePathCovers(
      source,
      entry.path,
      path,
      containerIsDir: true,
    ),
  );
}
