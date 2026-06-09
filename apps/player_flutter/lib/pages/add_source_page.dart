part of 'package:player_flutter/main.dart';

class AddSourcePage extends StatelessWidget {
  const AddSourcePage({required this.store, super.key});

  final AppStore store;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF3F2F7),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF3F2F7),
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
              final dir = await FilePicker.platform.getDirectoryPath();
              if (dir == null) return;
              final source = await store.addLocalDirectory(dir);
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
        ],
      ),
    );
  }
}

class WebdavSourceFormPage extends StatefulWidget {
  const WebdavSourceFormPage({required this.store, super.key});

  final AppStore store;

  @override
  State<WebdavSourceFormPage> createState() => _WebdavSourceFormPageState();
}

class _WebdavSourceFormPageState extends State<WebdavSourceFormPage> {
  final name = TextEditingController(text: '我的 WebDAV');
  final baseUrl = TextEditingController();
  final username = TextEditingController();
  final password = TextEditingController();
  final directory = TextEditingController(text: '/');
  bool busy = false;

  @override
  void dispose() {
    name.dispose();
    baseUrl.dispose();
    username.dispose();
    password.dispose();
    directory.dispose();
    super.dispose();
  }

  Future<void> save() async {
    setState(() => busy = true);
    try {
      final source = await widget.store.addWebdavSource(
        WebdavSourceDraft(
          name: name.text.trim(),
          baseUrl: baseUrl.text.trim(),
          username: username.text.trim(),
          password: password.text,
          directory: directory.text.trim(),
        ),
      );
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        appSlideRoute(
            (_) => WebdavBrowserPage(store: widget.store, source: source)),
      );
    } catch (e) {
      if (mounted) showSnack(context, 'WebDAV 添加失败：$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('添加 WebDAV 源'), centerTitle: true),
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
            label: const Text('保存并选择内容'),
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

  WebdavClient get client => WebdavClient.fromSource(source);

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

  Future<void> addEntry(WebdavEntry entry) async {
    setState(() => adding = true);
    try {
      await widget.store.addWebdavSelection(source, entry);
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

  bool isSelected(WebdavEntry entry) {
    final entryPath = entry.isDir ? normalizeRemoteDir(entry.path) : entry.path;
    return source.selectedPaths.contains(entryPath);
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
                        openPlayer(
                            context,
                            widget.store,
                            MediaItem.webdav(
                                source: widget.source, entry: entry));
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
