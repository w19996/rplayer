part of 'package:player_flutter/main.dart';

class MediaLibraryPage extends StatelessWidget {
  const MediaLibraryPage({required this.store, super.key});

  final AppStore store;

  @override
  Widget build(BuildContext context) {
    if (!store.loaded) {
      return const SafeArea(
        bottom: false,
        child: Center(child: CircularProgressIndicator()),
      );
    }
    return SafeArea(
      bottom: false,
      child: FutureBuilder<_LibraryPageData>(
        future: _loadLibraryPageData(store),
        builder: (context, snapshot) {
          final data = snapshot.data;
          final loading = snapshot.connectionState == ConnectionState.waiting &&
              !snapshot.hasData;
          final home = data?.home ?? const <LibraryHomeEntry>[];
          final pendingGroups = data == null
              ? const <MediaFolderGroup>[]
              : _pendingMediaGroups(store, home);
          return CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(22, 16, 22, 18),
                  child: Row(
                    children: [
                      const AppBrand(),
                      const Spacer(),
                      _LibrarySearchButton(
                        store: store,
                        home: home,
                        pendingGroups: pendingGroups,
                      ),
                      _LibraryRefreshButton(store: store),
                    ],
                  ),
                ),
              ),
              if (loading)
                const SliverFillRemaining(
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (store.items.isEmpty &&
                  home.isEmpty &&
                  pendingGroups.isEmpty &&
                  data?.recent.isEmpty != false)
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
              else if (home.isEmpty &&
                  pendingGroups.isEmpty &&
                  data?.recent.isEmpty != false)
                const SliverFillRemaining(
                  child: EmptyState(
                    icon: Icons.image_search_outlined,
                    title: '等待 TMDB 匹配',
                    message: '数据库里已有视频资源，但还没有可展示的 TMDB 剧集信息。',
                    action: SizedBox.shrink(),
                  ),
                )
              else ...[
                if (data?.recent.isNotEmpty == true) ...[
                  SliverToBoxAdapter(
                    child: SectionHeader(
                      title: '最近播放',
                      count: data!.recent.length,
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: SizedBox(
                      height: 176,
                      child: ListView.separated(
                        padding: const EdgeInsets.symmetric(horizontal: 22),
                        scrollDirection: Axis.horizontal,
                        itemCount: math.min(data.recent.length, 12),
                        separatorBuilder: (_, __) => const SizedBox(width: 14),
                        itemBuilder: (context, index) {
                          final recent = data.recent[index];
                          final tvbox =
                              store.tvboxRecentByItemId(recent.itemId);
                          final item =
                              tvbox?.item ?? store.itemById(recent.itemId);
                          return SizedBox(
                            width: 252,
                            child: _RecentDbTile(
                              store: store,
                              recent: recent,
                              item: item,
                              tvboxPicture: tvbox?.video.picture,
                              onTap: item == null
                                  ? null
                                  : () async {
                                      try {
                                        if (tvbox != null) {
                                          await openTvboxRecent(
                                              context, store, tvbox);
                                        } else if (context.mounted) {
                                          openPlayer(context, store, item);
                                        }
                                      } catch (error) {
                                        if (context.mounted) {
                                          showSnack(context, '播放失败：$error');
                                        }
                                      }
                                    },
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  const SliverToBoxAdapter(child: SizedBox(height: 10)),
                ],
                for (final section in _libraryCategorySections(home))
                  ..._libraryGridSection(
                    context,
                    store,
                    section.title,
                    section.entries,
                  ),
                if (pendingGroups.isNotEmpty)
                  ..._pendingGridSection(context, store, pendingGroups),
                const SliverToBoxAdapter(child: SizedBox(height: 24)),
              ],
            ],
          );
        },
      ),
    );
  }

  List<Widget> _libraryGridSection(
    BuildContext context,
    AppStore store,
    String title,
    List<LibraryHomeEntry> entries,
  ) {
    if (entries.isEmpty) return const [];
    return [
      SliverToBoxAdapter(
        child: SectionHeader(title: title, count: entries.length),
      ),
      SliverPadding(
        padding: const EdgeInsets.symmetric(horizontal: 22),
        sliver: SliverGrid.builder(
          itemCount: entries.length,
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 126,
            crossAxisSpacing: 18,
            mainAxisSpacing: 22,
            childAspectRatio: 0.42,
          ),
          itemBuilder: (context, index) {
            final entry = entries[index];
            return _LibraryDbTile(
              store: store,
              entry: entry,
              onTap: () => openLibraryEntry(context, store, entry),
              onLongPress: () => unawaited(
                  showRemoveLibraryEntryDialog(context, store, entry)),
            );
          },
        ),
      ),
    ];
  }

  List<Widget> _pendingGridSection(
    BuildContext context,
    AppStore store,
    List<MediaFolderGroup> groups,
  ) {
    return [
      SliverToBoxAdapter(
        child: SectionHeader(title: '正在匹配', count: groups.length),
      ),
      SliverPadding(
        padding: const EdgeInsets.symmetric(horizontal: 22),
        sliver: SliverGrid.builder(
          itemCount: groups.length,
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 126,
            crossAxisSpacing: 18,
            mainAxisSpacing: 22,
            childAspectRatio: 0.42,
          ),
          itemBuilder: (context, index) {
            final group = groups[index];
            final current = currentGroupItem(group, store);
            return MediaTile(
              item: current,
              store: store,
              metadata: null,
              progressMs: store.progress[current.id] ?? 0,
              displayTitle: group.title,
              coverItem: group.items.first,
              itemCount: group.items.length,
              onTap: () {},
              onLongPress: () =>
                  unawaited(showRemoveMediaGroupDialog(context, store, group)),
            );
          },
        ),
      ),
    ];
  }

  List<_LibraryCategorySection> _libraryCategorySections(
    List<LibraryHomeEntry> entries,
  ) {
    final grouped = <String, List<LibraryHomeEntry>>{};
    for (final entry in entries) {
      final key = _libraryCategoryKey(entry);
      grouped.putIfAbsent(key, () => []).add(entry);
    }
    final sections = <_LibraryCategorySection>[];
    for (final entry in grouped.entries) {
      if (entry.key == 'other') continue;
      sections.add(_LibraryCategorySection(
        title: _libraryCategoryTitle(entry.key),
        entries: entry.value,
      ));
    }
    final other = grouped['other'];
    if (other != null && other.isNotEmpty) {
      sections.add(_LibraryCategorySection(title: '其他', entries: other));
    }
    return sections;
  }

  String _libraryCategoryKey(LibraryHomeEntry entry) {
    if (!entry.matched) return 'other';
    return mediaCategoryKey(
      mediaType: entry.mediaType,
      tmdbType: entry.tmdbType,
      genres: entry.genres,
    );
  }

  String _libraryCategoryTitle(String mediaType) =>
      mediaCategoryLabel(mediaType);
}

class _LibrarySearchButton extends StatelessWidget {
  const _LibrarySearchButton({
    required this.store,
    required this.home,
    required this.pendingGroups,
  });

  final AppStore store;
  final List<LibraryHomeEntry> home;
  final List<MediaFolderGroup> pendingGroups;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: '搜索',
      onPressed: () => showSearch<void>(
        context: context,
        delegate: _LibrarySearchDelegate(
          store: store,
          home: home,
          pendingGroups: pendingGroups,
        ),
      ),
      icon: const Icon(Icons.search, size: 26),
    );
  }
}

class _LibrarySearchDelegate extends SearchDelegate<void> {
  _LibrarySearchDelegate({
    required this.store,
    required this.home,
    required this.pendingGroups,
  }) : super(searchFieldLabel: '搜索媒体库');

  final AppStore store;
  final List<LibraryHomeEntry> home;
  final List<MediaFolderGroup> pendingGroups;

  @override
  List<Widget> buildActions(BuildContext context) {
    return [
      if (query.isNotEmpty)
        IconButton(
          tooltip: '清空',
          onPressed: () => query = '',
          icon: const Icon(Icons.clear),
        ),
    ];
  }

  @override
  Widget buildLeading(BuildContext context) {
    return IconButton(
      tooltip: '返回',
      onPressed: () => close(context, null),
      icon: const Icon(Icons.arrow_back),
    );
  }

  @override
  Widget buildResults(BuildContext context) => _buildResults(context);

  @override
  Widget buildSuggestions(BuildContext context) => _buildResults(context);

  Widget _buildResults(BuildContext context) {
    final text = query.trim().toLowerCase();
    final matchedHome =
        home.where((entry) => _matchesHome(entry, text)).toList();
    final matchedPending =
        pendingGroups.where((group) => _matchesGroup(group, text)).toList();
    final total = matchedHome.length + matchedPending.length;
    if (total == 0) {
      return const Center(child: Text('没有找到匹配的媒体'));
    }
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(22, 18, 22, 24),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 126,
        crossAxisSpacing: 18,
        mainAxisSpacing: 22,
        childAspectRatio: 0.42,
      ),
      itemCount: total,
      itemBuilder: (context, index) {
        if (index < matchedHome.length) {
          final entry = matchedHome[index];
          return _LibraryDbTile(
            store: store,
            entry: entry,
            onTap: () => _openEntry(context, entry),
            onLongPress: () =>
                unawaited(showRemoveLibraryEntryDialog(context, store, entry)),
          );
        }
        final group = matchedPending[index - matchedHome.length];
        final current = currentGroupItem(group, store);
        return MediaTile(
          item: current,
          store: store,
          metadata: null,
          progressMs: store.progress[current.id] ?? 0,
          displayTitle: group.title,
          coverItem: group.items.first,
          itemCount: group.items.length,
          onTap: () {},
          onLongPress: () =>
              unawaited(showRemoveMediaGroupDialog(context, store, group)),
        );
      },
    );
  }

  bool _matchesHome(LibraryHomeEntry entry, String text) {
    if (text.isEmpty) return true;
    return [
      entry.title,
      entry.overview,
      entry.folderPath,
      entry.releaseDate,
      ...entry.genres,
    ].whereType<String>().join(' ').toLowerCase().contains(text);
  }

  bool _matchesGroup(MediaFolderGroup group, String text) {
    if (text.isEmpty) return true;
    return [
      group.title,
      for (final item in group.items) ...[
        item.title,
        item.folderTitle,
        item.matchTitle,
        item.uri,
      ],
    ].join(' ').toLowerCase().contains(text);
  }

  void _openEntry(BuildContext context, LibraryHomeEntry entry) {
    final navigator = Navigator.of(context);
    close(context, null);
    pushLibraryEntry(navigator, store, entry);
  }
}

List<MediaFolderGroup> _pendingMediaGroups(
  AppStore store,
  List<LibraryHomeEntry> home,
) {
  final matched = home.map(_libraryEntryResourceKey).toSet();
  return mediaFolderGroups(
    store.items.where(
      (item) =>
          !store.metadata.containsKey(item.id) &&
          !matched.contains(_mediaGroupResourceKey(mediaFolderKey(item))),
    ),
    lastPlayedAt: store.lastPlayedAt,
    separateItemIds: store.explicitlySelectedItemIds(store.items),
  );
}

String _libraryEntryResourceKey(LibraryHomeEntry entry) {
  return '${entry.sourceId}:${normalizeMediaResourcePath(entry.folderPath)}';
}

String _mediaGroupResourceKey(String groupKey) {
  final sourceSeparator = groupKey.indexOf(':');
  if (sourceSeparator < 0) return groupKey;
  final typeSeparator = groupKey.indexOf(':', sourceSeparator + 1);
  if (typeSeparator < 0) return groupKey;
  final sourceId = groupKey.substring(0, sourceSeparator);
  final path = groupKey.substring(typeSeparator + 1);
  return '$sourceId:${normalizeMediaResourcePath(path)}';
}

class _LibraryRefreshButton extends StatelessWidget {
  const _LibraryRefreshButton({required this.store});

  final AppStore store;

  @override
  Widget build(BuildContext context) {
    final refreshing = store.metadataRefreshing;
    return IconButton(
      tooltip: refreshing ? 'TMDB 刷新中' : '刷新',
      onPressed: refreshing
          ? null
          : () => unawaited(store.rescanAll(forceMetadataRefresh: true)),
      icon: SizedBox(
        width: 26,
        height: 26,
        child: refreshing
            ? const Padding(
                padding: EdgeInsets.all(3),
                child: CircularProgressIndicator(strokeWidth: 2.4),
              )
            : const Icon(Icons.refresh, size: 26),
      ),
    );
  }
}

class _LibraryCategorySection {
  const _LibraryCategorySection({
    required this.title,
    required this.entries,
  });

  final String title;
  final List<LibraryHomeEntry> entries;
}

class _LibraryPageData {
  const _LibraryPageData({required this.home, required this.recent});

  final List<LibraryHomeEntry> home;
  final List<LibraryRecentEntry> recent;
}

Future<_LibraryPageData> _loadLibraryPageData(AppStore store) async {
  final values = await Future.wait([
    store.loadLibraryHome(),
    store.loadLibraryRecent(),
  ]);
  final home = filterLiveLibraryHome(
    store,
    values[0] as List<LibraryHomeEntry>,
  );
  final allRecent = <LibraryRecentEntry>[
    ...(values[1] as List<LibraryRecentEntry>),
    ...store.tvboxRecent.map((entry) => entry.libraryRecent),
  ]..sort((left, right) =>
      (right.lastPlayedAt ?? 0).compareTo(left.lastPlayedAt ?? 0));
  final recent = filterRecentByMediaGroup(store, allRecent);
  unawaited(store.preloadCachedTmdbImages([
    for (final entry in home)
      if (entry.posterPath != null) MapEntry(entry.posterPath!, 'w500'),
    for (final entry in recent.take(12))
      if (entry.stillPath != null)
        MapEntry(entry.stillPath!, 'w780')
      else if (entry.backdropPath != null)
        MapEntry(entry.backdropPath!, 'w780')
      else if (entry.posterPath != null)
        MapEntry(entry.posterPath!, 'w500'),
  ]));
  return _LibraryPageData(
    home: home,
    recent: recent,
  );
}

List<LibraryRecentEntry> filterRecentByMediaGroup(
  AppStore store,
  Iterable<LibraryRecentEntry> recent,
) {
  final seenGroups = <String>{};
  final filtered = <LibraryRecentEntry>[];
  for (final entry in recent) {
    final item = store.tvboxRecentByItemId(entry.itemId)?.item ??
        store.itemById(entry.itemId);
    if (item == null || !seenGroups.add(mediaFolderKey(item))) continue;
    filtered.add(entry);
  }
  return filtered;
}

List<LibraryHomeEntry> filterLiveLibraryHome(
  AppStore store,
  List<LibraryHomeEntry> home,
) {
  final sourceById = {for (final source in store.sources) source.id: source};
  final itemIds = store.items.map((item) => item.id).toSet();
  return home.where((entry) {
    if (entry.itemId != null && itemIds.contains(entry.itemId)) return true;
    final source = sourceById[entry.sourceId];
    if (source == null || entry.folderPath.isEmpty) return false;
    return store.items.any((item) {
      if (item.sourceId != entry.sourceId) return false;
      final itemPath = sourceItemPath(source, item);
      if (itemPath.isEmpty) return false;
      return sourcePathCovers(
        source,
        entry.folderPath,
        itemPath,
        containerIsDir: true,
        targetIsDir: false,
      );
    });
  }).toList();
}

class _LibraryDbTile extends StatelessWidget {
  const _LibraryDbTile({
    required this.store,
    required this.entry,
    required this.onTap,
    required this.onLongPress,
  });

  final AppStore store;
  final LibraryHomeEntry entry;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final coverItem = _libraryEntryCoverItem(store, entry);
    final remote =
        coverItem == null ? false : isRemoteSourceType(coverItem.type);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          onLongPress: onLongPress,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AspectRatio(
                aspectRatio: 2 / 3,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      if (entry.posterPath != null)
                        CachedTmdbImage(
                          store: store,
                          imagePath: entry.posterPath!,
                          size: 'w500',
                          fit: BoxFit.cover,
                          fallback: MediaPosterFallback(remote: remote == true),
                        )
                      else if (coverItem != null)
                        VideoCoverImage(
                          store: store,
                          item: coverItem,
                          fit: BoxFit.cover,
                          fallback: MediaPosterFallback(remote: remote == true),
                        )
                      else
                        MediaPosterFallback(remote: remote == true),
                      if ((entry.voteAverage ?? 0) > 0)
                        Positioned(
                          right: 6,
                          bottom: 6,
                          child: Text(
                            entry.voteAverage!.toStringAsFixed(1),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                              shadows: [
                                Shadow(color: Colors.black, blurRadius: 8),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 9),
              Text(
                entry.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 14),
              ),
            ],
          ),
        ),
        const SizedBox(height: 3),
        Text(
          '库中有 ${entry.localFileCount} 集',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: Colors.grey),
        ),
      ],
    );
  }
}

Future<void> showRemoveLibraryEntryDialog(
  BuildContext context,
  AppStore store,
  LibraryHomeEntry entry,
) async {
  final source = libraryEntrySource(store, entry);
  final path =
      source == null ? null : libraryEntryRemovePath(store, source, entry);
  if (source == null || path == null) {
    showSnack(context, '找不到可取消的添加路径');
    return;
  }
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('取消添加'),
      content: Text('从媒体库移除“${entry.title}”？'),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('返回'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('取消添加'),
        ),
      ],
    ),
  );
  if (confirmed != true) return;
  try {
    await store.removeSelectedPath(source, path);
    if (context.mounted) showSnack(context, '已取消添加');
  } catch (error) {
    if (context.mounted) showSnack(context, '取消添加失败：$error');
  }
}

Future<void> showRemoveMediaGroupDialog(
  BuildContext context,
  AppStore store,
  MediaFolderGroup group,
) async {
  final source = mediaGroupSource(store, group);
  final path = source == null ? null : mediaGroupRemovePath(source, group);
  if (source == null || path == null) {
    showSnack(context, '找不到可取消的添加路径');
    return;
  }
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('取消添加'),
      content: Text('从媒体库移除“${group.title}”？'),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('返回'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('取消添加'),
        ),
      ],
    ),
  );
  if (confirmed != true) return;
  try {
    await store.removeSelectedPath(source, path);
    if (context.mounted) showSnack(context, '已取消添加');
  } catch (error) {
    if (context.mounted) showSnack(context, '取消添加失败：$error');
  }
}

MediaSourceConfig? libraryEntrySource(AppStore store, LibraryHomeEntry entry) {
  for (final source in store.sources) {
    if (source.id == entry.sourceId) return source;
  }
  return null;
}

String? libraryEntryRemovePath(
  AppStore store,
  MediaSourceConfig source,
  LibraryHomeEntry entry,
) {
  final item = entry.itemId == null ? null : store.itemById(entry.itemId!);
  final itemPath = item == null ? null : sourceItemPath(source, item);
  if (entry.localFileCount == 1 && itemPath?.isNotEmpty == true) {
    return explicitSelectedFilePath(source, itemPath!) ?? itemPath;
  }
  return entry.folderPath.isEmpty ? null : entry.folderPath;
}

MediaSourceConfig? mediaGroupSource(AppStore store, MediaFolderGroup group) {
  if (group.items.isEmpty) return null;
  final sourceId = group.items.first.sourceId;
  for (final source in store.sources) {
    if (source.id == sourceId) return source;
  }
  return null;
}

String? mediaGroupRemovePath(
  MediaSourceConfig source,
  MediaFolderGroup group,
) {
  final itemPaths = [
    for (final item in group.items) sourceItemPath(source, item),
  ].where((path) => path.isNotEmpty).toList();
  if (group.items.length == 1 && itemPaths.isNotEmpty) {
    final itemPath = itemPaths.first;
    final selected = explicitSelectedFilePath(source, itemPath);
    if (selected != null) return selected;
  }
  return group.representative.groupPath.isEmpty
      ? itemPaths.firstOrNull
      : group.representative.groupPath;
}

String? explicitSelectedFilePath(MediaSourceConfig source, String itemPath) {
  final identity = sourcePathIdentity(source, itemPath, isDir: false);
  for (final selected in source.selectedPaths) {
    if (!sourceStoredPathIsDir(source, selected) &&
        sourcePathIdentity(source, selected, isDir: false) == identity) {
      return selected;
    }
  }
  return null;
}

MediaItem? _libraryEntryCoverItem(AppStore store, LibraryHomeEntry entry) {
  final itemId = entry.itemId;
  if (itemId != null) {
    final item = store.itemById(itemId);
    if (item != null) return item;
  }
  final key = _libraryEntryResourceKey(entry);
  final items = store.items
      .where((item) =>
          item.sourceId == entry.sourceId &&
          _mediaGroupResourceKey(mediaFolderKey(item)) == key)
      .toList()
    ..sort(compareMediaItems);
  return items.firstOrNull;
}

class _RecentDbTile extends StatelessWidget {
  const _RecentDbTile({
    required this.store,
    required this.recent,
    required this.item,
    required this.onTap,
    this.tvboxPicture,
  });

  final AppStore store;
  final LibraryRecentEntry recent;
  final MediaItem? item;
  final VoidCallback? onTap;
  final String? tvboxPicture;

  double get progressValue {
    if (recent.positionMs <= 0) return 0;
    final duration = recent.durationMs ?? 0;
    if (duration <= 0) return 0.06;
    return (recent.positionMs / duration).clamp(0.0, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    final mediaItem = item;
    final imagePath =
        recent.stillPath ?? recent.backdropPath ?? recent.posterPath;
    final hasTime = recent.positionMs > 0 || (recent.durationMs ?? 0) > 0;
    final timeText = (recent.durationMs ?? 0) > 0
        ? '${formatDuration(Duration(milliseconds: recent.positionMs))}/${formatDuration(Duration(milliseconds: recent.durationMs!))}'
        : formatDuration(Duration(milliseconds: recent.positionMs));
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              height: 142,
              width: double.infinity,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (imagePath != null)
                    CachedTmdbImage(
                      store: store,
                      imagePath: imagePath,
                      size: imagePath == recent.posterPath ? 'w500' : 'w780',
                      fit: BoxFit.cover,
                      fallback: MediaPosterFallback(
                        remote: mediaItem == null
                            ? false
                            : isRemoteSourceType(mediaItem.type),
                      ),
                    )
                  else if (tvboxPicture?.isNotEmpty == true)
                    FutureBuilder<Uint8List?>(
                      future: _loadTvboxImage(tvboxImageRequest(tvboxPicture!)),
                      builder: (_, snapshot) {
                        final bytes = snapshot.data;
                        return bytes == null || bytes.isEmpty
                            ? const MediaPosterFallback(remote: true)
                            : Image.memory(bytes,
                                fit: BoxFit.cover,
                                gaplessPlayback: true,
                                errorBuilder: (_, __, ___) =>
                                    const MediaPosterFallback(remote: true));
                      },
                    )
                  else if (mediaItem != null)
                    VideoCoverImage(
                      store: store,
                      item: mediaItem,
                      fit: BoxFit.cover,
                      fallback: MediaPosterFallback(
                        remote: isRemoteSourceType(mediaItem.type),
                      ),
                    )
                  else
                    const MediaPosterFallback(remote: false),
                  const Center(
                    child: CircleAvatar(
                      radius: 24,
                      backgroundColor: Color(0xAA000000),
                      child:
                          Icon(Icons.play_arrow, color: Colors.white, size: 32),
                    ),
                  ),
                  if (hasTime)
                    Positioned(
                      right: 6,
                      bottom: 8,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: const Color(0xAA000000),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 3),
                          child: Text(
                            timeText,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                    ),
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: LinearProgressIndicator(
                      minHeight: 3,
                      value: progressValue,
                      backgroundColor: const Color(0x66FFFFFF),
                      color: const Color(0xFF2E7AF6),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 22,
            child: _AutoScrollingSingleLineText(
              recent.displayTitle,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AutoScrollingSingleLineText extends StatefulWidget {
  const _AutoScrollingSingleLineText(this.text, {required this.style});

  final String text;
  final TextStyle style;

  @override
  State<_AutoScrollingSingleLineText> createState() =>
      _AutoScrollingSingleLineTextState();
}

class _AutoScrollingSingleLineTextState
    extends State<_AutoScrollingSingleLineText> {
  final ScrollController controller = ScrollController();
  bool running = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => start());
  }

  @override
  void didUpdateWidget(covariant _AutoScrollingSingleLineText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text) {
      running = false;
      WidgetsBinding.instance.addPostFrameCallback((_) => start(reset: true));
    }
  }

  Future<void> start({bool reset = false}) async {
    if (!mounted || running || !controller.hasClients) return;
    if (reset) controller.jumpTo(0);
    if (controller.position.maxScrollExtent <= 0) return;
    running = true;
    while (mounted && controller.hasClients && running) {
      await Future<void>.delayed(const Duration(milliseconds: 900));
      if (!mounted || !controller.hasClients || !running) break;
      final max = controller.position.maxScrollExtent;
      if (max <= 0) break;
      await controller.animateTo(
        max,
        duration: Duration(milliseconds: (max * 42).clamp(1800, 5200).round()),
        curve: Curves.easeInOut,
      );
      await Future<void>.delayed(const Duration(milliseconds: 700));
      if (!mounted || !controller.hasClients || !running) break;
      await controller.animateTo(
        0,
        duration: Duration(milliseconds: (max * 30).clamp(1200, 3600).round()),
        curve: Curves.easeInOut,
      );
    }
    running = false;
  }

  @override
  void dispose() {
    running = false;
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: SingleChildScrollView(
        controller: controller,
        scrollDirection: Axis.horizontal,
        physics: const NeverScrollableScrollPhysics(),
        child: Text(
          widget.text,
          maxLines: 1,
          softWrap: false,
          style: widget.style,
        ),
      ),
    );
  }
}

String recentMediaTitle(
    MediaItem item, MediaMetadata? metadata, String groupTitle) {
  final episode = inferredEpisodeNumber(item);
  final episodeName = metadata?.episodeName;
  if (episode != null && episodeName?.isNotEmpty == true) {
    return '$groupTitle 第 $episode 集 $episodeName';
  }
  if (episode != null) return '$groupTitle 第 $episode 集';
  return item.title;
}

void openMediaGroup(
    BuildContext context, AppStore store, MediaFolderGroup group) {
  Navigator.of(context).push(
    appSlideRoute((_) => MediaGroupPage(store: store, groupKey: group.key)),
  );
}

void openMediaGroupKey(BuildContext context, AppStore store, String groupKey) {
  Navigator.of(context).push(
    appSlideRoute((_) => MediaGroupPage(store: store, groupKey: groupKey)),
  );
}

void openLibraryEntry(
    BuildContext context, AppStore store, LibraryHomeEntry entry) {
  pushLibraryEntry(Navigator.of(context), store, entry);
}

void pushLibraryEntry(
    NavigatorState navigator, AppStore store, LibraryHomeEntry entry) {
  navigator.push(
    appSlideRoute(
        (_) => MediaGroupPage(store: store, groupKey: entry.folderKey)),
  );
}

class MediaGroupPage extends StatefulWidget {
  const MediaGroupPage(
      {required this.store, required this.groupKey, super.key});

  final AppStore store;
  final String groupKey;

  @override
  State<MediaGroupPage> createState() => _MediaGroupPageState();
}

class _MediaGroupPageState extends State<MediaGroupPage> {
  late Future<LibraryShowDetail> future;
  int revision = -1;

  @override
  void initState() {
    super.initState();
    revision = widget.store.metadataRevision;
    future = widget.store.loadLibraryShowDetail(widget.groupKey);
    widget.store.addListener(_storeChanged);
  }

  @override
  void dispose() {
    widget.store.removeListener(_storeChanged);
    super.dispose();
  }

  void _storeChanged() {
    if (!mounted) return;
    if (revision == widget.store.metadataRevision) {
      setState(() {});
      return;
    }
    setState(() {
      revision = widget.store.metadataRevision;
      future = widget.store.loadLibraryShowDetail(widget.groupKey);
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<LibraryShowDetail>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            backgroundColor: Color(0xFF090B08),
            body: Center(child: CircularProgressIndicator()),
          );
        }
        final detail = snapshot.data;
        if (detail == null || detail.files.isEmpty) {
          return Scaffold(
            appBar: AppBar(),
            body: const Center(child: Text('没有可播放的视频')),
          );
        }
        return _MediaGroupDbBody(store: widget.store, detail: detail);
      },
    );

    /* final group = mediaFolderGroups(
      store.items.where((item) => mediaFolderKey(item) == groupKey),
      lastPlayedAt: store.lastPlayedAt,
    ).firstOrNull;

    if (group == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: Text('没有可播放的视频')),
      );
    }

    final metadata = mediaGroupMetadata(group, store.metadata);
    final title =
        metadata?.title.isNotEmpty == true ? metadata!.title : group.title;
    final totalEpisodes = metadata?.totalEpisodes;
    final totalSeasons = metadata?.totalSeasons;
    final releaseDate = metadata?.releaseDate;
    final genres = metadata?.genres ?? const <String>[];
    final castNames = metadata?.castNames ?? const <String>[];
    final profilePaths = metadata?.profilePaths ?? const <String>[];
    final posterPath = metadata?.posterPath;
    final backdropPath = metadata?.backdropPath;
    final currentPlayable = currentGroupItem(group, store);
    final currentEpisode = inferredEpisodeNumber(currentPlayable) ?? 1;
    final currentProgressMs = store.progress[currentPlayable.id] ?? 0;
    final currentDurationMs = store.durations[currentPlayable.id] ?? 0;

    return Scaffold(
      backgroundColor: const Color(0xFF090B08),
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Stack(
              children: [
                if (backdropPath != null)
                  Positioned.fill(
                    child: CachedTmdbImage(
                      store: store,
                      imagePath: backdropPath,
                      size: 'w780',
                      fit: BoxFit.cover,
                      alignment: Alignment.topCenter,
                      fallback: const SizedBox.shrink(),
                    ),
                  ),
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.black.withValues(alpha: 0.34),
                          const Color(0xFF090B08).withValues(alpha: 0.78),
                          const Color(0xFF090B08),
                        ],
                        stops: const [0, 0.58, 1],
                      ),
                    ),
                  ),
                ),
                SafeArea(
                  bottom: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(22, 8, 22, 34),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            IconButton(
                              color: Colors.white,
                              onPressed: () => Navigator.of(context).maybePop(),
                              icon: const Icon(Icons.chevron_left, size: 32),
                            ),
                            Expanded(
                              child: Text(
                                title,
                                textAlign: TextAlign.center,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 21,
                                  fontWeight: FontWeight.w400,
                                ),
                              ),
                            ),
                            IconButton(
                              color: Colors.white,
                              onPressed: () {},
                              icon: const Icon(Icons.more_horiz, size: 30),
                            ),
                          ],
                        ),
                        const SizedBox(height: 126),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (posterPath != null) ...[
                              ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: SizedBox(
                                  width: 82,
                                  height: 123,
                                  child: CachedTmdbImage(
                                    store: store,
                                    imagePath: posterPath,
                                    size: 'w500',
                                    fit: BoxFit.cover,
                                    fallback: const ColoredBox(
                                      color: Color(0xFF252A22),
                                      child: Icon(
                                        Icons.movie_creation_outlined,
                                        color: Colors.white70,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 14),
                            ],
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Wrap(
                                    spacing: 10,
                                    runSpacing: 8,
                                    crossAxisAlignment:
                                        WrapCrossAlignment.center,
                                    children: [
                                      if ((metadata?.voteAverage ?? 0) > 0)
                                        _DarkMetaChip(
                                          icon: Icons.local_movies,
                                          label: metadata!.voteAverage!
                                              .toStringAsFixed(1),
                                          accent: const Color(0xFF60D264),
                                        ),
                                      if (releaseDate?.isNotEmpty == true)
                                        _DarkMetaChip(
                                          icon: Icons.calendar_month_outlined,
                                          label: releaseDate!,
                                        ),
                                      _DarkTextChip(
                                        label: totalEpisodes == null
                                            ? '库中有 ${group.items.length} 集'
                                            : '共 $totalEpisodes 集（库中有 ${group.items.length} 集）',
                                      ),
                                    ],
                                  ),
                                  if (genres.isNotEmpty) ...[
                                    const SizedBox(height: 12),
                                    Text(
                                      genres.join('  '),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: Color(0xDDFFFFFF),
                                        fontSize: 15,
                                        fontWeight: FontWeight.w400,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 18),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(28, 0, 28, 34),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                SizedBox(
                  height: 46,
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: Colors.black,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                    onPressed: () =>
                        openPlayer(context, store, currentPlayable),
                    icon: const Icon(Icons.play_arrow, size: 22),
                    label: Text(
                      dbPlayButtonLabel(current, currentProgressMs),
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 34),
                Row(
                  children: [
                    Text(
                      '第 ${totalSeasons == null || totalSeasons <= 1 ? 1 : 1} 季',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 23,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const Icon(Icons.arrow_drop_down, color: Colors.white),
                  ],
                ),
                const SizedBox(height: 8),
                Container(
                  height: 3,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  height: 154,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: group.items.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 12),
                    itemBuilder: (context, index) {
                      final item = group.items[index];
                      return SizedBox(
                        width: 176,
                        child: _EpisodeCard(
                          item: item,
                          store: store,
                          metadata: store.metadata[item.id] ?? metadata,
                          progressMs: store.progress[item.id] ?? 0,
                          durationMs: store.durations[item.id] ?? 0,
                          onTap: () => openPlayer(context, store, item),
                        ),
                      );
                    },
                  ),
                ),
                if (metadata?.overview?.isNotEmpty == true) ...[
                  const SizedBox(height: 28),
                  const _DarkSectionHeader(title: '剧情简介'),
                  const SizedBox(height: 12),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 180),
                    child: SingleChildScrollView(
                      child: Text(
                        metadata!.overview!,
                        style: const TextStyle(
                          color: Color(0xDDFFFFFF),
                          height: 1.65,
                          fontSize: 15,
                        ),
                      ),
                    ),
                  ),
                ],
                if (castNames.isNotEmpty) ...[
                  const SizedBox(height: 30),
                  const _DarkSectionHeader(title: '相关演员'),
                  const SizedBox(height: 16),
                  SizedBox(
                    height: 130,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: math.min(castNames.length, 10),
                      separatorBuilder: (_, __) => const SizedBox(width: 18),
                      itemBuilder: (context, index) {
                        return _ActorAvatar(
                          store: store,
                          name: castNames[index],
                          imagePath: index < profilePaths.length
                              ? profilePaths[index]
                              : null,
                        );
                      },
                    ),
                  ),
                ],
                const SizedBox(height: 24),
                const Divider(color: Color(0x22FFFFFF)),
                const SizedBox(height: 16),
                Text(
                  currentPlayable.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xDDFFFFFF),
                    fontSize: 15,
                    height: 1.6,
                  ),
                ),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Text(
                    itemFolderLine(currentPlayable),
                    maxLines: 1,
                    softWrap: false,
                    style: const TextStyle(
                      color: Color(0xDDFFFFFF),
                      fontSize: 15,
                      height: 1.6,
                    ),
                  ),
                ),
                Text(
                  itemInfoLine(currentPlayable, currentDurationMs),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xDDFFFFFF),
                    fontSize: 15,
                    height: 1.6,
                  ),
                ),
              ]),
            ),
          ),
        ],
      ),
    );
    */
  }
}

class _MediaGroupDbBody extends StatefulWidget {
  const _MediaGroupDbBody({required this.store, required this.detail});

  final AppStore store;
  final LibraryShowDetail detail;

  @override
  State<_MediaGroupDbBody> createState() => _MediaGroupDbBodyState();
}

class _MediaGroupDbBodyState extends State<_MediaGroupDbBody> {
  String? selectedVersionKey;

  AppStore get store => widget.store;
  LibraryShowDetail get detail => widget.detail;

  List<LibraryFileEntry> get versionFiles {
    final key = selectedVersionKey;
    if (key == null) {
      final fallback = currentLibraryFile(detail, store);
      final files = detail.files
          .where((file) => file.versionKey == fallback.versionKey)
          .toList();
      return files.isEmpty ? detail.files : files;
    }
    final files = detail.files.where((file) => file.versionKey == key).toList();
    return files.isEmpty ? detail.files : files;
  }

  Map<String, String> get versionLabels {
    final values = <String, String>{};
    for (final file in detail.files) {
      values.putIfAbsent(file.versionKey, () => file.versionLabel);
    }
    return values;
  }

  LibraryFileEntry currentVersionFile() {
    final files = versionFiles;
    final withHistory = files
        .where((file) => (store.lastPlayedAt[file.itemId] ?? 0) > 0)
        .toList();
    if (withHistory.isNotEmpty) {
      return withHistory.reduce((a, b) => (store.lastPlayedAt[a.itemId] ?? 0) >=
              (store.lastPlayedAt[b.itemId] ?? 0)
          ? a
          : b);
    }
    final withProgress = files
        .where(
            (file) => (store.progress[file.itemId] ?? file.positionMs ?? 0) > 0)
        .toList();
    if (withProgress.isNotEmpty) {
      return withProgress.reduce((a, b) =>
          (store.progress[a.itemId] ?? a.positionMs ?? 0) >=
                  (store.progress[b.itemId] ?? b.positionMs ?? 0)
              ? a
              : b);
    }
    return files.first;
  }

  Future<void> _openManualMatch(BuildContext context) async {
    final changed = await Navigator.of(context).push<bool>(
      appSlideRoute(
        (_) => ManualTmdbMatchPage(
          store: store,
          detail: detail,
        ),
      ),
    );
    if (changed == true && context.mounted) {
      showSnack(context, '手动识别已完成');
    }
  }

  Future<void> _refreshTmdb(BuildContext context) async {
    try {
      await store.refreshLibraryDetail(detail);
      if (context.mounted) showSnack(context, '刷新已完成');
    } catch (err) {
      if (context.mounted) showSnack(context, '刷新失败：$err');
    }
  }

  @override
  Widget build(BuildContext context) {
    final head = detail.representative!;
    final current = currentVersionFile();
    final currentItem = store.itemById(current.itemId);
    final versions = versionLabels;
    final title =
        head.showTitle?.isNotEmpty == true ? head.showTitle! : current.filename;
    final hasCoverImage = head.posterPath != null || currentItem != null;
    final currentProgressMs =
        store.progress[current.itemId] ?? current.positionMs ?? 0;
    final currentDurationMs =
        store.durations[current.itemId] ?? current.durationMs ?? 0;
    return Scaffold(
      backgroundColor: const Color(0xFF090B08),
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Stack(
              children: [
                if (head.backdropPath != null)
                  Positioned.fill(
                    child: CachedTmdbImage(
                      store: store,
                      imagePath: head.backdropPath!,
                      size: 'w780',
                      fit: BoxFit.cover,
                      alignment: Alignment.topCenter,
                      fallback: const SizedBox.shrink(),
                    ),
                  )
                else if (currentItem != null)
                  Positioned.fill(
                    child: VideoCoverImage(
                      store: store,
                      item: currentItem,
                      fit: BoxFit.cover,
                      fallback: const SizedBox.shrink(),
                    ),
                  ),
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.black.withValues(alpha: 0.34),
                          const Color(0xFF090B08).withValues(alpha: 0.78),
                          const Color(0xFF090B08),
                        ],
                        stops: const [0, 0.58, 1],
                      ),
                    ),
                  ),
                ),
                SafeArea(
                  bottom: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(22, 8, 22, 34),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            IconButton(
                              color: Colors.white,
                              onPressed: () => Navigator.of(context).maybePop(),
                              icon: const Icon(Icons.chevron_left, size: 32),
                            ),
                            Expanded(
                              child: Text(
                                title,
                                textAlign: TextAlign.center,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 21,
                                  fontWeight: FontWeight.w400,
                                ),
                              ),
                            ),
                            PopupMenuButton<String>(
                              tooltip: '更多',
                              color: Colors.white,
                              iconColor: Colors.white,
                              icon: const Icon(Icons.more_horiz, size: 30),
                              onSelected: (value) {
                                if (value == 'manual-match') {
                                  unawaited(_openManualMatch(context));
                                } else if (value == 'refresh') {
                                  unawaited(_refreshTmdb(context));
                                }
                              },
                              itemBuilder: (context) => const [
                                PopupMenuItem(
                                  value: 'refresh',
                                  child: Text('刷新'),
                                ),
                                PopupMenuItem(
                                  value: 'manual-match',
                                  child: Text('手动识别'),
                                ),
                              ],
                            ),
                          ],
                        ),
                        const SizedBox(height: 128),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (hasCoverImage) ...[
                              ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: SizedBox(
                                  width: 82,
                                  height: 123,
                                  child: head.posterPath != null
                                      ? CachedTmdbImage(
                                          store: store,
                                          imagePath: head.posterPath!,
                                          size: 'w500',
                                          fit: BoxFit.cover,
                                          fallback: const ColoredBox(
                                            color: Color(0xFF252A22),
                                            child: Icon(
                                              Icons.movie_creation_outlined,
                                              color: Colors.white70,
                                            ),
                                          ),
                                        )
                                      : VideoCoverImage(
                                          store: store,
                                          item: currentItem!,
                                          fit: BoxFit.cover,
                                          fallback: const ColoredBox(
                                            color: Color(0xFF252A22),
                                            child: Icon(
                                              Icons.movie_creation_outlined,
                                              color: Colors.white70,
                                            ),
                                          ),
                                        ),
                                ),
                              ),
                              const SizedBox(width: 14),
                            ],
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Wrap(
                                    spacing: 10,
                                    runSpacing: 8,
                                    crossAxisAlignment:
                                        WrapCrossAlignment.center,
                                    children: [
                                      if ((head.voteAverage ?? 0) > 0)
                                        _DarkMetaChip(
                                          icon: Icons.local_movies,
                                          label: head.voteAverage!
                                              .toStringAsFixed(1),
                                          accent: const Color(0xFF60D264),
                                        ),
                                      if (head.releaseDate?.isNotEmpty == true)
                                        _DarkMetaChip(
                                          icon: Icons.calendar_month_outlined,
                                          label: head.releaseDate!,
                                        ),
                                      _DarkTextChip(
                                        label: head.totalEpisodes == null
                                            ? '库中有 ${versionFiles.length} 集'
                                            : '共 ${head.totalEpisodes} 集（库中有 ${versionFiles.length} 集）',
                                      ),
                                    ],
                                  ),
                                  if (detail.genres.isNotEmpty) ...[
                                    const SizedBox(height: 12),
                                    Text(
                                      detail.genres.join('  '),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: Color(0xDDFFFFFF),
                                        fontSize: 15,
                                        fontWeight: FontWeight.w400,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 18),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(28, 0, 28, 34),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                SizedBox(
                  height: 46,
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: Colors.black,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                    onPressed: currentItem == null
                        ? null
                        : () => openPlayer(context, store, currentItem),
                    icon: const Icon(Icons.play_arrow, size: 22),
                    label: Text(
                      dbPlayButtonLabel(current, currentProgressMs),
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 34),
                Row(
                  children: [
                    Text(
                      dbSeasonLabel(current),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                    const Icon(Icons.arrow_drop_down, color: Colors.white),
                    if (versions.length > 1) ...[
                      const SizedBox(width: 14),
                      PopupMenuButton<String>(
                        tooltip: '切换版本',
                        color: Colors.white,
                        initialValue: selectedVersionKey ?? current.versionKey,
                        onSelected: (value) {
                          setState(() {
                            selectedVersionKey = value;
                          });
                        },
                        itemBuilder: (context) => [
                          for (final entry in versions.entries)
                            PopupMenuItem(
                              value: entry.key,
                              child: Text(entry.value),
                            ),
                        ],
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Flexible(
                              child: Text(
                                versions[selectedVersionKey ??
                                        current.versionKey] ??
                                    current.versionLabel,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w400,
                                ),
                              ),
                            ),
                            const Icon(
                              Icons.arrow_drop_down,
                              color: Colors.white,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 8),
                const Divider(
                  height: 1,
                  thickness: 1,
                  color: Color(0x44FFFFFF),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  height: 154,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: versionFiles.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 12),
                    itemBuilder: (context, index) {
                      final file = versionFiles[index];
                      final item = store.itemById(file.itemId);
                      return SizedBox(
                        width: 176,
                        child: _EpisodeDbCard(
                          file: file,
                          store: store,
                          onTap: item == null
                              ? null
                              : () => openPlayer(context, store, item),
                        ),
                      );
                    },
                  ),
                ),
                if (head.showOverview?.isNotEmpty == true) ...[
                  const SizedBox(height: 28),
                  const _DarkSectionHeader(title: '剧情简介'),
                  const SizedBox(height: 12),
                  Text(
                    head.showOverview!,
                    style: const TextStyle(
                      color: Color(0xDDFFFFFF),
                      height: 1.65,
                      fontSize: 15,
                    ),
                  ),
                ],
                if (detail.castNames.isNotEmpty) ...[
                  const SizedBox(height: 30),
                  const _DarkSectionHeader(title: '相关演员'),
                  const SizedBox(height: 16),
                  SizedBox(
                    height: 130,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: math.min(detail.castNames.length, 10),
                      separatorBuilder: (_, __) => const SizedBox(width: 18),
                      itemBuilder: (context, index) {
                        return _ActorAvatar(
                          store: store,
                          name: detail.castNames[index],
                          imagePath: index < detail.profilePaths.length
                              ? detail.profilePaths[index]
                              : null,
                        );
                      },
                    ),
                  ),
                ],
                const SizedBox(height: 24),
                const Divider(color: Color(0x22FFFFFF)),
                const SizedBox(height: 16),
                Text(
                  current.filename.isEmpty
                      ? current.relativePath
                      : current.filename,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xDDFFFFFF),
                    fontSize: 15,
                    height: 1.6,
                  ),
                ),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Text(
                    currentItem == null
                        ? current.relativePath
                        : itemFolderLine(currentItem),
                    maxLines: 1,
                    softWrap: false,
                    style: const TextStyle(
                      color: Color(0xDDFFFFFF),
                      fontSize: 15,
                      height: 1.6,
                    ),
                  ),
                ),
                Text(
                  dbItemInfoLine(current, currentDurationMs),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xDDFFFFFF),
                    fontSize: 15,
                    height: 1.6,
                  ),
                ),
              ]),
            ),
          ),
        ],
      ),
    );
  }
}

class ManualTmdbMatchPage extends StatefulWidget {
  const ManualTmdbMatchPage({
    required this.store,
    required this.detail,
    super.key,
  });

  final AppStore store;
  final LibraryShowDetail detail;

  @override
  State<ManualTmdbMatchPage> createState() => _ManualTmdbMatchPageState();
}

class _ManualTmdbMatchPageState extends State<ManualTmdbMatchPage> {
  late final TextEditingController controller;
  List<TmdbSearchCandidate> results = const [];
  bool loading = false;
  Object? error;
  int searchSerial = 0;
  TmdbSearchCandidate? replacing;

  @override
  void initState() {
    super.initState();
    controller = TextEditingController();
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  Future<void> _searchNow(String value) async {
    final query = value.trim();
    final serial = ++searchSerial;
    if (query.isEmpty) {
      setState(() {
        results = const [];
        loading = false;
        error = null;
      });
      return;
    }
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final next = await widget.store.searchTmdbCandidates(query);
      if (!mounted || serial != searchSerial) return;
      setState(() {
        results = next;
        loading = false;
      });
    } catch (err) {
      if (!mounted || serial != searchSerial) return;
      setState(() {
        error = err;
        loading = false;
      });
    }
  }

  Future<void> _selectCandidate(TmdbSearchCandidate candidate) async {
    setState(() => replacing = candidate);
    try {
      await widget.store.rematchLibraryDetail(widget.detail, candidate);
      if (mounted) Navigator.of(context).pop(true);
    } catch (err) {
      if (!mounted) return;
      setState(() => replacing = null);
      showSnack(context, '手动识别失败：$err');
    }
  }

  @override
  Widget build(BuildContext context) {
    final busy = replacing != null;
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 14, 18, 8),
              child: Text(
                '搜索并匹配影片',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      color: Colors.black,
                      fontWeight: FontWeight.w800,
                    ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 8, 18, 10),
              child: Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 46,
                      child: TextField(
                        controller: controller,
                        enabled: !busy,
                        autofocus: true,
                        textInputAction: TextInputAction.search,
                        onChanged: (_) => setState(() {}),
                        onSubmitted: _searchNow,
                        style: const TextStyle(color: Colors.black),
                        decoration: InputDecoration(
                          filled: true,
                          fillColor: const Color(0xFFF2F2F7),
                          prefixIcon: const Icon(
                            Icons.search,
                            color: Color(0xFF6E6E73),
                          ),
                          suffixIcon: controller.text.isEmpty
                              ? null
                              : IconButton(
                                  tooltip: '清空',
                                  icon: const Icon(
                                    Icons.cancel,
                                    color: Color(0xFFB0B0B6),
                                  ),
                                  onPressed: busy
                                      ? null
                                      : () {
                                          controller.clear();
                                          searchSerial++;
                                          results = const [];
                                          loading = false;
                                          error = null;
                                          setState(() {});
                                        },
                                ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide.none,
                          ),
                          contentPadding:
                              const EdgeInsets.symmetric(horizontal: 12),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  TextButton(
                    onPressed: busy ? null : () => _searchNow(controller.text),
                    child: const Text('搜索'),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: Color(0xFFE6E6EA)),
            Expanded(
              child: _buildResults(context),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResults(BuildContext context) {
    if (loading && results.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            '搜索失败：$error',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.black54),
          ),
        ),
      );
    }
    if (results.isEmpty) {
      return const Center(
        child: Text(
          '输入片名搜索 TMDB',
          style: TextStyle(color: Colors.black45),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
      itemCount: results.length + (loading ? 1 : 0),
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        if (index >= results.length) {
          return const Center(child: CircularProgressIndicator());
        }
        final candidate = results[index];
        return _TmdbCandidateCard(
          store: widget.store,
          candidate: candidate,
          busy: replacing != null,
          selected: replacing == candidate,
          onTap: () => _selectCandidate(candidate),
        );
      },
    );
  }
}

class _TmdbCandidateCard extends StatelessWidget {
  const _TmdbCandidateCard({
    required this.store,
    required this.candidate,
    required this.busy,
    required this.selected,
    required this.onTap,
  });

  final AppStore store;
  final TmdbSearchCandidate candidate;
  final bool busy;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: busy ? null : onTap,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFFE4E4E8)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: SizedBox(
                  width: 86,
                  height: 126,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      if (candidate.posterPath != null)
                        CachedTmdbImage(
                          store: store,
                          imagePath: candidate.posterPath!,
                          size: 'w185',
                          fit: BoxFit.cover,
                          fallback: const MediaPosterFallback(remote: false),
                        )
                      else
                        const MediaPosterFallback(remote: false),
                      Positioned(
                        left: 0,
                        top: 0,
                        child: DecoratedBox(
                          decoration: const BoxDecoration(
                            color: Color(0xFF1B3C9B),
                            borderRadius: BorderRadius.only(
                              bottomRight: Radius.circular(4),
                            ),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 5,
                              vertical: 2,
                            ),
                            child: Text(
                              candidate.mediaTypeLabel,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: SizedBox(
                  height: 126,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        candidate.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.black,
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          const Icon(
                            Icons.calendar_month_outlined,
                            size: 16,
                            color: Color(0xFF7A7A80),
                          ),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              '${candidate.displayDate}  |  ${candidate.displayCountry}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Color(0xFF7A7A80),
                                fontSize: 14,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Expanded(
                        child: Text(
                          candidate.overview?.trim().isNotEmpty == true
                              ? candidate.overview!.trim()
                              : '暂无简介',
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Color(0xFF7A7A80),
                            fontSize: 14,
                            height: 1.35,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (selected) ...[
                const SizedBox(width: 8),
                const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ActorAvatar extends StatelessWidget {
  const _ActorAvatar({
    required this.store,
    required this.name,
    required this.imagePath,
  });

  final AppStore store;
  final String name;
  final String? imagePath;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 76,
      child: Column(
        children: [
          ClipOval(
            child: SizedBox(
              width: 72,
              height: 72,
              child: imagePath == null
                  ? const ColoredBox(
                      color: Color(0xFF252A22),
                      child: Icon(Icons.person, color: Colors.white70),
                    )
                  : CachedTmdbImage(
                      store: store,
                      imagePath: imagePath!,
                      size: 'w185',
                      fit: BoxFit.cover,
                      fallback: const ColoredBox(
                        color: Color(0xFF252A22),
                        child: Icon(Icons.person, color: Colors.white70),
                      ),
                    ),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w400,
            ),
          ),
        ],
      ),
    );
  }
}

LibraryFileEntry currentLibraryFile(LibraryShowDetail detail, AppStore store) {
  final withHistory = detail.files
      .where((file) => (store.lastPlayedAt[file.itemId] ?? 0) > 0)
      .toList();
  if (withHistory.isNotEmpty) {
    return withHistory.reduce((a, b) => (store.lastPlayedAt[a.itemId] ?? 0) >=
            (store.lastPlayedAt[b.itemId] ?? 0)
        ? a
        : b);
  }
  final withProgress = detail.files
      .where(
          (file) => (store.progress[file.itemId] ?? file.positionMs ?? 0) > 0)
      .toList();
  if (withProgress.isNotEmpty) {
    return withProgress.reduce((a, b) =>
        (store.progress[a.itemId] ?? a.positionMs ?? 0) >=
                (store.progress[b.itemId] ?? b.positionMs ?? 0)
            ? a
            : b);
  }
  return detail.currentFile ?? detail.files.first;
}

String dbSeasonLabel(LibraryFileEntry file) {
  final season = file.seasonNumber;
  return season == null ? '剧集' : '第 $season 季';
}

String dbEpisodeLabel(LibraryFileEntry file) {
  final episode = file.episodeNumber;
  return episode == null ? file.displayTitle : '第 $episode 集';
}

String dbEpisodeTitle(LibraryFileEntry file, {String? fallback}) {
  final title = file.episodeName?.trim();
  if (title != null && title.isNotEmpty) return title;
  final value = fallback ?? file.displayTitle;
  return value.trim().isEmpty ? file.filename : value;
}

String dbPlaybackTitle(LibraryFileEntry file, {required String fallback}) {
  final values = <String>[];
  final showTitle = file.showTitle?.trim();
  if (showTitle != null && showTitle.isNotEmpty) values.add(showTitle);
  if (file.seasonNumber != null && file.episodeNumber != null) {
    values.add('S${file.seasonNumber}E${file.episodeNumber}');
  } else if (file.episodeNumber != null) {
    values.add('第 ${file.episodeNumber} 集');
  }
  final episodeTitle = file.episodeName?.trim();
  if (episodeTitle != null && episodeTitle.isNotEmpty) {
    values.add(episodeTitle);
  }
  if (values.isEmpty) return fallback;
  return values.join(' · ');
}

String dbPlayButtonLabel(LibraryFileEntry file, int progressMs) {
  final prefix = dbEpisodeLabel(file);
  if (progressMs <= 0) return prefix;
  return '$prefix ${formatDuration(Duration(milliseconds: progressMs))}';
}

MediaItem currentGroupItem(MediaFolderGroup group, AppStore store) {
  final withHistory = group.items
      .where((item) => (store.lastPlayedAt[item.id] ?? 0) > 0)
      .toList();
  if (withHistory.isNotEmpty) {
    return withHistory.reduce((a, b) =>
        (store.lastPlayedAt[a.id] ?? 0) >= (store.lastPlayedAt[b.id] ?? 0)
            ? a
            : b);
  }
  final withProgress =
      group.items.where((item) => (store.progress[item.id] ?? 0) > 0);
  if (withProgress.isNotEmpty) {
    return withProgress.reduce((a, b) =>
        (store.progress[a.id] ?? 0) >= (store.progress[b.id] ?? 0) ? a : b);
  }
  return group.items.first;
}

String playButtonLabel(int episode, int progressMs) {
  final prefix = '第 $episode 集';
  if (progressMs <= 0) return prefix;
  return '$prefix ${formatDuration(Duration(milliseconds: progressMs))}';
}

String itemFolderLine(MediaItem item) {
  if (isRemoteSourceType(item.type)) {
    final uri = Uri.tryParse(item.uri);
    final path = uri == null ? item.uri : Uri.decodeComponent(uri.path);
    return '${sourceTypeLabel(item.type)}: ${item.sourceName} - ${parentPath(path)}';
  }
  return '本地: ${item.sourceName} - ${p.dirname(item.uri)}';
}

String itemInfoLine(MediaItem item, int durationMs) {
  final values = <String>[
    durationMs > 0
        ? '总时长 ${formatDuration(Duration(milliseconds: durationMs))}'
        : '总时长未知',
    readableBytes(item.size),
  ];
  return values.join('  ');
}

String dbItemInfoLine(LibraryFileEntry file, int durationMs) {
  final values = <String>[
    durationMs > 0
        ? '总时长 ${formatDuration(Duration(milliseconds: durationMs))}'
        : '总时长未知',
    readableBytes(file.size),
  ];
  return values.join('  ');
}

class _EpisodeDbCard extends StatelessWidget {
  const _EpisodeDbCard({
    required this.file,
    required this.store,
    required this.onTap,
  });

  final LibraryFileEntry file;
  final AppStore store;
  final VoidCallback? onTap;

  double get progressValue {
    final progress = store.progress[file.itemId] ?? file.positionMs ?? 0;
    if (progress <= 0) return 0;
    final duration = store.durations[file.itemId] ?? file.durationMs ?? 0;
    if (duration <= 0) return 0.06;
    return (progress / duration).clamp(0.0, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    final imagePath = file.stillPath ?? file.backdropPath;
    final item = store.itemById(file.itemId);
    final progress = store.progress[file.itemId] ?? file.positionMs ?? 0;
    final duration = store.durations[file.itemId] ?? file.durationMs ?? 0;
    final hasTime = progress > 0 || duration > 0;
    final timeText = duration > 0
        ? '${formatDuration(Duration(milliseconds: progress))}/${formatDuration(Duration(milliseconds: duration))}'
        : formatDuration(Duration(milliseconds: progress));
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: AspectRatio(
              aspectRatio: 16 / 9,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (imagePath != null)
                    CachedTmdbImage(
                      store: store,
                      imagePath: imagePath,
                      size: 'w780',
                      fit: BoxFit.cover,
                      fallback: MediaPosterFallback(
                        remote: item == null
                            ? false
                            : isRemoteSourceType(item.type),
                      ),
                    )
                  else if (item != null)
                    VideoCoverImage(
                      store: store,
                      item: item,
                      fit: BoxFit.cover,
                      fallback: MediaPosterFallback(
                        remote: isRemoteSourceType(item.type),
                      ),
                    )
                  else
                    const MediaPosterFallback(remote: false),
                  const Center(
                    child: CircleAvatar(
                      radius: 15,
                      backgroundColor: Color(0xAA000000),
                      child:
                          Icon(Icons.play_arrow, color: Colors.white, size: 20),
                    ),
                  ),
                  if (hasTime)
                    Positioned(
                      right: 6,
                      bottom: 8,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: const Color(0xAA000000),
                          borderRadius: BorderRadius.circular(5),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 5, vertical: 2),
                          child: Text(
                            timeText,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.w400,
                            ),
                          ),
                        ),
                      ),
                    ),
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: LinearProgressIndicator(
                      minHeight: 3,
                      value: progressValue,
                      backgroundColor: const Color(0x66FFFFFF),
                      color: const Color(0xFF2E7AF6),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 7),
          Text(
            file.episodeNumber == null
                ? dbEpisodeTitle(file)
                : '${file.episodeNumber}. ${dbEpisodeTitle(file)}',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w400,
            ),
          ),
        ],
      ),
    );
  }
}

class _DarkMetaChip extends StatelessWidget {
  const _DarkMetaChip({
    required this.icon,
    required this.label,
    this.accent = Colors.white,
  });

  final IconData icon;
  final String label;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: accent, size: 15),
        const SizedBox(width: 5),
        Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 12,
            fontWeight: FontWeight.w400,
          ),
        ),
      ],
    );
  }
}

class _DarkTextChip extends StatelessWidget {
  const _DarkTextChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: const TextStyle(
        color: Colors.white,
        fontSize: 12,
        fontWeight: FontWeight.w400,
      ),
    );
  }
}

class _DarkSectionHeader extends StatelessWidget {
  const _DarkSectionHeader({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: const TextStyle(
        color: Colors.white,
        fontSize: 17,
        fontWeight: FontWeight.w400,
      ),
    );
  }
}

// ignore: unused_element
class _EpisodeCard extends StatelessWidget {
  const _EpisodeCard({
    required this.item,
    required this.store,
    required this.metadata,
    required this.progressMs,
    required this.durationMs,
    required this.onTap,
  });

  final MediaItem item;
  final AppStore store;
  final MediaMetadata? metadata;
  final int progressMs;
  final int durationMs;
  final VoidCallback onTap;

  double get progressValue {
    if (progressMs <= 0) return 0;
    if (durationMs <= 0) return 0.06;
    return (progressMs / durationMs).clamp(0.0, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    final imagePath = metadata?.stillPath ?? metadata?.backdropPath;
    final episode = inferredEpisodeNumber(item);
    final hasTime = progressMs > 0 || durationMs > 0;
    final timeText = durationMs > 0
        ? '${formatDuration(Duration(milliseconds: progressMs))}/${formatDuration(Duration(milliseconds: durationMs))}'
        : formatDuration(Duration(milliseconds: progressMs));
    final episodeTitle = metadata?.episodeName?.isNotEmpty == true
        ? metadata!.episodeName!
        : item.title;
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: AspectRatio(
              aspectRatio: 16 / 9,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (imagePath != null)
                    CachedTmdbImage(
                      store: store,
                      imagePath: imagePath,
                      size: 'w780',
                      fit: BoxFit.cover,
                      fallback: MediaPosterFallback(
                          remote: isRemoteSourceType(item.type)),
                    )
                  else
                    VideoCoverImage(
                      store: store,
                      item: item,
                      fit: BoxFit.cover,
                      fallback: MediaPosterFallback(
                          remote: isRemoteSourceType(item.type)),
                    ),
                  const Center(
                    child: CircleAvatar(
                      radius: 15,
                      backgroundColor: Color(0xAA000000),
                      child:
                          Icon(Icons.play_arrow, color: Colors.white, size: 20),
                    ),
                  ),
                  if (hasTime)
                    Positioned(
                      right: 6,
                      bottom: 8,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: const Color(0xAA000000),
                          borderRadius: BorderRadius.circular(5),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 5, vertical: 2),
                          child: Text(
                            timeText,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                    ),
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: LinearProgressIndicator(
                      minHeight: 3,
                      value: progressValue,
                      backgroundColor: const Color(0x66FFFFFF),
                      color: const Color(0xFF2E7AF6),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 7),
          Text(
            episode == null ? episodeTitle : '$episode. $episodeTitle',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
