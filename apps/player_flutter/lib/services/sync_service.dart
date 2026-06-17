part of 'package:player_flutter/main.dart';

Future<void> showSyncConfigDialog(BuildContext context, AppStore store) async {
  final current = store.syncConfig;
  final baseUrl = TextEditingController(text: current?.baseUrl ?? '');
  final username = TextEditingController(text: current?.username ?? '');
  final password = TextEditingController(text: current?.password ?? '');
  final configPath =
      TextEditingController(text: current?.configPath ?? '/Player/config.json');
  final databasePath = TextEditingController(
      text: current?.databasePath ?? '/Player/metadata.sqlite');
  var syncConfigFile = current?.syncConfigFile ?? true;
  var syncDatabase = current?.syncDatabase ?? true;

  await showDialog<void>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setDialogState) => AlertDialog(
        title: const Text('同步 WebDAV'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: baseUrl,
                decoration: const InputDecoration(labelText: '服务器地址'),
              ),
              TextField(
                controller: username,
                decoration: const InputDecoration(labelText: '用户名'),
              ),
              TextField(
                controller: password,
                decoration: const InputDecoration(labelText: '密码'),
                obscureText: true,
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('同步配置文件'),
                value: syncConfigFile,
                onChanged: (value) =>
                    setDialogState(() => syncConfigFile = value ?? true),
              ),
              TextField(
                controller: configPath,
                enabled: syncConfigFile,
                decoration: const InputDecoration(labelText: '配置文件路径'),
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('同步元数据数据库'),
                value: syncDatabase,
                onChanged: (value) =>
                    setDialogState(() => syncDatabase = value ?? true),
              ),
              TextField(
                controller: databasePath,
                enabled: syncDatabase,
                decoration: const InputDecoration(labelText: '数据库文件路径'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () async {
              await store.setSyncConfig(
                SyncConfig(
                  baseUrl: baseUrl.text.trim(),
                  username: username.text.trim(),
                  password: password.text,
                  configPath: configPath.text.trim().isEmpty
                      ? '/Player/config.json'
                      : configPath.text.trim(),
                  databasePath: databasePath.text.trim().isEmpty
                      ? '/Player/metadata.sqlite'
                      : databasePath.text.trim(),
                  syncConfigFile: syncConfigFile,
                  syncDatabase: syncDatabase,
                ),
              );
              if (context.mounted) Navigator.pop(context);
            },
            child: const Text('保存'),
          ),
        ],
      ),
    ),
  );
}

Future<void> uploadState(BuildContext context, AppStore store) async {
  final config = store.syncConfig;
  if (config == null) return showSnack(context, '请先设置同步 WebDAV');
  try {
    store.addDiagnosticLog('sync upload started', category: 'sync');
    final client = WebdavClient.fromSync(config);
    if (config.syncConfigFile) {
      await client.ensureParentCollections(config.configPath);
      await client.putText(config.configPath, store.exportSettings());
      store.addDiagnosticLog('sync uploaded settings: ${config.configPath}',
          category: 'sync');
    }
    if (config.syncDatabase) {
      await store.saveMediaStateDatabase();
      await store.replaceMetadataDatabase();
      final db = await store.metadataDatabaseFile;
      if (await db.exists()) {
        await client.ensureParentCollections(config.databasePath);
        await client.putBytes(config.databasePath, await db.readAsBytes());
        store.addDiagnosticLog('sync uploaded database: ${config.databasePath}',
            category: 'sync');
      }
    }
    if (context.mounted) showSnack(context, '同步已上传');
  } catch (e) {
    store.addDiagnosticLog('sync upload failed: $e', category: 'sync');
    if (context.mounted) showSnack(context, '上传失败：$e');
  }
}

Future<void> downloadState(BuildContext context, AppStore store) async {
  final config = store.syncConfig;
  if (config == null) return showSnack(context, '请先设置同步 WebDAV');
  try {
    store.addDiagnosticLog('sync download started', category: 'sync');
    final client = WebdavClient.fromSync(config);
    if (config.syncConfigFile) {
      final text = await client.getText(config.configPath);
      await store.importState(text);
      store.addDiagnosticLog('sync downloaded settings: ${config.configPath}',
          category: 'sync');
    }
    if (config.syncDatabase) {
      final bytes = await client.getBytes(config.databasePath);
      final db = await store.metadataDatabaseFile;
      await db.writeAsBytes(bytes, flush: true);
      await store.reloadDatabaseBackedState();
      store.addDiagnosticLog('sync downloaded database: ${config.databasePath}',
          category: 'sync');
    }
    if (context.mounted) showSnack(context, '同步已恢复');
  } catch (e) {
    store.addDiagnosticLog('sync download failed: $e', category: 'sync');
    if (context.mounted) showSnack(context, '下载失败：$e');
  }
}

void openAddSource(BuildContext context, AppStore store) {
  Navigator.of(context).push(appSlideRoute((_) => AddSourcePage(store: store)));
}

Route<T> appSlideRoute<T>(WidgetBuilder builder) {
  return PageRouteBuilder<T>(
    transitionDuration: const Duration(milliseconds: 130),
    reverseTransitionDuration: const Duration(milliseconds: 130),
    pageBuilder: (context, animation, secondaryAnimation) => builder(context),
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.linear,
        reverseCurve: Curves.linear,
      );
      return SlideTransition(
        position: Tween<Offset>(begin: const Offset(1, 0), end: Offset.zero)
            .animate(curved),
        child: child,
      );
    },
  );
}

Route<T> overlapSlideRoute<T>(WidgetBuilder builder) {
  return PageRouteBuilder<T>(
    transitionDuration: const Duration(milliseconds: 120),
    reverseTransitionDuration: const Duration(milliseconds: 120),
    pageBuilder: (context, animation, secondaryAnimation) => builder(context),
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.linear,
        reverseCurve: Curves.linear,
      );
      return SlideTransition(
        position: Tween<Offset>(begin: const Offset(1, 0), end: Offset.zero)
            .animate(curved),
        child: child,
      );
    },
  );
}

void openPlayer(BuildContext context, AppStore store, MediaItem item) {
  Navigator.of(context).push(
    PageRouteBuilder<void>(
      transitionDuration: Duration.zero,
      reverseTransitionDuration: Duration.zero,
      pageBuilder: (_, __, ___) => VideoPlayerPage(store: store, item: item),
    ),
  );
}

void showSnack(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}
