part of 'package:player_flutter/main.dart';

class ProfilePage extends StatelessWidget {
  const ProfilePage({required this.store, super.key});

  final AppStore store;

  @override
  Widget build(BuildContext context) {
    final sync = store.syncConfig;
    final tmdb = store.tmdbConfig;
    final danmu = store.danmuConfig;
    return SafeArea(
      bottom: false,
      child: ListView(
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(22, 34, 22, 30),
            decoration: const BoxDecoration(
              color: Colors.white,
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
                      ? '${tmdb.language} / ${tmdb.region} / ${tmdbEndpointLabel(tmdb.apiBaseUrl)} / ${tmdbEndpointHost(tmdb.apiBaseUrl)}'
                      : 'API、海报、简介和演员信息',
                  onTap: () => Navigator.of(context).push(
                    appSlideRoute((_) => TmdbSettingsPage(store: store)),
                  ),
                ),
                ProfileActionCard(
                  icon: Icons.code_outlined,
                  title: '自定义规则',
                  subtitle:
                      '版本 ${store.versionDirectoryRegexes.length} 条 / 集数 ${store.episodeRegexes.length} 条',
                  onTap: () => Navigator.of(context).push(
                    appSlideRoute((_) => CustomRulesSettingsPage(store: store)),
                  ),
                ),
                ProfileActionCard(
                  icon: Icons.chat_bubble_outline,
                  title: '弹幕设置',
                  subtitle: danmu.enabled
                      ? (danmu.available
                          ? '${Uri.parse(danmu.requestBaseUrl).host} / token ${danmu.normalizedApiToken.isEmpty ? '默认' : '已设置'}'
                          : '已开启，未配置弹幕服务')
                      : '已关闭，进入后可开启和配置弹幕服务',
                  onTap: () => Navigator.of(context).push(
                    appSlideRoute((_) => DanmuSettingsPage(store: store)),
                  ),
                ),
                ProfileActionCard(
                  icon: Icons.tune_outlined,
                  title: 'MPV 进阶参数',
                  subtitle: mpvAdvancedPresetSummary(
                    store.mpvAdvancedPreset,
                    deviceClass: currentDeviceClass,
                  ),
                  onTap: () => Navigator.of(context).push(
                    appSlideRoute((_) => MpvAdvancedSettingsPage(store: store)),
                  ),
                ),
                ProfileActionCard(
                  icon: Icons.settings_outlined,
                  title: '同步与备份',
                  subtitle: sync == null
                      ? '配置 WebDAV，同步配置文件和数据库'
                      : '${sync.syncConfigFile ? '配置 ' : ''}${sync.syncDatabase ? '数据库' : ''}',
                  onTap: () => Navigator.of(context).push(
                    appSlideRoute((_) => SyncSettingsPage(store: store)),
                  ),
                ),
                ProfileActionCard(
                  icon: Icons.bug_report_outlined,
                  title: '诊断日志',
                  subtitle: store.diagnosticLoggingEnabled
                      ? '已开启，记录数据库、扫描、匹配、缓存、同步和播放事件'
                      : '已关闭，不记录新的诊断日志',
                  onTap: () => Navigator.of(context).push(
                    appSlideRoute(
                        (_) => DiagnosticLogSettingsPage(store: store)),
                  ),
                ),
                ProfileActionCard(
                  icon: Icons.info_outline,
                  title: '关于',
                  subtitle: '项目地址与捐助',
                  onTap: () => Navigator.of(context).push(
                    appSlideRoute((_) => const AboutPage()),
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

class AboutPage extends StatelessWidget {
  const AboutPage({super.key});

  static const projectUrl = 'https://github.com/w19996/rplayer';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('关于')),
      body: ListView(
        padding: const EdgeInsets.all(22),
        children: [
          const Text(
            'rplayer',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 24),
          Card(
            child: ListTile(
              leading: const Icon(Icons.link),
              title: const Text('项目地址'),
              subtitle: const SelectableText(projectUrl),
              trailing: const Icon(Icons.copy_outlined),
              onTap: () {
                Clipboard.setData(const ClipboardData(text: projectUrl));
                showSnack(context, '项目地址已复制');
              },
            ),
          ),
          Card(
            child: ListTile(
              leading: const Icon(Icons.balance_outlined),
              title: const Text('开源许可证'),
              subtitle:
                  const Text('rplayer：GPL-3.0 · TVBoxOS Spider 兼容层：AGPL-3.0'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => showLicensePage(
                context: context,
                applicationName: appName,
                applicationLegalese:
                    'TVBoxOS 派生组件来源与对应源码见项目 THIRD_PARTY_NOTICES.md',
              ),
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            '捐助支持',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 12),
          Image.asset('assets/donate.png'),
        ],
      ),
    );
  }
}

Widget _scrollingHelper(String text) => SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Text(text, maxLines: 1, softWrap: false),
    );

class MpvAdvancedSettingsPage extends StatelessWidget {
  const MpvAdvancedSettingsPage({required this.store, super.key});

  final AppStore store;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('MPV 进阶参数')),
      body: AnimatedBuilder(
        animation: store,
        builder: (context, _) {
          return ListView(
            padding: const EdgeInsets.all(22),
            children: [
              RadioGroup<String>(
                groupValue: mpvAdvancedPresetValues.contains(
                  store.mpvAdvancedPreset,
                )
                    ? store.mpvAdvancedPreset
                    : null,
                onChanged: (value) {
                  if (value == null) return;
                  unawaited(store.setMpvAdvancedPreset(value));
                },
                child: Column(
                  children: [
                    for (final preset in mpvAdvancedPresetValues)
                      RadioListTile<String>(
                        contentPadding:
                            const EdgeInsets.symmetric(horizontal: 4),
                        secondary: const Icon(Icons.tune_outlined),
                        title: Text(mpvAdvancedPresetLabel(preset)),
                        subtitle: Text(
                          mpvAdvancedPresetSummary(
                            preset,
                            deviceClass: currentDeviceClass,
                          ),
                        ),
                        value: preset,
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              for (final spec in mpvAdvancedOptionSpecs)
                MpvAdvancedOptionTile(store: store, spec: spec),
            ],
          );
        },
      ),
    );
  }
}

class MpvAdvancedOptionTile extends StatelessWidget {
  const MpvAdvancedOptionTile({
    required this.store,
    required this.spec,
    super.key,
  });

  final AppStore store;
  final MpvAdvancedOptionSpec spec;

  @override
  Widget build(BuildContext context) {
    final current = store.effectiveMpvAdvancedOptions()[spec.key] ?? '';
    final values = [
      ...spec.values,
      if (current.isNotEmpty && !spec.values.contains(current)) current,
    ];
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: DropdownButtonFormField<String>(
        isExpanded: true,
        initialValue: current.isEmpty ? null : current,
        decoration: InputDecoration(
          labelText: spec.label,
          helperText: spec.description,
          helperMaxLines: 2,
          prefixIcon: const Icon(Icons.tune_outlined),
        ),
        items: [
          for (final value in values)
            DropdownMenuItem(
              value: value,
              child: Text(
                spec.valueLabels[value] ?? value,
                overflow: TextOverflow.ellipsis,
              ),
            ),
        ],
        onChanged: (value) {
          if (value == null) return;
          unawaited(store.setMpvAdvancedOption(spec.key, value));
        },
      ),
    );
  }
}

class TmdbSettingsPage extends StatelessWidget {
  const TmdbSettingsPage({required this.store, super.key});

  final AppStore store;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('TMDB 与媒体信息')),
      body: AnimatedBuilder(
        animation: store,
        builder: (context, _) {
          final tmdb = store.tmdbConfig;
          final tmdbStatus = store.metadataRefreshing
              ? '正在匹配 TMDB 信息...'
              : store.tmdbLastStatus.isNotEmpty
                  ? store.tmdbLastStatus
                  : '刷新海报、背景图、剧集封面和演员信息';
          return ListView(
            padding: const EdgeInsets.all(22),
            children: [
              ProfileActionCard(
                icon: Icons.image_search_outlined,
                title: 'TMDB API',
                subtitle: tmdb.enabled
                    ? '${tmdb.language} / ${tmdb.region} / ${tmdbEndpointLabel(tmdb.apiBaseUrl)} / ${tmdbEndpointHost(tmdb.apiBaseUrl)}'
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
            ],
          );
        },
      ),
    );
  }
}

class CustomRulesSettingsPage extends StatelessWidget {
  const CustomRulesSettingsPage({required this.store, super.key});

  final AppStore store;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('自定义规则')),
      body: AnimatedBuilder(
        animation: store,
        builder: (context, _) {
          return ListView(
            padding: const EdgeInsets.all(22),
            children: [
              ProfileActionCard(
                icon: Icons.folder_copy_outlined,
                title: '版本目录正则',
                subtitle: store.versionDirectoryRegexes.isEmpty
                    ? '未添加自定义版本目录正则'
                    : '${store.versionDirectoryRegexes.length} 条自定义规则',
                onTap: () => Navigator.of(context).push(
                  appSlideRoute((_) => VersionRegexSettingsPage(store: store)),
                ),
              ),
              ProfileActionCard(
                icon: Icons.pin_outlined,
                title: '集数正则',
                subtitle: store.episodeRegexes.isEmpty
                    ? '未添加自定义集数正则'
                    : '${store.episodeRegexes.length} 条自定义规则',
                onTap: () => Navigator.of(context).push(
                  appSlideRoute((_) => EpisodeRegexSettingsPage(store: store)),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class VersionRegexSettingsPage extends StatefulWidget {
  const VersionRegexSettingsPage({required this.store, super.key});

  final AppStore store;

  @override
  State<VersionRegexSettingsPage> createState() =>
      _VersionRegexSettingsPageState();
}

class _VersionRegexSettingsPageState extends State<VersionRegexSettingsPage> {
  final controller = TextEditingController();
  bool saving = false;

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  Future<void> addPattern() async {
    final pattern = controller.text.trim();
    if (pattern.isEmpty || saving) return;
    setState(() => saving = true);
    try {
      await widget.store.addVersionDirectoryRegex(pattern);
      controller.clear();
      if (mounted) showSnack(context, '版本正则已保存，重新扫描后生效');
    } catch (error) {
      if (mounted) showSnack(context, '版本正则无效：$error');
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  Future<void> removePattern(int index) async {
    if (saving) return;
    setState(() => saving = true);
    try {
      await widget.store.removeVersionDirectoryRegexAt(index);
      if (mounted) showSnack(context, '版本正则已删除，重新扫描后生效');
    } catch (error) {
      if (mounted) showSnack(context, '删除失败：$error');
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('版本匹配正则')),
      body: AnimatedBuilder(
        animation: widget.store,
        builder: (context, _) {
          final patterns = widget.store.versionDirectoryRegexes;
          return ListView(
            padding: const EdgeInsets.all(22),
            children: [
              TextField(
                controller: controller,
                decoration: InputDecoration(
                  labelText: '目录正则',
                  helperText: '匹配到的目录会作为版本目录',
                  suffixIcon: IconButton(
                    tooltip: '添加',
                    icon: saving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.add),
                    onPressed: saving ? null : addPattern,
                  ),
                ),
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => addPattern(),
              ),
              const SizedBox(height: 18),
              if (patterns.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(
                    child: Text(
                      '暂无自定义正则',
                      style: TextStyle(color: Colors.grey),
                    ),
                  ),
                )
              else
                for (final entry in patterns.indexed)
                  Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFFE7EAF0)),
                    ),
                    child: ListTile(
                      title: Text(
                        entry.$2,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: IconButton(
                        tooltip: '删除',
                        icon: const Icon(Icons.delete_outline),
                        onPressed:
                            saving ? null : () => removePattern(entry.$1),
                      ),
                    ),
                  ),
            ],
          );
        },
      ),
    );
  }
}

class EpisodeRegexSettingsPage extends StatefulWidget {
  const EpisodeRegexSettingsPage({required this.store, super.key});

  final AppStore store;

  @override
  State<EpisodeRegexSettingsPage> createState() =>
      _EpisodeRegexSettingsPageState();
}

class _EpisodeRegexSettingsPageState extends State<EpisodeRegexSettingsPage> {
  final controller = TextEditingController();
  bool saving = false;

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  Future<void> addPattern() async {
    final pattern = controller.text.trim();
    if (pattern.isEmpty || saving) return;
    setState(() => saving = true);
    try {
      await widget.store.addEpisodeRegex(pattern);
      controller.clear();
      if (mounted) showSnack(context, '集数正则已保存，重新扫描后生效');
    } catch (error) {
      if (mounted) showSnack(context, '集数正则无效：$error');
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  Future<void> removePattern(int index) async {
    if (saving) return;
    setState(() => saving = true);
    try {
      await widget.store.removeEpisodeRegexAt(index);
      if (mounted) showSnack(context, '集数正则已删除，重新扫描后生效');
    } catch (error) {
      if (mounted) showSnack(context, '删除失败：$error');
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('集数匹配正则')),
      body: AnimatedBuilder(
        animation: widget.store,
        builder: (context, _) {
          final patterns = widget.store.episodeRegexes;
          return ListView(
            padding: const EdgeInsets.all(22),
            children: [
              TextField(
                controller: controller,
                decoration: InputDecoration(
                  labelText: '文件名正则',
                  helperText: r'第一个捕获组作为集数，例如 ^Part-(\d+)$',
                  suffixIcon: IconButton(
                    tooltip: '添加',
                    icon: saving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.add),
                    onPressed: saving ? null : addPattern,
                  ),
                ),
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => addPattern(),
              ),
              const SizedBox(height: 18),
              if (patterns.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(
                    child: Text(
                      '暂无自定义正则',
                      style: TextStyle(color: Colors.grey),
                    ),
                  ),
                )
              else
                for (final entry in patterns.indexed)
                  Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFFE7EAF0)),
                    ),
                    child: ListTile(
                      title: Text(
                        entry.$2,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: IconButton(
                        tooltip: '删除',
                        icon: const Icon(Icons.delete_outline),
                        onPressed:
                            saving ? null : () => removePattern(entry.$1),
                      ),
                    ),
                  ),
            ],
          );
        },
      ),
    );
  }
}

class DiagnosticLogSettingsPage extends StatelessWidget {
  const DiagnosticLogSettingsPage({required this.store, super.key});

  final AppStore store;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('诊断日志')),
      body: AnimatedBuilder(
        animation: store,
        builder: (context, _) {
          final latest = store.diagnosticLogs.reversed.take(8).toList();
          return ListView(
            padding: const EdgeInsets.all(22),
            children: [
              SwitchListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                secondary: const Icon(Icons.bug_report_outlined),
                title: const Text('记录诊断日志'),
                subtitle: Text(store.diagnosticLoggingEnabled
                    ? '记录数据库读写、扫描、匹配、TMDB、图片缓存、同步和播放事件'
                    : '关闭后不会继续追加新的诊断日志'),
                value: store.diagnosticLoggingEnabled,
                onChanged: (value) =>
                    unawaited(store.setDiagnosticLoggingEnabled(value)),
              ),
              ProfileActionCard(
                icon: Icons.file_download_outlined,
                title: '导出诊断日志',
                subtitle: '导出日志文件，共 ${store.diagnosticLogCount} 条记录',
                actionText: '导出',
                onTap: () async {
                  final path = await store.exportDiagnosticLogFile();
                  if (context.mounted) showSnack(context, '诊断日志已导出：$path');
                },
              ),
              ProfileActionCard(
                icon: Icons.delete_sweep_outlined,
                title: '清空诊断日志',
                subtitle: '清空本地诊断日志文件',
                actionText: '清空',
                onTap: () async {
                  await store.clearDiagnosticLogs();
                  if (context.mounted) showSnack(context, '诊断日志已清空');
                },
              ),
              if (latest.isNotEmpty) ...[
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '最近记录',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                ),
                const SizedBox(height: 8),
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: const Color(0xFFF5F6F8),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(
                      latest.join('\n'),
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12,
                        height: 1.45,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

class DanmuSettingsPage extends StatefulWidget {
  const DanmuSettingsPage({required this.store, super.key});

  final AppStore store;

  @override
  State<DanmuSettingsPage> createState() => _DanmuSettingsPageState();
}

class _DanmuSettingsPageState extends State<DanmuSettingsPage> {
  late final TextEditingController apiBaseUrl;
  late final TextEditingController apiToken;

  @override
  void initState() {
    super.initState();
    final current = widget.store.danmuConfig;
    apiBaseUrl = TextEditingController(text: current.normalizedApiBaseUrl);
    apiToken = TextEditingController(text: current.normalizedApiToken);
  }

  @override
  void dispose() {
    apiBaseUrl.dispose();
    apiToken.dispose();
    super.dispose();
  }

  Future<void> _save(DanmuConfig current) async {
    await widget.store.setDanmuConfig(
      current.copyWith(
        apiBaseUrl: apiBaseUrl.text.trim(),
        apiToken: apiToken.text.trim(),
      ),
    );
    if (mounted) showSnack(context, '弹幕设置已保存');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('弹幕设置')),
      body: AnimatedBuilder(
        animation: widget.store,
        builder: (context, _) {
          final current = widget.store.danmuConfig;
          return ListView(
            padding: const EdgeInsets.all(22),
            children: [
              SwitchListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                secondary: const Icon(Icons.chat_bubble_outline),
                title: const Text('启用弹幕'),
                subtitle: Text(current.available
                    ? '已连接到 ${Uri.parse(current.requestBaseUrl).host}'
                    : '开启后播放时会自动匹配和加载弹幕'),
                value: current.enabled,
                onChanged: (value) => unawaited(
                  widget.store.setDanmuConfig(current.copyWith(enabled: value)),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: apiBaseUrl,
                decoration: InputDecoration(
                  labelText: 'API 地址',
                  helper: _scrollingHelper(
                    '兼容 huangxd-/danmu_api，例如 https://danmu.example.com，不填 /api/v2',
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: apiToken,
                decoration: const InputDecoration(
                  labelText: 'Token',
                  helperText: '默认 87654321 可留空；自定义 TOKEN 时填写',
                ),
              ),
              const SizedBox(height: 18),
              FilledButton(
                onPressed: () => unawaited(_save(current)),
                child: const Text('保存'),
              ),
            ],
          );
        },
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
                : '${sync.configPath}\n${sync.databasePath}',
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
          ProfileActionCard(
            icon: Icons.file_download_outlined,
            title: '导出配置文件',
            subtitle: '只导出软件设置，不包含视频、播放进度和 TMDB 元数据',
            actionText: '导出',
            onTap: () async {
              final path = await store.exportConfigFile();
              if (context.mounted) showSnack(context, '配置文件已导出：$path');
            },
          ),
          ProfileActionCard(
            icon: Icons.sd_storage_outlined,
            title: '导出数据库文件',
            subtitle: '导出媒体库、播放进度、TMDB 元数据和图片缓存数据库',
            actionText: '导出',
            onTap: () async {
              showSnack(context, '正在准备数据库导出...');
              final path = await store.exportDatabaseFile();
              if (context.mounted) showSnack(context, '数据库已导出：$path');
            },
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
  final customApiBaseUrl =
      TextEditingController(text: tmdbProxyDisplayBaseUrl(current.apiBaseUrl));
  var endpointValue = selectedTmdbEndpointValue(current.apiBaseUrl);

  await showDialog<void>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setDialogState) {
        final selected = tmdbApiEndpoints
            .firstWhere((endpoint) => endpoint.url == endpointValue);
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
                  initialValue: endpointValue,
                  decoration: InputDecoration(
                    labelText: 'TMDB API 地址',
                    helper: _scrollingHelper(
                      selected.custom
                          ? '兼容 imaliang/tmdb-proxy：API 使用 /3，图片使用 /t/p'
                          : selected.url,
                    ),
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
                              endpoint.custom ? '输入你部署的代理域名' : endpoint.url,
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
                    setDialogState(() => endpointValue = value);
                  },
                ),
                if (endpointValue == tmdbProxyEndpointValue)
                  TextField(
                    controller: customApiBaseUrl,
                    decoration: const InputDecoration(
                      labelText: '自建 tmdb-proxy 域名',
                      helperText: '例如 https://tmdb.example.com',
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
                final apiBaseUrl = endpointValue == tmdbProxyEndpointValue
                    ? customApiBaseUrl.text.trim()
                    : endpointValue;
                final normalizedApiBaseUrl =
                    normalizeTmdbApiBaseUrl(apiBaseUrl);
                await store.setTmdbConfig(
                  TmdbConfig(
                    accessToken: token.text.trim(),
                    language: language.text.trim().isEmpty
                        ? 'zh-CN'
                        : language.text.trim(),
                    region:
                        region.text.trim().isEmpty ? 'CN' : region.text.trim(),
                    apiBaseUrl: normalizedApiBaseUrl,
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
