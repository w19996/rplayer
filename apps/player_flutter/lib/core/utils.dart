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

String mediaPathName(MediaSourceConfig source, String path) {
  final value = source.type == SourceType.webdav
      ? path.trimRight().split('/').where((part) => part.isNotEmpty).lastOrNull
      : p.basename(path);
  if (value == null || value.isEmpty) return path;
  return isVideoName(value) ? p.basenameWithoutExtension(value) : value;
}

bool sourceManualSeriesPath(
  MediaSourceConfig source,
  String path, {
  required bool isDir,
}) {
  return source.seriesPaths
      .contains(sourcePathIdentity(source, path, isDir: isDir));
}

String? manualSeriesPathForItem(MediaSourceConfig source, MediaItem item) {
  if (source.id != item.sourceId) return null;
  final itemPath = sourceItemPath(source, item);
  if (itemPath.isEmpty) return null;
  final matches = source.seriesPaths
      .where((path) => sourcePathCovers(
            source,
            path,
            itemPath,
            targetIsDir: false,
          ))
      .toList();
  if (matches.isEmpty) return null;
  matches.sort((a, b) => b.length.compareTo(a.length));
  return matches.first;
}

MediaItem applyManualSeriesPath(MediaSourceConfig source, MediaItem item) {
  final root = manualSeriesPathForItem(source, item);
  if (root == null) return item;
  final title = mediaPathName(source, root);
  final version =
      manualSeriesVersion(source, root, sourceItemPath(source, item));
  return item.copyWith(
    folderTitle: title,
    matchTitle: title,
    mediaKind: 'TvEpisode',
    groupPath: normalizeMediaResourcePath(root),
    versionName: version.$1,
    versionDirPath: version.$2,
    manualSeries: true,
  );
}

(String, String) manualSeriesVersion(
  MediaSourceConfig source,
  String root,
  String itemPath,
) {
  if (!sourceStoredPathIsDir(source, root)) return ('', '');
  final rootPath = sourceComparablePath(source, root, isDir: true);
  final item = sourceComparablePath(source, itemPath, isDir: false);
  final prefix = rootPath.endsWith('/') ? rootPath : '$rootPath/';
  if (!item.startsWith(prefix)) return ('', '');
  final parts = item
      .substring(prefix.length)
      .split('/')
      .where((part) => part.isNotEmpty)
      .toList(growable: false);
  if (parts.length < 2) return ('', '');
  final versionName = parts.first;
  final versionDir = normalizeMediaResourcePath('$prefix$versionName');
  return (versionName, versionDir);
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

String tmdbSearchQueryFromText(String value) {
  var text = cleanTmdbHints(value)
      .replaceAll(RegExp(r'^\s*[A-Za-z]\s+(?=[\u3400-\u9FFF])'), ' ')
      .replaceAll(RegExp(r'[【】\[\]{}()（）《》「」『』，、；;]'), ' ')
      .replaceAll(RegExp(r'\b[Ss]\d{1,2}[Ee]\d{1,3}\b'), ' ')
      .replaceAll(RegExp(r'\b[Ee][Pp]?\d{1,3}\b'), ' ')
      .replaceAll(RegExp(r'第\s*[0-9一二三四五六七八九十百零两]+\s*[集季话]'), ' ')
      .replaceAll(RegExp(r'全\s*[0-9一二三四五六七八九十百零两]+\s*[集季话]'), ' ');
  final tokens = text
      .split(RegExp(r'[\s._\-~+]+'))
      .map(_stripTmdbNoiseFromToken)
      .map((token) => token.trim())
      .where((token) => token.isNotEmpty && !_isTmdbNoiseToken(token))
      .toList(growable: false);
  return tokens.join(' ').trim();
}

bool isUsefulTmdbSearchQuery(String value) {
  final normalized = normalizeMatchText(value);
  if (normalized.length < 2) return false;
  if (RegExp(r'^\d+$').hasMatch(normalized.replaceAll(' ', ''))) {
    return false;
  }
  const blocked = {
    '夸克',
    '来自 分享',
    '分享',
    '片头尾',
    '花絮',
    '字幕',
    '简繁字幕',
    '简繁英字幕',
    '内封',
  };
  if (blocked.contains(normalized)) return false;
  if (RegExp(r'^第\s*[0-9一二三四五六七八九十百零两]+\s*章').hasMatch(value.trim())) {
    return false;
  }
  return true;
}

String _stripTmdbNoiseFromToken(String token) {
  var value = token;
  const zhNoise = [
    '杜比视界',
    '简繁英字幕',
    '简繁字幕',
    '中英字幕',
    '外挂字幕',
    '高码率',
    '低码率',
    '高帧率',
    '原盘',
    '蓝光',
    '压制版',
    '网盘版',
    '收藏版',
    '无水印',
    '杜比',
    '国语',
    '粤语',
    '日语',
    '英语',
    '中字',
    '简中',
    '繁中',
    '内封',
    '字幕',
    '简繁',
    '双语',
  ];
  for (final word in zhNoise) {
    value = value.replaceAll(word, '');
  }
  return value
      .replaceAll(
        RegExp(
          r'(dolbyvision|hdr10\+?|2160p|1080p|720p|480p|120fps|60fps|\d{2,3}fps|web[- ]?dl|webrip|blu[- ]?ray|bdrip|remux|hdtv|tvrip|dvdrip|truehd|dts[- ]?hd|h\.?265|x265|hevc|h\.?264|x264|avc|av1|vp9|10bit|8bit|atmos|dolby|hdr|sdr|uhd|fhd|4k|8k|ddp|eac3|ac3|aac|dts|hlg|raw|bd|dv|hq|dl)',
          caseSensitive: false,
        ),
        '',
      )
      .replaceAll(RegExp(r'^[^\w\u4E00-\u9FFF]+|[^\w\u4E00-\u9FFF]+$'), '');
}

bool _isTmdbNoiseToken(String token) {
  final lower = token.toLowerCase();
  const exact = {
    '8k',
    '4k',
    '2160p',
    '1080p',
    '720p',
    '480p',
    'uhd',
    'fhd',
    'hd',
    'sd',
    'hdr',
    'hdr10',
    'sdr',
    'dv',
    'hlg',
    'web',
    'dl',
    'hq',
    'webdl',
    'webrip',
    'bluray',
    'bdrip',
    'remux',
    'raw',
    'hdtv',
    'h265',
    'hevc',
    'x265',
    'h264',
    'x264',
    'avc',
    'av1',
    'vp9',
    '10bit',
    '8bit',
    'aac',
    'ac3',
    'eac3',
    'ddp',
    'dts',
    'p',
  };
  if (exact.contains(lower)) return true;
  if (RegExp(r'^\d{2,3}fps$', caseSensitive: false).hasMatch(token)) {
    return true;
  }
  if (RegExp(r'^0*\d{1,4}$').hasMatch(token)) return true;
  if (RegExp(r'^\d{4}$').hasMatch(token)) return true;
  if (RegExp(r'^全[0-9一二三四五六七八九十百零两]+[集季话]$').hasMatch(token)) {
    return true;
  }
  if (RegExp(r'^第[0-9一二三四五六七八九十百零两]+[集季话]$').hasMatch(token)) {
    return true;
  }
  return token.contains('字幕') ||
      token == '内封' ||
      token == '简繁' ||
      token == '双语';
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
  final episodeToken =
      RegExp(r'(?:^|[^A-Za-z0-9])(?:[Ee][Pp]?)(\d{1,3})(?=$|[^A-Za-z0-9])')
          .firstMatch(title);
  if (episodeToken != null) return int.tryParse(episodeToken.group(1)!);
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
  final parsedGroupPath = normalizedItemGroupPath(item);
  if (parsedGroupPath.isNotEmpty) {
    return normalizeMediaFolderKey(
      '${item.sourceId}:${item.type == SourceType.webdav ? 'webdav' : 'local'}:$parsedGroupPath',
    );
  }
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

String normalizedItemGroupPath(MediaItem item) {
  final value = item.groupPath.trim().replaceAll('\\', '/');
  if (value.isEmpty) return '';
  if (item.type == SourceType.webdav && !value.startsWith('/')) {
    return '/$value';
  }
  return value;
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
  Set<String> separateItemIds = const {},
}) {
  final grouped = <String, List<MediaItem>>{};
  for (final item in items) {
    final key = separateItemIds.contains(item.id)
        ? '${mediaFolderKey(item)}\t${item.id}'
        : mediaFolderKey(item);
    grouped.putIfAbsent(key, () => []).add(item);
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
    final title = groupItems.length == 1
        ? cleanTmdbHints(groupItems.first.title)
        : mediaGroupDisplayTitle(representative);
    groups.add(MediaFolderGroup(
      key: entry.key,
      title: title.isNotEmpty ? title : mediaGroupDisplayTitle(representative),
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

bool itemExplicitlySelectedFile(MediaSourceConfig source, MediaItem item) {
  if (source.id != item.sourceId) return false;
  final path = sourceItemPath(source, item);
  if (path.isEmpty) return false;
  final identity = sourcePathIdentity(source, path, isDir: false);
  return source.selectedPaths.any(
    (selected) =>
        !sourceStoredPathIsDir(source, selected) &&
        sourcePathIdentity(source, selected, isDir: false) == identity,
  );
}

MediaItem singleFileTmdbLookupItem(MediaItem item) {
  return item.copyWith(
    folderTitle: item.title,
    matchTitle: item.title,
  );
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

int resumablePlaybackPositionMs(int positionMs, int durationMs) {
  if (positionMs <= 0) return 0;
  if (durationMs <= 0) return positionMs;
  if (positionMs >= durationMs) return 0;
  if (durationMs - positionMs <= 3000) return 0;
  return positionMs;
}

bool shouldPersistPlaybackProgress({
  required bool ready,
  required bool positionConfirmed,
  required int positionMs,
}) =>
    ready && positionConfirmed && positionMs > 0;

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

String defaultLocalStorageRoot() {
  if (Platform.isAndroid) return '/storage/emulated/0';
  if (Platform.isWindows) return '';
  return '/';
}

String localSourceName(String dir) {
  if (dir == defaultLocalStorageRoot()) return '本地存储';
  final name = p.basename(dir);
  return name.isEmpty ? '本地目录' : name;
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
