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
      color: const Color(0xFFF3F2F7),
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
