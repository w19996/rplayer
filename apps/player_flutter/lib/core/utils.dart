part of 'package:player_flutter/main.dart';

bool isVideoName(String value) =>
    videoExtensions.contains(p.extension(value).toLowerCase());

String newId() => DateTime.now().microsecondsSinceEpoch.toString();

String normalizeRemoteDir(String value) {
  if (value.trim().isEmpty) return '/';
  var path = value.trim();
  if (!path.startsWith('/')) path = '/$path';
  if (!path.endsWith('/')) path = '$path/';
  return path;
}

String parentPath(String value) {
  final normalized = normalizeRemoteDir(value);
  final trimmed = normalized.length > 1
      ? normalized.substring(0, normalized.length - 1)
      : normalized;
  final index = trimmed.lastIndexOf('/');
  if (index <= 0) return '/';
  return '${trimmed.substring(0, index)}/';
}

String sourcePathIdentity(
  MediaSourceConfig source,
  String path, {
  bool? isDir,
}) {
  if (source.type == SourceType.webdav) {
    return isDir == true || path.endsWith('/')
        ? normalizeRemoteDir(path)
        : path;
  }
  return path.replaceAll('\\', '/');
}

bool sourceStoredPathIsDir(MediaSourceConfig source, String path) {
  if (source.type == SourceType.webdav) return path.endsWith('/');
  return !isVideoName(path);
}

String sourceComparablePath(
  MediaSourceConfig source,
  String path, {
  bool? isDir,
}) {
  final identity = sourcePathIdentity(source, path, isDir: isDir);
  final directory = isDir ?? sourceStoredPathIsDir(source, identity);
  if (source.type == SourceType.local && directory && !identity.endsWith('/')) {
    return '$identity/';
  }
  return identity;
}

bool sourcePathCovers(
  MediaSourceConfig source,
  String container,
  String target, {
  bool? containerIsDir,
  bool? targetIsDir,
}) {
  final containerPath =
      sourceComparablePath(source, container, isDir: containerIsDir);
  final targetPath = sourceComparablePath(source, target, isDir: targetIsDir);
  if (containerPath == targetPath) return true;
  final directory = containerIsDir ?? sourceStoredPathIsDir(source, container);
  if (!directory) return false;
  final prefix =
      containerPath.endsWith('/') ? containerPath : '$containerPath/';
  return targetPath.startsWith(prefix);
}

Set<String> selectedPathsCoveredBy(
  MediaSourceConfig source,
  String selectedPath,
) {
  final normalizedPath =
      source.type == SourceType.webdav && selectedPath.endsWith('/')
          ? normalizeRemoteDir(selectedPath)
          : sourcePathIdentity(source, selectedPath);
  final pathIsDir = sourceStoredPathIsDir(source, normalizedPath);
  return source.selectedPaths
      .where(
        (path) => sourcePathCovers(
          source,
          normalizedPath,
          path,
          containerIsDir: pathIsDir,
          targetIsDir: sourceStoredPathIsDir(source, path),
        ),
      )
      .toSet();
}

String sourceItemPath(MediaSourceConfig source, MediaItem item) {
  if (source.type == SourceType.webdav) {
    final prefix = '${source.id}:';
    return item.id.startsWith(prefix) ? item.id.substring(prefix.length) : '';
  }
  return item.uri.replaceAll('\\', '/');
}

bool looksLikeSeasonFolderName(String value) {
  final text = value.trim();
  if (text.isEmpty) return false;
  return RegExp(r'^(season|s)\s*0?\d{1,2}$', caseSensitive: false)
          .hasMatch(text) ||
      RegExp(r'^第\s*\d{1,2}\s*季$').hasMatch(text) ||
      RegExp(r'^(specials?|sp|特别篇|番外)$', caseSensitive: false).hasMatch(text);
}

String remoteParentName(String value) {
  final parent = parentPath(value).trimRight();
  return parent.split('/').where((part) => part.isNotEmpty).lastOrNull ?? '';
}

String normalizeMediaResourcePath(String value) {
  var path = value.replaceAll('\\', '/').trim();
  if (path.isEmpty) return '/';
  while (path.contains('//')) {
    path = path.replaceAll('//', '/');
  }
  if (path == '/dav') return '/';
  if (path.startsWith('/dav/')) {
    path = '/${path.substring('/dav/'.length)}';
  }
  while (path.length > 1 &&
      path.endsWith('/') &&
      !RegExp(r'^[A-Za-z]:/$').hasMatch(path)) {
    path = path.substring(0, path.length - 1);
  }
  return path;
}

String normalizeMediaFolderKey(String value) {
  final sourceSeparator = value.indexOf(':');
  if (sourceSeparator < 0) return value;
  final typeSeparator = value.indexOf(':', sourceSeparator + 1);
  if (typeSeparator < 0) return value;
  final sourceId = value.substring(0, sourceSeparator);
  final sourceType = value.substring(sourceSeparator + 1, typeSeparator);
  final path = normalizeMediaResourcePath(value.substring(typeSeparator + 1));
  return '$sourceId:$sourceType:$path';
}

String? tmdbImageUrl(
  String? path,
  String size, {
  String imageBaseUrl = 'https://image.tmdb.org/t/p',
}) {
  if (path == null || path.isEmpty) return null;
  final normalized = path.startsWith('/') ? path : '/$path';
  return '${imageBaseUrl.trim().replaceAll(RegExp(r'/+$'), '')}/$size$normalized';
}

String normalizeMatchText(String value) {
  final buffer = StringBuffer();
  var lastWasSpace = false;
  for (final rune in value.toLowerCase().runes) {
    if (_isMatchTextRune(rune)) {
      buffer.writeCharCode(rune);
      lastWasSpace = false;
    } else if (!lastWasSpace) {
      buffer.write(' ');
      lastWasSpace = true;
    }
  }
  return buffer.toString().trim();
}

bool _isMatchTextRune(int rune) {
  return (rune >= 0x30 && rune <= 0x39) ||
      (rune >= 0x61 && rune <= 0x7A) ||
      (rune >= 0x4E00 && rune <= 0x9FFF) ||
      (rune >= 0x3400 && rune <= 0x4DBF) ||
      (rune >= 0xF900 && rune <= 0xFAFF);
}

String cleanTmdbHints(String value) {
  return value
      .replaceAll(
        RegExp(r'(?:^|[^\w])tmdb(?:id)?\s*[-=]\s*\d+(?=$|[^\w])',
            caseSensitive: false),
        ' ',
      )
      .trim();
}

int? explicitTmdbIdFromText(String value) {
  final match = RegExp(
    r'(?:^|[^\w])tmdb(?:id)?\s*[-=]\s*(\d+)(?=$|[^\w])',
    caseSensitive: false,
  ).firstMatch(value);
  return match == null ? null : int.tryParse(match.group(1)!);
}

int? explicitTmdbId(MediaItem item) {
  for (final value in [
    item.folderTitle,
    item.title,
    item.matchTitle,
    item.uri,
    item.id,
  ]) {
    final id = explicitTmdbIdFromText(value);
    if (id != null) return id;
  }
  return null;
}

int? inferredEpisodeNumber(MediaItem item) {
  if (item.episode != null) return item.episode;
  final title = item.title.trim();
  final seasonEpisode = RegExp(r'[Ss]\d{1,2}[Ee](\d{1,3})').firstMatch(title);
  if (seasonEpisode != null) return int.tryParse(seasonEpisode.group(1)!);
  final leading = RegExp(r'^0*(\d{1,3})(?:\D|$)').firstMatch(title);
  if (leading == null) return null;
  final value = int.tryParse(leading.group(1)!);
  if (value == null || value <= 0) return null;
  return value;
}

int? inferredSeasonNumber(MediaItem item) {
  if (item.season != null) return item.season;
  return inferredEpisodeNumber(item) == null ? null : 1;
}

bool looksLikeSeriesItem(MediaItem item) {
  if (item.mediaKind == 'TvEpisode') return true;
  if (item.season != null || item.episode != null) return true;
  final folderTitle = mediaFolderTitle(item);
  return folderTitle.isNotEmpty &&
      normalizeMatchText(folderTitle) != normalizeMatchText(item.title) &&
      inferredEpisodeNumber(item) != null;
}

String mediaFolderKey(MediaItem item) {
  if (item.type == SourceType.local) {
    final dir = p.dirname(item.uri);
    final folder = p.basename(dir);
    final groupDir = looksLikeSeasonFolderName(folder) ? p.dirname(dir) : dir;
    return normalizeMediaFolderKey('${item.sourceId}:local:$groupDir');
  }
  final uri = Uri.tryParse(item.uri);
  final path = uri == null ? item.uri : Uri.decodeComponent(uri.path);
  final parent = parentPath(path);
  final folder = remoteParentName(path);
  final groupPath = looksLikeSeasonFolderName(folder)
      ? parentPath(parent.substring(0, parent.length - 1))
      : parent;
  return normalizeMediaFolderKey('${item.sourceId}:webdav:$groupPath');
}

String mediaFolderTitle(MediaItem item) {
  if (item.folderTitle.trim().isNotEmpty) return item.folderTitle.trim();
  if (item.type == SourceType.local) {
    return mediaSeriesTitleFromLocalPath(item.uri);
  }
  final uri = Uri.tryParse(item.uri);
  final path = uri == null ? item.uri : Uri.decodeComponent(uri.path);
  return mediaSeriesTitleFromRemotePath(path);
}

String mediaSeriesTitleFromLocalPath(String path) {
  return RustCoreService.instance
      .mediaSeriesTitle(SourceType.local, path)
      .trim();
}

String mediaSeriesTitleFromRemotePath(String path) {
  return RustCoreService.instance
      .mediaSeriesTitle(SourceType.webdav, path)
      .trim();
}

String mediaIdentityFileName(MediaItem item) {
  if (item.type == SourceType.local) {
    return p.basename(item.uri);
  }
  final uri = Uri.tryParse(item.uri);
  final path = uri == null ? item.uri : Uri.decodeComponent(uri.path);
  final name = path.split('/').where((part) => part.isNotEmpty).lastOrNull;
  return name == null || name.isEmpty ? item.title : name;
}

String mediaGroupDisplayTitle(MediaItem item) {
  final title = mediaFolderTitle(item);
  return cleanTmdbHints(title.isNotEmpty ? title : item.title);
}

String describeMediaItem(MediaItem item) {
  final parts = <String>[
    mediaGroupDisplayTitle(item),
    mediaIdentityFileName(item),
    'match=${item.matchTitle}',
    'kind=${item.mediaKind}',
    if (item.season != null) 'S${item.season}',
    if (item.episode != null) 'E${item.episode}',
  ];
  return parts.where((part) => part.trim().isNotEmpty).join(' / ');
}

List<MediaFolderGroup> mediaFolderGroups(
  Iterable<MediaItem> items, {
  Map<String, int> lastPlayedAt = const {},
}) {
  final grouped = <String, List<MediaItem>>{};
  for (final item in items) {
    grouped.putIfAbsent(mediaFolderKey(item), () => []).add(item);
  }

  final groups = <MediaFolderGroup>[];
  for (final entry in grouped.entries) {
    final groupItems = [...entry.value]..sort(compareMediaItems);
    final latestPlayed = groupItems.fold<int>(
      0,
      (latest, item) => math.max(latest, lastPlayedAt[item.id] ?? 0),
    );
    final representative = latestPlayed > 0
        ? groupItems.reduce((a, b) =>
            (lastPlayedAt[a.id] ?? 0) >= (lastPlayedAt[b.id] ?? 0) ? a : b)
        : groupItems.first;
    groups.add(MediaFolderGroup(
      key: entry.key,
      title: mediaGroupDisplayTitle(representative),
      items: groupItems,
      representative: representative,
      latestPlayedAt: latestPlayed,
    ));
  }

  groups.sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
  return groups;
}

int compareMediaItems(MediaItem a, MediaItem b) {
  final episodeA = inferredEpisodeNumber(a);
  final episodeB = inferredEpisodeNumber(b);
  if (episodeA != null && episodeB != null && episodeA != episodeB) {
    return episodeA.compareTo(episodeB);
  }
  return a.title.toLowerCase().compareTo(b.title.toLowerCase());
}

MediaMetadata? mediaGroupMetadata(
    MediaFolderGroup group, Map<String, MediaMetadata> metadata) {
  return metadata[group.representative.id] ??
      group.items
          .map((item) => metadata[item.id])
          .whereType<MediaMetadata>()
          .firstOrNull;
}

String formatDuration(Duration value) {
  final total = value.inSeconds;
  final h = total ~/ 3600;
  final m = (total % 3600) ~/ 60;
  final s = total % 60;
  if (h > 0) {
    return '$h:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }
  return '$m:${s.toString().padLeft(2, '0')}';
}

String readableBytes(int? value) {
  if (value == null || value <= 0) return '未知大小';
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  var size = value.toDouble();
  var unit = 0;
  while (size >= 1024 && unit < units.length - 1) {
    size /= 1024;
    unit++;
  }
  return '${size.toStringAsFixed(size >= 10 ? 0 : 1)} ${units[unit]}';
}

Future<bool> ensureLocalStorageAccess(BuildContext context,
    {bool showDeniedMessage = true}) async {
  if (!Platform.isAndroid) return true;

  final videos = await Permission.videos.request();
  final storage = await Permission.storage.request();
  final manage = await Permission.manageExternalStorage.request();
  final granted = videos.isGranted || storage.isGranted || manage.isGranted;

  if (!granted && context.mounted && showDeniedMessage) {
    showSnack(context, '需要本地存储权限才能浏览视频目录');
    await openAppSettings();
  }
  return granted;
}

String localAccessHelp(String path) {
  if (!Platform.isAndroid) return '无法访问目录：$path';
  return '无法访问目录：$path\n\n如果这是模拟器共享目录，Android 11 及以上可能会阻止应用用普通文件路径读取它。请在系统设置中给本应用开启“所有文件访问权限”，或在模拟器里把视频复制到 Movies/Download 等可访问目录后重新选择。';
}
