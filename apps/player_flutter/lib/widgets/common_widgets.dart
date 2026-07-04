part of 'package:player_flutter/main.dart';

class AppBrand extends StatelessWidget {
  const AppBrand({super.key});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
            boxShadow: const [
              BoxShadow(
                color: Color(0x1A000000),
                blurRadius: 6,
                offset: Offset(0, 2),
              ),
            ],
          ),
          child: const Padding(
            padding: EdgeInsets.all(5),
            child: CustomPaint(painter: _PlayStyleLogoPainter()),
          ),
        ),
        const SizedBox(width: 8),
        const Text(appName,
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
      ],
    );
  }
}

class _PlayStyleLogoPainter extends CustomPainter {
  const _PlayStyleLogoPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.shortestSide / 20;
    final stroke = 5.2 * scale;
    final strokePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final leftTop = Offset(5 * scale, 4 * scale);
    final leftBottom = Offset(5 * scale, 16 * scale);
    final right = Offset(16 * scale, 10 * scale);

    canvas.drawLine(
      leftTop,
      leftBottom,
      strokePaint..color = const Color(0xFF1A73E8),
    );
    canvas.drawLine(
      leftTop,
      right,
      strokePaint..color = const Color(0xFF1DB954),
    );
    canvas.drawLine(
      right,
      Offset(13.2 * scale, 11.6 * scale),
      strokePaint..color = const Color(0xFFFFC107),
    );
    canvas.drawLine(
      Offset(13.2 * scale, 11.6 * scale),
      leftBottom,
      strokePaint..color = const Color(0xFFFF2B20),
    );

    final cutout = Path()
      ..moveTo(8.4 * scale, 6.5 * scale)
      ..lineTo(14.0 * scale, 10 * scale)
      ..lineTo(8.4 * scale, 13.5 * scale)
      ..close();
    canvas.drawPath(cutout, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class MediaTile extends StatelessWidget {
  const MediaTile(
      {required this.item,
      required this.store,
      required this.metadata,
      required this.progressMs,
      required this.onTap,
      this.displayTitle,
      this.coverItem,
      this.itemCount = 1,
      this.onLongPress,
      super.key});

  final MediaItem item;
  final AppStore store;
  final MediaMetadata? metadata;
  final int progressMs;
  final VoidCallback onTap;
  final String? displayTitle;
  final MediaItem? coverItem;
  final int itemCount;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final remote = item.type == SourceType.webdav;
    final rating = metadata?.voteAverage;
    return InkWell(
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
                  if (metadata?.posterPath != null)
                    CachedTmdbImage(
                      store: store,
                      imagePath: metadata!.posterPath!,
                      size: 'w500',
                      fit: BoxFit.cover,
                      fallback: MediaPosterFallback(remote: remote),
                    )
                  else
                    VideoCoverImage(
                      store: store,
                      item: coverItem ?? item,
                      fit: BoxFit.cover,
                      fallback: MediaPosterFallback(remote: remote),
                    ),
                  if (rating != null && rating > 0)
                    Positioned(
                      right: 6,
                      bottom: 6,
                      child: Text(
                        rating.toStringAsFixed(1),
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
              metadata?.title.isNotEmpty == true
                  ? metadata!.title
                  : displayTitle ?? item.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 14)),
          const SizedBox(height: 3),
          Text(item.sourceName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.grey)),
          if (itemCount > 1)
            Text('共 $itemCount 集',
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
    required this.store,
    required this.metadata,
    required this.progressMs,
    required this.durationMs,
    required this.onTap,
    this.displayTitle,
    this.itemCount = 1,
    super.key,
  });

  final MediaItem item;
  final AppStore store;
  final MediaMetadata? metadata;
  final int progressMs;
  final int durationMs;
  final VoidCallback onTap;
  final String? displayTitle;
  final int itemCount;

  double get progressValue {
    if (progressMs <= 0) return 0;
    if (durationMs <= 0) return 0.06;
    return (progressMs / durationMs).clamp(0.0, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    final remote = item.type == SourceType.webdav;
    final imagePath = metadata?.stillPath ?? metadata?.backdropPath;
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
                  if (imagePath != null)
                    CachedTmdbImage(
                      store: store,
                      imagePath: imagePath,
                      size: metadata?.stillPath != null ? 'w780' : 'w780',
                      fit: BoxFit.cover,
                      fallback: MediaPosterFallback(remote: remote),
                    )
                  else
                    MediaPosterFallback(remote: remote),
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
            displayTitle ??
                (metadata?.title.isNotEmpty == true
                    ? metadata!.title
                    : item.title),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

class CachedTmdbImage extends StatefulWidget {
  const CachedTmdbImage({
    required this.store,
    required this.imagePath,
    required this.size,
    required this.fit,
    required this.fallback,
    this.alignment = Alignment.center,
    super.key,
  });

  final AppStore store;
  final String imagePath;
  final String size;
  final BoxFit fit;
  final Widget fallback;
  final Alignment alignment;

  @override
  State<CachedTmdbImage> createState() => _CachedTmdbImageState();
}

class _CachedTmdbImageState extends State<CachedTmdbImage> {
  Future<Uint8List?>? future;
  Uint8List? bytes;
  late String key;

  @override
  void initState() {
    super.initState();
    key = _keyFor(widget.imagePath, widget.size);
    _load();
  }

  @override
  void didUpdateWidget(CachedTmdbImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    final nextKey = _keyFor(widget.imagePath, widget.size);
    if (nextKey != key || oldWidget.store != widget.store) {
      key = nextKey;
      _load();
    }
  }

  String _keyFor(String imagePath, String size) => '$size:$imagePath';

  void _load() {
    bytes = widget.store.cachedTmdbImageMemoryBytes(
      widget.imagePath,
      widget.size,
    );
    future = bytes == null
        ? widget.store.cachedTmdbImageBytes(widget.imagePath, widget.size)
        : null;
  }

  @override
  Widget build(BuildContext context) {
    final memoryBytes = bytes;
    if (memoryBytes != null && memoryBytes.isNotEmpty) {
      return Image.memory(
        memoryBytes,
        fit: widget.fit,
        alignment: widget.alignment,
        gaplessPlayback: true,
        errorBuilder: (_, __, ___) => widget.fallback,
      );
    }
    return FutureBuilder<Uint8List?>(
      future: future,
      builder: (context, snapshot) {
        final bytes = snapshot.data;
        if (bytes != null && bytes.isNotEmpty) {
          return Image.memory(
            bytes,
            fit: widget.fit,
            alignment: widget.alignment,
            gaplessPlayback: true,
            errorBuilder: (_, __, ___) => widget.fallback,
          );
        }
        return widget.fallback;
      },
    );
  }
}

class VideoCoverImage extends StatefulWidget {
  const VideoCoverImage({
    required this.store,
    required this.item,
    required this.fit,
    required this.fallback,
    super.key,
  });

  final AppStore store;
  final MediaItem item;
  final BoxFit fit;
  final Widget fallback;

  @override
  State<VideoCoverImage> createState() => _VideoCoverImageState();
}

class _VideoCoverImageState extends State<VideoCoverImage> {
  late Future<Uint8List?> future;
  late String itemId;

  @override
  void initState() {
    super.initState();
    itemId = widget.item.id;
    future = widget.store.videoCoverBytes(widget.item);
  }

  @override
  void didUpdateWidget(VideoCoverImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.item.id != itemId || oldWidget.store != widget.store) {
      itemId = widget.item.id;
      future = widget.store.videoCoverBytes(widget.item);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Uint8List?>(
      future: future,
      builder: (context, snapshot) {
        final bytes = snapshot.data;
        if (bytes != null && bytes.isNotEmpty) {
          return Image.memory(
            bytes,
            fit: widget.fit,
            gaplessPlayback: true,
            errorBuilder: (_, __, ___) => widget.fallback,
          );
        }
        return widget.fallback;
      },
    );
  }
}

class MediaPosterFallback extends StatelessWidget {
  const MediaPosterFallback({required this.remote, super.key});

  final bool remote;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
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
        remote ? Icons.cloud_queue : Icons.movie_creation_outlined,
        size: 48,
        color: Colors.white70,
      ),
    );
  }
}

class SourceEntryMenu extends StatelessWidget {
  const SourceEntryMenu({
    required this.selected,
    required this.manualSeries,
    required this.enabled,
    required this.onAdd,
    required this.onRemove,
    required this.onSeriesOn,
    required this.onSeriesOff,
    super.key,
  });

  final bool selected;
  final bool manualSeries;
  final bool enabled;
  final VoidCallback onAdd;
  final VoidCallback onRemove;
  final VoidCallback onSeriesOn;
  final VoidCallback onSeriesOff;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      enabled: enabled,
      icon: Icon(
        manualSeries
            ? Icons.live_tv_outlined
            : selected
                ? Icons.check_circle
                : Icons.more_vert,
        color: selected ? const Color(0xFF2E7AF6) : null,
      ),
      onSelected: (value) {
        if (value == 'add') onAdd();
        if (value == 'remove') onRemove();
        if (value == 'series-on') onSeriesOn();
        if (value == 'series-off') onSeriesOff();
      },
      itemBuilder: (_) => [
        PopupMenuItem(
          value: selected ? 'remove' : 'add',
          child: Text(selected ? '取消添加' : '添加'),
        ),
        PopupMenuItem(
          value: manualSeries ? 'series-off' : 'series-on',
          child: Text(manualSeries ? '取消剧集设置' : '设为剧集'),
        ),
      ],
    );
  }
}

class SourceCard extends StatelessWidget {
  const SourceCard(
      {required this.source,
      required this.count,
      required this.onOpen,
      required this.onDelete,
      required this.onAdded,
      this.onEdit,
      super.key});

  final MediaSourceConfig source;
  final int count;
  final VoidCallback onOpen;
  final VoidCallback onDelete;
  final VoidCallback onAdded;
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 16, 8, 16),
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
                        style: const TextStyle(fontSize: 16)),
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
                  if (value == 'added') onAdded();
                  if (value == 'edit') onEdit?.call();
                  if (value == 'delete') onDelete();
                },
                itemBuilder: (_) => [
                  const PopupMenuItem(value: 'added', child: Text('已添加')),
                  if (onEdit != null)
                    const PopupMenuItem(value: 'edit', child: Text('编辑源')),
                  const PopupMenuItem(value: 'delete', child: Text('删除源')),
                ],
              ),
            ],
          ),
        ),
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
        leading: Icon(icon, color: const Color(0xFF2E7AF6), size: 28),
        title: Text(title, style: const TextStyle(fontSize: 16)),
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
          Icon(icon, color: const Color(0xFF2E7AF6), size: 28),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontSize: 16)),
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
              fontSize: 12, color: Colors.grey, fontWeight: FontWeight.w600)),
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
                  const TextStyle(fontSize: 19, fontWeight: FontWeight.w700)),
          const SizedBox(width: 6),
          Text('$count',
              style: const TextStyle(fontSize: 15, color: Colors.grey)),
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
          Icon(icon, size: 60, color: Colors.grey),
          const SizedBox(height: 18),
          Text(title,
              style:
                  const TextStyle(fontSize: 19, fontWeight: FontWeight.w700)),
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
                size: 40, color: dark ? Colors.white70 : Colors.red),
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
