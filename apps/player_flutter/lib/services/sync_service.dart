part of 'package:player_flutter/main.dart';

Future<void> showSyncConfigDialog(BuildContext context, AppStore store) async {
  final current = store.syncConfig;
  final baseUrl = TextEditingController(text: current?.baseUrl ?? '');
  final username = TextEditingController(text: current?.username ?? '');
  final password = TextEditingController(text: current?.password ?? '');
  final configPath =
      TextEditingController(text: current?.configPath ?? '/Player/config.json');

  await showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('同步 WebDAV'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
                controller: baseUrl,
                decoration: const InputDecoration(labelText: '服务器地址')),
            TextField(
                controller: username,
                decoration: const InputDecoration(labelText: '用户名')),
            TextField(
                controller: password,
                decoration: const InputDecoration(labelText: '密码'),
                obscureText: true),
            TextField(
                controller: configPath,
                decoration: const InputDecoration(labelText: '配置文件路径')),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context), child: const Text('取消')),
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
              ),
            );
            if (context.mounted) Navigator.pop(context);
          },
          child: const Text('保存'),
        ),
      ],
    ),
  );
}

Future<void> uploadState(BuildContext context, AppStore store) async {
  final config = store.syncConfig;
  if (config == null) return showSnack(context, '请先设置同步 WebDAV');
  try {
    final client = WebdavClient.fromSync(config);
    await client.ensureParentCollections(config.configPath);
    await client.putText(config.configPath, store.exportState());
    if (context.mounted) showSnack(context, '配置已上传');
  } catch (e) {
    if (context.mounted) showSnack(context, '上传失败：$e');
  }
}

Future<void> downloadState(BuildContext context, AppStore store) async {
  final config = store.syncConfig;
  if (config == null) return showSnack(context, '请先设置同步 WebDAV');
  try {
    final text = await WebdavClient.fromSync(config).getText(config.configPath);
    await store.importState(text);
    if (context.mounted) showSnack(context, '配置已恢复');
  } catch (e) {
    if (context.mounted) showSnack(context, '下载失败：$e');
  }
}

void openAddSource(BuildContext context, AppStore store) {
  Navigator.of(context).push(appSlideRoute((_) => AddSourcePage(store: store)));
}

Route<T> appSlideRoute<T>(WidgetBuilder builder) {
  return PageRouteBuilder<T>(
    transitionDuration: const Duration(milliseconds: 260),
    reverseTransitionDuration: const Duration(milliseconds: 220),
    pageBuilder: (context, animation, secondaryAnimation) => builder(context),
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );
      return SlideTransition(
        position: Tween<Offset>(begin: const Offset(1, 0), end: Offset.zero)
            .animate(curved),
        child: DecoratedBox(
          decoration: const BoxDecoration(
            boxShadow: [
              BoxShadow(
                  color: Color(0x33000000),
                  blurRadius: 22,
                  offset: Offset(-8, 0)),
            ],
          ),
          child: child,
        ),
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
