part of 'package:player_flutter/main.dart';

class AddSourcePage extends StatelessWidget {
  const AddSourcePage({required this.store, super.key});

  final AppStore store;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        title: const Text('添加新文件源'),
        centerTitle: true,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(22, 20, 22, 24),
        children: [
          const SourceGroupTitle('本地存储'),
          AddSourceTile(
            icon: Icons.folder_special_outlined,
            title: '本地目录',
            onTap: () async {
              final granted = await ensureLocalStorageAccess(context);
              if (!granted) return;
              final dir = defaultLocalStorageRoot();
              final source = store.sources
                      .where((source) =>
                          source.type == SourceType.local &&
                          source.directory == dir)
                      .firstOrNull ??
                  MediaSourceConfig.local(
                    id: newId(),
                    name: localSourceName(dir),
                    directory: dir,
                  );
              if (context.mounted) {
                Navigator.pushReplacement(
                  context,
                  appSlideRoute(
                      (_) => LocalBrowserPage(store: store, source: source)),
                );
              }
            },
          ),
          const SourceGroupTitle('网络存储'),
          AddSourceTile(
            icon: Icons.cloud_queue,
            title: 'WebDAV',
            onTap: () => Navigator.of(context).pushReplacement(
              appSlideRoute((_) => WebdavSourceFormPage(store: store)),
            ),
          ),
          AddSourceTile(
            icon: Icons.cloud_sync_outlined,
            title: 'OpenList',
            onTap: () => Navigator.of(context).pushReplacement(
              appSlideRoute((_) => WebdavSourceFormPage(
                    store: store,
                    sourceType: SourceType.openlist,
                  )),
            ),
          ),
        ],
      ),
    );
  }
}

class WebdavSourceFormPage extends StatefulWidget {
  const WebdavSourceFormPage({
    required this.store,
    this.source,
    this.sourceType = SourceType.webdav,
    super.key,
  });

  final AppStore store;
  final MediaSourceConfig? source;
  final SourceType sourceType;

  @override
  State<WebdavSourceFormPage> createState() => _WebdavSourceFormPageState();
}

class _WebdavSourceFormPageState extends State<WebdavSourceFormPage> {
  SourceType get type => widget.source?.type ?? widget.sourceType;
  String get label => sourceTypeLabel(type);

  late final name =
      TextEditingController(text: widget.source?.name ?? '我的 WebDAV');
  late final baseUrl =
      TextEditingController(text: widget.source?.baseUrl ?? '');
  late final username =
      TextEditingController(text: widget.source?.username ?? '');
  late final password =
      TextEditingController(text: widget.source?.password ?? '');
  late final otpCode =
      TextEditingController(text: widget.source?.otpCode ?? '');
  late final directory =
      TextEditingController(text: widget.source?.directory ?? '/');
  bool busy = false;

  @override
  void initState() {
    super.initState();
    if (widget.source == null && type == SourceType.openlist) {
      name.text = '我的 OpenList';
    }
  }

  @override
  void dispose() {
    name.dispose();
    baseUrl.dispose();
    username.dispose();
    password.dispose();
    otpCode.dispose();
    directory.dispose();
    super.dispose();
  }

  Future<void> save() async {
    setState(() => busy = true);
    try {
      final draft = WebdavSourceDraft(
        name: name.text.trim(),
        baseUrl: baseUrl.text.trim(),
        username: username.text.trim(),
        password: password.text,
        otpCode: otpCode.text.trim(),
        directory: directory.text.trim(),
      );
      final editing = widget.source;
      if (editing != null) {
        await widget.store.updateWebdavSource(editing, draft);
        if (!mounted) return;
        Navigator.pop(context);
        return;
      }
      final source = type == SourceType.openlist
          ? await widget.store.addOpenlistSource(draft)
          : await widget.store.addWebdavSource(draft);
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        appSlideRoute(
            (_) => WebdavBrowserPage(store: widget.store, source: source)),
      );
    } catch (e) {
      if (mounted) {
        showSnack(context, '$label \u6DFB\u52A0\u5931\u8D25\uFF1A$e');
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
          title: Text(
              '${widget.source == null ? '\u6DFB\u52A0' : '\u7F16\u8F91'} $label \u6E90'),
          centerTitle: true),
      body: ListView(
        padding: const EdgeInsets.all(22),
        children: [
          TextField(
              controller: name,
              decoration: const InputDecoration(labelText: '名称')),
          TextField(
              controller: baseUrl,
              decoration: const InputDecoration(
                  labelText: '服务器地址，例如 https://host/dav')),
          TextField(
              controller: username,
              decoration: const InputDecoration(labelText: '用户名')),
          TextField(
              controller: password,
              decoration: const InputDecoration(labelText: '密码'),
              obscureText: true),
          if (type == SourceType.openlist)
            TextField(
                controller: otpCode,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'OTP Code\uFF08\u53EF\u9009\uFF09',
                  hintText:
                      '\u672A\u542F\u7528\u4E24\u6B65\u9A8C\u8BC1\u53EF\u7559\u7A7A',
                  floatingLabelBehavior: FloatingLabelBehavior.always,
                )),
          TextField(
              controller: directory,
              decoration: const InputDecoration(labelText: '目录路径，例如 /Movies/')),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: busy ? null : save,
            icon: busy
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.check),
            label: Text(widget.source == null ? '保存并选择内容' : '保存'),
          ),
        ],
      ),
    );
  }
}

class WebdavBrowserPage extends StatefulWidget {
  const WebdavBrowserPage(
      {required this.store, required this.source, super.key});

  final AppStore store;
  final MediaSourceConfig source;

  @override
  State<WebdavBrowserPage> createState() => _WebdavBrowserPageState();
}

class _WebdavBrowserPageState extends State<WebdavBrowserPage> {
  late String path = widget.source.directory;
  late Future<List<WebdavEntry>> future = load();
  bool adding = false;

  MediaSourceConfig get source => widget.store.sources.firstWhere(
        (value) => value.id == widget.source.id,
        orElse: () => widget.source,
      );

  RemoteFileClient get client => remoteClientForSource(source);

  Future<List<WebdavEntry>> load() => client.list(path);

  void refresh([String? next]) {
    setState(() {
      path = next ?? path;
      future = load();
    });
  }

  void goParent() {
    if (path != widget.source.directory) refresh(parentPath(path));
  }

  Future<void> addEntry(WebdavEntry entry, {bool asSeries = false}) async {
    setState(() => adding = true);
    try {
      await widget.store.addWebdavSelection(source, entry, asSeries: asSeries);
      if (mounted) {
        showSnack(context, entry.isDir ? '已添加文件夹，视频会显示在首页' : '已添加视频到首页');
      }
    } catch (e) {
      if (mounted) showSnack(context, '添加失败：$e');
    } finally {
      if (mounted) setState(() => adding = false);
    }
  }

  Future<void> removeEntry(WebdavEntry entry) async {
    setState(() => adding = true);
    try {
      await widget.store.removeWebdavSelection(source, entry);
      if (mounted) showSnack(context, entry.isDir ? '已取消此文件夹' : '已取消此视频');
    } catch (e) {
      if (mounted) showSnack(context, '取消失败：$e');
    } finally {
      if (mounted) setState(() => adding = false);
    }
  }

  SourcePathSelectionState selectionState(WebdavEntry entry) {
    final entryPath = entry.isDir ? normalizeRemoteDir(entry.path) : entry.path;
    return widget.store
        .sourcePathSelectionState(source, entryPath, isDir: entry.isDir);
  }

  bool isManualSeries(WebdavEntry entry) {
    final entryPath = entry.isDir ? normalizeRemoteDir(entry.path) : entry.path;
    return sourceManualSeriesPath(source, entryPath, isDir: entry.isDir);
  }

  Future<void> setSeriesEntry(WebdavEntry entry, bool enabled) async {
    setState(() => adding = true);
    try {
      await widget.store.setManualSeriesPath(
        source,
        entry.isDir ? normalizeRemoteDir(entry.path) : entry.path,
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
          title:
              Text(path == widget.source.directory ? widget.source.name : path),
          actions: [
            IconButton(
                tooltip: '刷新',
                onPressed: refresh,
                icon: const Icon(Icons.refresh)),
          ],
        ),
        body: FutureBuilder<List<WebdavEntry>>(
          future: future,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return ErrorView(message: '${snapshot.error}', onRetry: refresh);
            }
            final entries = snapshot.data ?? [];
            if (entries.isEmpty) {
              return EmptyState(
                icon: Icons.folder_off_outlined,
                title: '目录为空',
                message: '没有发现视频或子目录。请检查 WebDAV 目录路径和权限。',
                action: OutlinedButton(
                    onPressed: refresh, child: const Text('重新加载')),
              );
            }
            final hasParent = path != widget.source.directory;
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
                final entryPath =
                    entry.isDir ? normalizeRemoteDir(entry.path) : entry.path;
                final selected = widget.store.sourcePathSelectionState(
                    source, entryPath,
                    isDir: entry.isDir);
                return ListTile(
                  leading:
                      Icon(entry.isDir ? Icons.folder : Icons.movie_outlined),
                  title: Text(entry.name,
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle:
                      Text(entry.isDir ? '文件夹' : readableBytes(entry.size)),
                  trailing: SourceEntryMenu(
                    selectionState: selected,
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
                      openPlayer(
                          context,
                          widget.store,
                          MediaItem.remote(
                              source: widget.source, entry: entry));
                    }
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
