part of 'package:player_flutter/main.dart';

class MediaLibraryPage extends StatelessWidget {
  const MediaLibraryPage({required this.store, super.key});

  final AppStore store;

  @override
  Widget build(BuildContext context) {
    final recentItems = store.items
        .where((item) => store.lastPlayedAt.containsKey(item.id))
        .toList()
      ..sort((a, b) => (store.lastPlayedAt[b.id] ?? 0)
          .compareTo(store.lastPlayedAt[a.id] ?? 0));
    return SafeArea(
      bottom: false,
      child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(22, 16, 22, 18),
              child: Row(
                children: [
                  const AppBrand(),
                  const Spacer(),
                  IconButton(
                      tooltip: '刷新',
                      onPressed: store.rescanAll,
                      icon: const Icon(Icons.refresh, size: 30)),
                ],
              ),
            ),
          ),
          if (!store.loaded)
            const SliverFillRemaining(
                child: Center(child: CircularProgressIndicator()))
          else if (store.items.isEmpty)
            SliverFillRemaining(
              child: EmptyState(
                icon: Icons.video_library_outlined,
                title: '还没有视频',
                message: '请先到资源库添加本地目录或 WebDAV 目录源。',
                action: FilledButton.icon(
                  onPressed: () => openAddSource(context, store),
                  icon: const Icon(Icons.add),
                  label: const Text('添加源'),
                ),
              ),
            )
          else ...[
            if (recentItems.isNotEmpty) ...[
              SliverToBoxAdapter(
                  child:
                      SectionHeader(title: '最近播放', count: recentItems.length)),
              SliverToBoxAdapter(
                child: SizedBox(
                  height: 176,
                  child: ListView.separated(
                    padding: const EdgeInsets.symmetric(horizontal: 22),
                    scrollDirection: Axis.horizontal,
                    itemCount: math.min(recentItems.length, 12),
                    separatorBuilder: (_, __) => const SizedBox(width: 14),
                    itemBuilder: (context, index) {
                      final item = recentItems[index];
                      return SizedBox(
                        width: 240,
                        child: RecentMediaTile(
                          item: item,
                          progressMs: store.progress[item.id] ?? 0,
                          durationMs: store.durations[item.id] ?? 0,
                          onTap: () => openPlayer(context, store, item),
                        ),
                      );
                    },
                  ),
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 20)),
            ],
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 22),
              sliver: SliverGrid.builder(
                itemCount: store.items.length,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  crossAxisSpacing: 14,
                  mainAxisSpacing: 18,
                  childAspectRatio: 0.88,
                ),
                itemBuilder: (context, index) {
                  final item = store.items[index];
                  return MediaTile(
                    item: item,
                    progressMs: 0,
                    onTap: () => openPlayer(context, store, item),
                  );
                },
              ),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 24)),
          ],
        ],
      ),
    );
  }
}
