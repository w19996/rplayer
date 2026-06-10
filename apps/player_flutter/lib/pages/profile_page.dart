part of 'package:player_flutter/main.dart';

class ProfilePage extends StatelessWidget {
  const ProfilePage({required this.store, super.key});

  final AppStore store;

  @override
  Widget build(BuildContext context) {
    final sync = store.syncConfig;
    final tmdb = store.tmdbConfig;
    return SafeArea(
      bottom: false,
      child: ListView(
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(22, 34, 22, 30),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xFFDCEEFF), Colors.white],
              ),
            ),
            child: Column(
              children: [
                const CircleAvatar(
                  radius: 42,
                  backgroundColor: Color(0xFFAFC7F7),
                  child: Icon(
                    Icons.cloud_sync_outlined,
                    color: Colors.white,
                    size: 40,
                  ),
                ),
                const SizedBox(height: 18),
                const Text(
                  '我的',
                  style: TextStyle(fontSize: 21, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 6),
                Text(
                  sync == null ? '未设置同步 WebDAV' : sync.baseUrl,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.grey),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(22),
            child: Column(
              children: [
                ProfileActionCard(
                  icon: Icons.image_search_outlined,
                  title: 'TMDB 与媒体信息',
                  subtitle: tmdb.enabled
                      ? '${tmdb.language} / ${tmdb.region} / ${Uri.parse(tmdb.apiBaseUrl).host}'
                      : 'API、海报、简介、演员和诊断日志',
                  actionText: '进入',
                  onTap: () => Navigator.of(context).push(
                    appSlideRoute((_) => TmdbSettingsPage(store: store)),
                  ),
                ),
                ProfileActionCard(
                  icon: Icons.settings_outlined,
                  title: '同步与备份',
                  subtitle: sync == null
                      ? '配置 WebDAV，同步配置文件和数据库'
                      : '${sync.syncConfigFile ? '配置 ' : ''}${sync.syncDatabase ? '数据库' : ''}',
                  actionText: '进入',
                  onTap: () => Navigator.of(context).push(
                    appSlideRoute((_) => SyncSettingsPage(store: store)),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class TmdbSettingsPage extends StatelessWidget {
  const TmdbSettingsPage({required this.store, super.key});

  final AppStore store;

  @override
  Widget build(BuildContext context) {
    final tmdb = store.tmdbConfig;
    final tmdbStatus = store.metadataRefreshing
        ? '正在匹配 TMDB 信息...'
        : store.tmdbLastStatus.isNotEmpty
            ? store.tmdbLastStatus
            : '刷新海报、背景图、剧集封面和演员信息';
    return Scaffold(
      appBar: AppBar(title: const Text('TMDB 与媒体信息')),
      body: ListView(
        padding: const EdgeInsets.all(22),
        children: [
          ProfileActionCard(
            icon: Icons.image_search_outlined,
            title: 'TMDB API',
            subtitle: tmdb.enabled
                ? '${tmdb.language} / ${tmdb.region} / ${Uri.parse(tmdb.apiBaseUrl).host}'
                : '获取影片信息、竖版海报和剧集封面',
            actionText: tmdb.enabled ? '编辑' : '设置',
            onTap: () => showTmdbConfigDialog(context, store),
          ),
          ProfileActionCard(
            icon: Icons.auto_awesome_motion_outlined,
            title: '刷新影片信息',
            subtitle: tmdbStatus,
            actionText: store.metadataRefreshing ? '进行中' : '刷新',
            onTap: () {
              if (!store.tmdbConfig.enabled) {
                showSnack(context, '请先设置 TMDB API Token');
                return;
              }
              unawaited(store.refreshMissingMetadata(force: true));
            },
          ),
          ProfileActionCard(
            icon: Icons.content_copy_outlined,
            title: '复制诊断日志',
            subtitle: '复制最近 ${store.diagnosticLogs.length} 条 TMDB 和扫描日志',
            actionText: '复制',
            onTap: () async {
              await Clipboard.setData(
                ClipboardData(text: store.exportDiagnosticLogs()),
              );
              if (context.mounted) showSnack(context, '诊断日志已复制');
            },
          ),
          ProfileActionCard(
            icon: Icons.delete_sweep_outlined,
            title: '清空诊断日志',
            subtitle: '清空本机保存的调试日志',
            actionText: '清空',
            onTap: () async {
              await store.clearDiagnosticLogs();
              if (context.mounted) showSnack(context, '诊断日志已清空');
            },
          ),
        ],
      ),
    );
  }
}

class SyncSettingsPage extends StatelessWidget {
  const SyncSettingsPage({required this.store, super.key});

  final AppStore store;

  @override
  Widget build(BuildContext context) {
    final sync = store.syncConfig;
    return Scaffold(
      appBar: AppBar(title: const Text('同步与备份')),
      body: ListView(
        padding: const EdgeInsets.all(22),
        children: [
          ProfileActionCard(
            icon: Icons.settings_outlined,
            title: '同步 WebDAV',
            subtitle: sync == null
                ? '单独配置备份位置'
                : '${sync.configPath} / ${sync.databasePath}',
            actionText: sync == null ? '设置' : '编辑',
            onTap: () => showSyncConfigDialog(context, store),
          ),
          ProfileActionCard(
            icon: Icons.upload_file,
            title: '上传同步数据',
            subtitle: '按开关上传配置文件和元数据数据库',
            actionText: '上传',
            onTap: () => uploadState(context, store),
          ),
          ProfileActionCard(
            icon: Icons.download_for_offline_outlined,
            title: '下载同步数据',
            subtitle: '按开关从 WebDAV 恢复配置和数据库',
            actionText: '下载',
            onTap: () => downloadState(context, store),
          ),
        ],
      ),
    );
  }
}

Future<void> showTmdbConfigDialog(BuildContext context, AppStore store) async {
  final current = store.tmdbConfig;
  final token = TextEditingController(text: current.accessToken);
  final language = TextEditingController(text: current.language);
  final region = TextEditingController(text: current.region);
  final proxyUrl = TextEditingController(text: current.proxyUrl);
  var apiBaseUrl = selectedTmdbApiBaseUrl(current.apiBaseUrl);

  await showDialog<void>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setDialogState) {
        final selected = tmdbApiEndpoints
            .firstWhere((endpoint) => endpoint.url == apiBaseUrl);
        return AlertDialog(
          title: const Text('TMDB API'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: token,
                  decoration: const InputDecoration(
                    labelText: 'Read Access Token',
                    helperText: 'TMDB 设置页里的 API Read Access Token',
                  ),
                  minLines: 1,
                  maxLines: 3,
                ),
                TextField(
                  controller: language,
                  decoration: const InputDecoration(labelText: '语言'),
                ),
                TextField(
                  controller: region,
                  decoration: const InputDecoration(labelText: '地区'),
                ),
                DropdownButtonFormField<String>(
                  isExpanded: true,
                  initialValue: apiBaseUrl,
                  decoration: InputDecoration(
                    labelText: 'TMDB API 地址',
                    helperText: selected.url,
                  ),
                  selectedItemBuilder: (context) => [
                    for (final endpoint in tmdbApiEndpoints)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          endpoint.label,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  items: [
                    for (final endpoint in tmdbApiEndpoints)
                      DropdownMenuItem(
                        value: endpoint.url,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(endpoint.label),
                            Text(
                              endpoint.url,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.grey,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                  onChanged: (value) {
                    if (value == null) return;
                    setDialogState(() => apiBaseUrl = value);
                  },
                ),
                TextField(
                  controller: proxyUrl,
                  decoration: const InputDecoration(
                    labelText: 'HTTP 代理',
                    helperText: '可选，例如 http://192.168.1.10:7890',
                  ),
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
                await store.setTmdbConfig(
                  TmdbConfig(
                    accessToken: token.text.trim(),
                    language: language.text.trim().isEmpty
                        ? 'zh-CN'
                        : language.text.trim(),
                    region:
                        region.text.trim().isEmpty ? 'CN' : region.text.trim(),
                    apiBaseUrl: apiBaseUrl,
                    proxyUrl: proxyUrl.text.trim(),
                  ),
                );
                if (context.mounted) Navigator.pop(context);
              },
              child: const Text('保存'),
            ),
          ],
        );
      },
    ),
  );
}
