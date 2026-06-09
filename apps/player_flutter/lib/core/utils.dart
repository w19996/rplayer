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

String mediaFolderKey(MediaItem item) {
  if (item.type == SourceType.local) {
    return '${item.sourceId}:local:${p.dirname(item.uri)}';
  }
  final uri = Uri.tryParse(item.uri);
  final path = uri == null ? item.uri : Uri.decodeComponent(uri.path);
  return '${item.sourceId}:webdav:${parentPath(path)}';
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
