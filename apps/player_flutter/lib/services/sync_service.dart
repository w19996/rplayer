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
  final uploadProgress = transferProgress(context, '正在上传数据库');
  try {
    showSnack(context, '正在上传同步数据...', loading: true);
    store.addDiagnosticLog('sync upload started', category: 'sync');
    final client = WebdavClient.fromSync(config);
    if (config.syncConfigFile) {
      if (context.mounted) showSnack(context, '正在上传配置文件...', loading: true);
      await client.ensureParentCollections(config.configPath);
      await client.putText(config.configPath, store.exportSettings());
      store.addDiagnosticLog('sync uploaded settings: ${config.configPath}',
          category: 'sync');
    }
    if (config.syncDatabase) {
      if (context.mounted) {
        showSnack(context, '正在等待数据库写入完成...', loading: true);
      }
      await store.waitForPendingDatabaseWrites();
      if (context.mounted) showSnack(context, '正在保存数据库状态...', loading: true);
      await store.saveMediaStateDatabase();
      await store.waitForPendingDatabaseWrites();
      final db = await store.metadataDatabaseFile;
      if (await db.exists()) {
        await client.ensureParentCollections(config.databasePath);
        final snapshot = await store.databaseSnapshotForUpload();
        try {
          await client.putFile(
            config.databasePath,
            snapshot,
            onProgress: uploadProgress,
          );
        } finally {
          if (await snapshot.exists()) await snapshot.delete();
        }
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
  final downloadProgress = transferProgress(context, '正在下载数据库');
  try {
    showSnack(context, '正在下载同步数据...', loading: true);
    store.addDiagnosticLog('sync download started', category: 'sync');
    final client = WebdavClient.fromSync(config);
    if (config.syncConfigFile) {
      if (context.mounted) showSnack(context, '正在下载配置文件...', loading: true);
      final text = await client.getText(config.configPath);
      if (context.mounted) showSnack(context, '正在恢复配置文件...', loading: true);
      await store.importState(text);
      store.addDiagnosticLog('sync downloaded settings: ${config.configPath}',
          category: 'sync');
    }
    if (config.syncDatabase) {
      if (context.mounted) {
        showSnack(context, '正在下载数据库，文件较大时请稍候...', loading: true);
      }
      await store.waitForPendingDatabaseWrites();
      final db = await store.metadataDatabaseFile;
      final temp = File('${db.path}.download');
      final backup = File('${db.path}.backup');
      if (await temp.exists()) await temp.delete();
      if (await backup.exists()) await backup.delete();
      await client.getFile(
        config.databasePath,
        temp,
        onProgress: downloadProgress,
      );
      if (context.mounted) showSnack(context, '正在写入数据库...', loading: true);
      if (await db.exists()) await db.rename(backup.path);
      try {
        await temp.rename(db.path);
      } catch (_) {
        if (await backup.exists() && !await db.exists()) {
          await backup.rename(db.path);
        }
        rethrow;
      }
      if (await backup.exists()) {
        try {
          await backup.delete();
        } catch (_) {}
      }
      if (context.mounted) showSnack(context, '正在加载数据库...', loading: true);
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

String formatFileSize(int bytes) {
  const units = ['B', 'KB', 'MB', 'GB'];
  var value = bytes.toDouble();
  var unitIndex = 0;
  while (value >= 1024 && unitIndex < units.length - 1) {
    value /= 1024;
    unitIndex++;
  }
  final text =
      unitIndex == 0 ? value.toStringAsFixed(0) : value.toStringAsFixed(1);
  return '$text ${units[unitIndex]}';
}

void showTransferProgress(
  BuildContext context,
  String label,
  int done,
  int total,
) {
  if (!context.mounted) return;
  final size = total > 0
      ? '${formatFileSize(done)} / ${formatFileSize(total)}'
      : formatFileSize(done);
  final percent = total > 0 ? '（${done * 100 ~/ total}%）' : '';
  showSnack(context, '$label：$size$percent', loading: true);
}

void Function(int done, int total) transferProgress(
  BuildContext context,
  String label,
) {
  var lastPercent = -1;
  var lastBytes = -1024 * 1024;
  return (done, total) {
    final percent = total > 0 ? done * 100 ~/ total : -1;
    if (done != total &&
        percent == lastPercent &&
        done - lastBytes < 1024 * 1024) {
      return;
    }
    lastPercent = percent;
    lastBytes = done;
    showTransferProgress(context, label, done, total);
  };
}

void showSnack(
  BuildContext context,
  String message, {
  bool loading = false,
}) {
  final messenger = ScaffoldMessenger.of(context)..clearSnackBars();
  messenger.showSnackBar(
    SnackBar(
      duration: loading ? const Duration(days: 1) : const Duration(seconds: 4),
      content: Row(
        children: [
          if (loading) ...[
            const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            ),
            const SizedBox(width: 12),
          ],
          Expanded(child: Text(message)),
        ],
      ),
    ),
  );
}
