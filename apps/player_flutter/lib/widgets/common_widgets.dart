part of 'package:player_flutter/main.dart';

class AppBrand extends StatelessWidget {
  const AppBrand({super.key});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
              color: const Color(0xFFFFD95C),
              borderRadius: BorderRadius.circular(8)),
          child: const Icon(Icons.local_movies, color: Color(0xFF2F5FA8)),
        ),
        const SizedBox(width: 8),
        const Text('爆米花播放器',
            style: TextStyle(fontSize: 23, fontWeight: FontWeight.w800)),
      ],
    );
  }
}

class MediaTile extends StatelessWidget {
  const MediaTile(
      {required this.item,
      required this.progressMs,
      required this.onTap,
      super.key});

  final MediaItem item;
  final int progressMs;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final remote = item.type == SourceType.webdav;
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Container(
              width: double.infinity,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: remote
                      ? const [Color(0xFF78A7F7), Color(0xFF7DD6C4)]
                      : const [Color(0xFFE9B36D), Color(0xFF8567C8)],
                ),
              ),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Icon(
                      remote
                          ? Icons.cloud_queue
                          : Icons.movie_creation_outlined,
                      size: 60,
                      color: Colors.white70),
                  const Center(
                    child: CircleAvatar(
                      radius: 24,
                      backgroundColor: Color(0x88000000),
                      child:
                          Icon(Icons.play_arrow, color: Colors.white, size: 34),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 9),
          Text(item.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 16)),
          const SizedBox(height: 3),
          Text(item.sourceName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.grey)),
        ],
      ),
    );
  }
}

class RecentMediaTile extends StatelessWidget {
  const RecentMediaTile({
    required this.item,
    required this.progressMs,
    required this.durationMs,
    required this.onTap,
    super.key,
  });

  final MediaItem item;
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
    final remote = item.type == SourceType.webdav;
    final hasTime = progressMs > 0 || durationMs > 0;
    final timeText = durationMs > 0
        ? '${formatDuration(Duration(milliseconds: progressMs))}/${formatDuration(Duration(milliseconds: durationMs))}'
        : formatDuration(Duration(milliseconds: progressMs));
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
                  DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: remote
                            ? const [Color(0xFF78A7F7), Color(0xFF7DD6C4)]
                            : const [Color(0xFFE9B36D), Color(0xFF8567C8)],
                      ),
                    ),
                    child: Icon(
                      remote
                          ? Icons.cloud_queue
                          : Icons.movie_creation_outlined,
                      size: 58,
                      color: Colors.white70,
                    ),
                  ),
                  const Center(
                    child: CircleAvatar(
                      radius: 28,
                      backgroundColor: Color(0xAA000000),
                      child:
                          Icon(Icons.play_arrow, color: Colors.white, size: 38),
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
                                fontWeight: FontWeight.w700),
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
          Text(
            item.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

class SourceCard extends StatelessWidget {
  const SourceCard(
      {required this.source,
      required this.count,
      required this.onOpen,
      required this.onDelete,
      super.key});

  final MediaSourceConfig source;
  final int count;
  final VoidCallback onOpen;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(22, 16, 12, 16),
      decoration: BoxDecoration(
          color: Colors.white, borderRadius: BorderRadius.circular(8)),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 38,
            decoration: BoxDecoration(
                color: const Color(0xFFDDE8FF),
                borderRadius: BorderRadius.circular(6)),
            child: Icon(
                source.type == SourceType.local
                    ? Icons.folder_special_outlined
                    : Icons.cloud_queue,
                color: const Color(0xFF2E7AF6)),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(source.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 18)),
                const SizedBox(height: 5),
                Text('${source.displayPath} · $count 个视频',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.grey)),
              ],
            ),
          ),
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'rescan') onOpen();
              if (value == 'delete') onDelete();
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'rescan', child: Text('管理内容')),
              const PopupMenuItem(value: 'delete', child: Text('删除源')),
            ],
          ),
          TextButton(onPressed: onOpen, child: const Text('浏览')),
        ],
      ),
    );
  }
}

class AddSourceTile extends StatelessWidget {
  const AddSourceTile(
      {required this.icon,
      required this.title,
      required this.onTap,
      super.key});

  final IconData icon;
  final String title;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
          color: Colors.white, borderRadius: BorderRadius.circular(8)),
      child: ListTile(
        leading: Icon(icon, color: const Color(0xFF2E7AF6), size: 34),
        title: Text(title, style: const TextStyle(fontSize: 18)),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}

class ProfileActionCard extends StatelessWidget {
  const ProfileActionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.actionText,
    required this.onTap,
    super.key,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String actionText;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(22, 16, 12, 16),
      decoration: BoxDecoration(
          color: const Color(0xFFF5F7FB),
          borderRadius: BorderRadius.circular(8)),
      child: Row(
        children: [
          Icon(icon, color: const Color(0xFF2E7AF6), size: 32),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontSize: 18)),
                const SizedBox(height: 5),
                Text(subtitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.grey)),
              ],
            ),
          ),
          TextButton(onPressed: onTap, child: Text(actionText)),
        ],
      ),
    );
  }
}

class SourceGroupTitle extends StatelessWidget {
  const SourceGroupTitle(this.title, {super.key});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 18, 0, 9),
      child: Text(title,
          style: const TextStyle(
              fontSize: 13, color: Colors.grey, fontWeight: FontWeight.w600)),
    );
  }
}

class SectionHeader extends StatelessWidget {
  const SectionHeader({required this.title, required this.count, super.key});

  final String title;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 0, 22, 16),
      child: Row(
        children: [
          Text(title,
              style:
                  const TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
          const SizedBox(width: 6),
          Text('$count',
              style: const TextStyle(fontSize: 17, color: Colors.grey)),
        ],
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState(
      {required this.icon,
      required this.title,
      required this.message,
      required this.action,
      super.key});

  final IconData icon;
  final String title;
  final String message;
  final Widget action;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 72, color: Colors.grey),
          const SizedBox(height: 18),
          Text(title,
              style:
                  const TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
          Text(message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.grey)),
          const SizedBox(height: 20),
          action,
        ],
      ),
    );
  }
}

class ErrorView extends StatelessWidget {
  const ErrorView(
      {required this.message,
      required this.onRetry,
      this.action,
      this.dark = false,
      super.key});

  final String message;
  final VoidCallback onRetry;
  final Widget? action;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline,
                size: 48, color: dark ? Colors.white70 : Colors.red),
            const SizedBox(height: 12),
            Text(message,
                textAlign: TextAlign.center,
                style: TextStyle(color: dark ? Colors.white : null)),
            const SizedBox(height: 16),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              alignment: WrapAlignment.center,
              children: [
                FilledButton(onPressed: onRetry, child: const Text('重试')),
                if (action != null) action!,
              ],
            ),
          ],
        ),
      ),
    );
  }
}
