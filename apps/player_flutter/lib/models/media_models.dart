part of 'package:player_flutter/main.dart';

enum SourceType { local, webdav, openlist }

const mpvAdvancedPresetAuto = 'auto';
const mpvAdvancedPresetPower = 'power';
const mpvAdvancedPresetQuality = 'quality';
const mpvAdvancedPresetCompat = 'compat';
const mpvAdvancedPresetCustom = 'custom';
const mpvAdvancedPresetValues = [
  mpvAdvancedPresetAuto,
  mpvAdvancedPresetPower,
  mpvAdvancedPresetQuality,
  mpvAdvancedPresetCompat,
];

String normalizeMpvAdvancedPreset(Object? value) {
  final text = value is String ? value.trim() : '';
  if (text == mpvAdvancedPresetCustom) return text;
  return mpvAdvancedPresetValues.contains(text) ? text : mpvAdvancedPresetAuto;
}

String mpvAdvancedPresetLabel(String preset) =>
    switch (normalizeMpvAdvancedPreset(preset)) {
      mpvAdvancedPresetPower => '省电优先',
      mpvAdvancedPresetQuality => '画质优先',
      mpvAdvancedPresetCompat => '兼容优先',
      mpvAdvancedPresetCustom => '自定义',
      _ => '自动',
    };

String mpvAdvancedPresetSummary(String preset, {required bool android}) {
  return switch (normalizeMpvAdvancedPreset(preset)) {
    mpvAdvancedPresetPower => '降低缓存和渲染负载，适合发热或切后台卡顿',
    mpvAdvancedPresetQuality => '保留更高缓存和精确 seek，适合性能充足设备',
    mpvAdvancedPresetCompat => '软解回退，适合硬解异常或花屏',
    mpvAdvancedPresetCustom => '已单独调整参数',
    _ => android ? 'Android 使用 fast + MediaCodec 预设' : '当前平台使用默认稳定预设',
  };
}

const mpvAdvancedOptionKeys = [
  'profile',
  'hwdec',
  'hwdec-codecs',
  'vd-lavc-threads',
  'vd-lavc-film-grain',
  'demuxer-max-bytes',
  'demuxer-max-back-bytes',
  'hr-seek',
  'hr-seek-framedrop',
  'video-sync',
  'framedrop',
];

class MpvAdvancedOptionSpec {
  const MpvAdvancedOptionSpec({
    required this.key,
    required this.label,
    required this.description,
    required this.values,
    this.valueLabels = const {},
  });

  final String key;
  final String label;
  final String description;
  final List<String> values;
  final Map<String, String> valueLabels;
}

const mpvAdvancedOptionSpecs = [
  MpvAdvancedOptionSpec(
    key: 'profile',
    label: 'profile',
    description: 'mpv 内置配置档；fast 降低解码和渲染负载，default 保留默认画质策略。',
    values: ['fast', 'default'],
    valueLabels: {'fast': 'fast（低负载）', 'default': 'default（默认画质）'},
  ),
  MpvAdvancedOptionSpec(
    key: 'hwdec',
    label: 'hwdec',
    description: '硬件解码策略；Android 优先 MediaCodec，no 表示强制软解。',
    values: ['mediacodec,mediacodec-copy,no', 'auto-safe', 'no'],
    valueLabels: {
      'mediacodec,mediacodec-copy,no': 'MediaCodec 优先',
      'auto-safe': 'auto-safe',
      'no': 'no（软解）',
    },
  ),
  MpvAdvancedOptionSpec(
    key: 'hwdec-codecs',
    label: 'hwdec-codecs',
    description: '允许硬解的编码范围；all 表示所有支持的编码都尝试硬解。',
    values: ['all'],
  ),
  MpvAdvancedOptionSpec(
    key: 'vd-lavc-threads',
    label: 'vd-lavc-threads',
    description: '软解线程数；0 由解码器自动决定，较小数值可减少后台抢占。',
    values: ['0', '2', '4'],
    valueLabels: {'0': '0（自动）', '2': '2', '4': '4'},
  ),
  MpvAdvancedOptionSpec(
    key: 'vd-lavc-film-grain',
    label: 'vd-lavc-film-grain',
    description: 'AV1 等视频的胶片颗粒重建方式；影响画面细节和解码负载。',
    values: ['cpu', 'auto'],
  ),
  MpvAdvancedOptionSpec(
    key: 'demuxer-max-bytes',
    label: 'demuxer-max-bytes',
    description: '向前读取缓存上限；越大越抗网络波动，也会占更多内存。',
    values: ['33554432', '67108864', '134217728', '268435456'],
    valueLabels: {
      '33554432': '32 MB',
      '67108864': '64 MB',
      '134217728': '128 MB',
      '268435456': '256 MB',
    },
  ),
  MpvAdvancedOptionSpec(
    key: 'demuxer-max-back-bytes',
    label: 'demuxer-max-back-bytes',
    description: '回退缓存上限；越大越方便短距离回看，也会占更多内存。',
    values: ['33554432', '67108864', '134217728', '268435456'],
    valueLabels: {
      '33554432': '32 MB',
      '67108864': '64 MB',
      '134217728': '128 MB',
      '268435456': '256 MB',
    },
  ),
  MpvAdvancedOptionSpec(
    key: 'hr-seek',
    label: 'hr-seek',
    description: '精确 seek；开启后拖动定位更准，但跳转时可能更吃性能。',
    values: ['no', 'yes'],
    valueLabels: {'no': 'no', 'yes': 'yes'},
  ),
  MpvAdvancedOptionSpec(
    key: 'hr-seek-framedrop',
    label: 'hr-seek-framedrop',
    description: '精确 seek 后是否允许丢帧追进度；开启更流畅，关闭更重画质。',
    values: ['yes', 'no'],
    valueLabels: {'yes': 'yes', 'no': 'no'},
  ),
  MpvAdvancedOptionSpec(
    key: 'video-sync',
    label: 'video-sync',
    description: '音视频同步方式；audio 以音频为准，display-resample 更偏显示刷新。',
    values: ['audio', 'display-resample'],
  ),
  MpvAdvancedOptionSpec(
    key: 'framedrop',
    label: 'framedrop',
    description: '卡顿时的丢帧策略；decoder+vo 最积极，no 不主动丢帧。',
    values: ['decoder+vo', 'vo', 'no'],
    valueLabels: {
      'decoder+vo': 'decoder+vo',
      'vo': 'vo',
      'no': 'no',
    },
  ),
];

Map<String, String> mpvAdvancedPresetOptions({
  required String preset,
  required bool android,
}) {
  final value = normalizeMpvAdvancedPreset(preset);
  final compat = value == mpvAdvancedPresetCompat;
  final quality = value == mpvAdvancedPresetQuality;
  final power = value == mpvAdvancedPresetPower;
  final cacheBytes = (power
          ? 32
          : quality
              ? 128
              : 64) *
      1024 *
      1024;
  return {
    'profile': quality || (!android && value == mpvAdvancedPresetAuto)
        ? 'default'
        : 'fast',
    'hwdec': compat
        ? 'no'
        : android
            ? 'mediacodec,mediacodec-copy,no'
            : 'auto-safe',
    'hwdec-codecs': 'all',
    'vd-lavc-threads': compat ? '2' : '0',
    'vd-lavc-film-grain': 'cpu',
    'demuxer-max-bytes': '$cacheBytes',
    'demuxer-max-back-bytes': '$cacheBytes',
    'hr-seek': quality ? 'yes' : 'no',
    'hr-seek-framedrop': quality ? 'no' : 'yes',
    'video-sync': 'audio',
    'framedrop': power || android ? 'decoder+vo' : 'vo',
  };
}

Map<String, String> normalizeMpvAdvancedOptions(
  Object? value, {
  required String preset,
  required bool android,
}) {
  final result = mpvAdvancedPresetOptions(preset: preset, android: android);
  if (value is Map) {
    for (final entry in value.entries) {
      final key = entry.key;
      final option = entry.value;
      if (key is! String || option is! String) continue;
      if (!mpvAdvancedOptionKeys.contains(key)) continue;
      final trimmed = option.trim();
      if (trimmed.isEmpty) continue;
      result[key] = trimmed;
    }
  }
  return result;
}

bool _sameMpvAdvancedOptions(
  Map<String, String> a,
  Map<String, String> b,
) {
  for (final key in mpvAdvancedOptionKeys) {
    if (a[key] != b[key]) return false;
  }
  return true;
}

String mpvAdvancedPresetForOptions(
  Map<String, String> options, {
  required bool android,
}) {
  for (final preset in mpvAdvancedPresetValues) {
    if (_sameMpvAdvancedOptions(
      options,
      mpvAdvancedPresetOptions(preset: preset, android: android),
    )) {
      return preset;
    }
  }
  return mpvAdvancedPresetCustom;
}

Map<String, String> mpvAdvancedOptions({
  required String preset,
  required bool android,
  required bool softwareDecoderFallback,
  Map<String, String>? customOptions,
}) {
  final options = customOptions == null
      ? mpvAdvancedPresetOptions(preset: preset, android: android)
      : normalizeMpvAdvancedOptions(
          customOptions,
          preset: preset,
          android: android,
        );
  if (softwareDecoderFallback) {
    options['hwdec'] = 'no';
    options['vd-lavc-threads'] = '2';
  }
  return options;
}

SourceType sourceTypeFromValue(String value) => switch (value) {
      'webdav' => SourceType.webdav,
      'openlist' => SourceType.openlist,
      _ => SourceType.local,
    };

String sourceTypeValue(SourceType type) => switch (type) {
      SourceType.webdav => 'webdav',
      SourceType.openlist => 'openlist',
      SourceType.local => 'local',
    };

bool isRemoteSourceType(SourceType type) =>
    type == SourceType.webdav || type == SourceType.openlist;

String sourceTypeLabel(SourceType type) => switch (type) {
      SourceType.webdav => 'WebDAV',
      SourceType.openlist => 'OpenList',
      SourceType.local => 'Local',
    };

class MediaSourceConfig {
  const MediaSourceConfig({
    required this.id,
    required this.name,
    required this.type,
    required this.directory,
    this.baseUrl = '',
    this.username = '',
    this.password = '',
    this.otpCode = '',
    this.selectedPaths = const [],
    this.seriesPaths = const [],
  });

  factory MediaSourceConfig.local(
      {required String id, required String name, required String directory}) {
    return MediaSourceConfig(
        id: id, name: name, type: SourceType.local, directory: directory);
  }

  factory MediaSourceConfig.webdav({
    required String id,
    required String name,
    required String baseUrl,
    required String username,
    required String password,
    String otpCode = '',
    required String directory,
    List<String> selectedPaths = const [],
    List<String> seriesPaths = const [],
  }) {
    return MediaSourceConfig(
      id: id,
      name: name,
      type: SourceType.webdav,
      baseUrl: baseUrl,
      username: username,
      password: password,
      otpCode: otpCode,
      directory: directory,
      selectedPaths: selectedPaths,
      seriesPaths: seriesPaths,
    );
  }

  factory MediaSourceConfig.openlist({
    required String id,
    required String name,
    required String baseUrl,
    required String username,
    required String password,
    String otpCode = '',
    required String directory,
    List<String> selectedPaths = const [],
    List<String> seriesPaths = const [],
  }) {
    return MediaSourceConfig(
      id: id,
      name: name,
      type: SourceType.openlist,
      baseUrl: baseUrl,
      username: username,
      password: password,
      otpCode: otpCode,
      directory: directory,
      selectedPaths: selectedPaths,
      seriesPaths: seriesPaths,
    );
  }

  final String id;
  final String name;
  final SourceType type;
  final String directory;
  final String baseUrl;
  final String username;
  final String password;
  final String otpCode;
  final List<String> selectedPaths;
  final List<String> seriesPaths;

  String get displayPath => type == SourceType.local
      ? (directory.isEmpty ? '此电脑' : directory)
      : '$baseUrl$directory';

  Map<String, String> get headers {
    if (type != SourceType.webdav) return {};
    if (username.isEmpty && password.isEmpty) return {};
    return {
      'Authorization':
          'Basic ${base64Encode(utf8.encode('$username:$password'))}'
    };
  }

  Uri resolve(String remotePath) {
    final base = baseUrl.endsWith('/') ? baseUrl : '$baseUrl/';
    final relative =
        remotePath.startsWith('/') ? remotePath.substring(1) : remotePath;
    return Uri.parse(base)
        .resolve(relative.split('/').map(Uri.encodeComponent).join('/'));
  }

  MediaSourceConfig copyWith({
    String? id,
    String? name,
    SourceType? type,
    String? directory,
    String? baseUrl,
    String? username,
    String? password,
    String? otpCode,
    List<String>? selectedPaths,
    List<String>? seriesPaths,
  }) {
    return MediaSourceConfig(
      id: id ?? this.id,
      name: name ?? this.name,
      type: type ?? this.type,
      directory: directory ?? this.directory,
      baseUrl: baseUrl ?? this.baseUrl,
      username: username ?? this.username,
      password: password ?? this.password,
      otpCode: otpCode ?? this.otpCode,
      selectedPaths: selectedPaths ?? this.selectedPaths,
      seriesPaths: seriesPaths ?? this.seriesPaths,
    );
  }

  factory MediaSourceConfig.fromJson(Map<String, dynamic> json) =>
      MediaSourceConfig(
        id: json['id'] as String,
        name: json['name'] as String,
        type: sourceTypeFromValue(json['type'] as String? ?? 'local'),
        directory: json['directory'] as String,
        baseUrl: json['baseUrl'] as String? ?? '',
        username: json['username'] as String? ?? '',
        password: json['password'] as String? ?? '',
        otpCode: json['otpCode'] as String? ?? '',
        selectedPaths: (json['selectedPaths'] as List<dynamic>? ?? const [])
            .whereType<String>()
            .toList(),
        seriesPaths: (json['seriesPaths'] as List<dynamic>? ?? const [])
            .whereType<String>()
            .toList(),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'type': sourceTypeValue(type),
        'directory': directory,
        'baseUrl': baseUrl,
        'username': username,
        'password': password,
        'otpCode': otpCode,
        'selectedPaths': selectedPaths,
        'seriesPaths': seriesPaths,
      };
}

class MediaItem {
  const MediaItem({
    required this.id,
    required this.sourceId,
    required this.sourceName,
    required this.type,
    required this.title,
    required this.uri,
    this.folderTitle = '',
    this.matchTitle = '',
    this.matchYear,
    this.season,
    this.episode,
    this.mediaKind = 'Unknown',
    this.groupPath = '',
    this.versionName = '',
    this.versionDirPath = '',
    this.manualSeries = false,
    this.size,
  });

  factory MediaItem.local(
      {required MediaSourceConfig source, required String path, int? size}) {
    final title = p.basenameWithoutExtension(path);
    final candidate = RustCoreService.instance
        .tryParseMediaPathCandidate(SourceType.local, path);
    final folderTitle = candidate?.title ?? mediaSeriesTitleFromLocalPath(path);
    return MediaItem(
      id: '${source.id}:$path',
      sourceId: source.id,
      sourceName: source.name,
      type: SourceType.local,
      title: title,
      uri: path,
      folderTitle: folderTitle,
      matchTitle: candidate?.title ?? title,
      matchYear: candidate?.year,
      season: candidate?.seasonNumber,
      episode: candidate?.episodeNumber,
      mediaKind: candidate?.mediaTypeHint == 'tv'
          ? 'TvEpisode'
          : candidate?.mediaTypeHint == 'movie'
              ? 'Movie'
              : 'Unknown',
      groupPath: candidate?.sourcePath ?? '',
      versionName: candidate?.versionName ?? '',
      versionDirPath: candidate?.versionDirPath ?? '',
      size: size,
    );
  }

  factory MediaItem.webdav(
      {required MediaSourceConfig source, required WebdavEntry entry}) {
    return MediaItem.remote(source: source, entry: entry);
  }

  factory MediaItem.remote(
      {required MediaSourceConfig source, required WebdavEntry entry}) {
    final title = p.basenameWithoutExtension(entry.name);
    final candidate = RustCoreService.instance
        .tryParseMediaPathCandidate(SourceType.webdav, entry.path);
    final folderTitle =
        candidate?.title ?? mediaSeriesTitleFromRemotePath(entry.path);
    return MediaItem(
      id: '${source.id}:${entry.path}',
      sourceId: source.id,
      sourceName: source.name,
      type: source.type,
      title: title,
      uri: source.type == SourceType.openlist ? entry.path : entry.url,
      folderTitle: folderTitle,
      matchTitle: candidate?.title ?? title,
      matchYear: candidate?.year,
      season: candidate?.seasonNumber,
      episode: candidate?.episodeNumber,
      mediaKind: candidate?.mediaTypeHint == 'tv'
          ? 'TvEpisode'
          : candidate?.mediaTypeHint == 'movie'
              ? 'Movie'
              : 'Unknown',
      groupPath: candidate?.sourcePath ?? '',
      versionName: candidate?.versionName ?? '',
      versionDirPath: candidate?.versionDirPath ?? '',
      size: entry.size,
    );
  }

  final String id;
  final String sourceId;
  final String sourceName;
  final SourceType type;
  final String title;
  final String uri;
  final String folderTitle;
  final String matchTitle;
  final int? matchYear;
  final int? season;
  final int? episode;
  final String mediaKind;
  final String groupPath;
  final String versionName;
  final String versionDirPath;
  final bool manualSeries;
  final int? size;

  MediaItem copyWith({
    String? id,
    String? sourceId,
    String? sourceName,
    SourceType? type,
    String? title,
    String? uri,
    String? folderTitle,
    String? matchTitle,
    int? matchYear,
    int? season,
    int? episode,
    String? mediaKind,
    String? groupPath,
    String? versionName,
    String? versionDirPath,
    bool? manualSeries,
    int? size,
  }) {
    return MediaItem(
      id: id ?? this.id,
      sourceId: sourceId ?? this.sourceId,
      sourceName: sourceName ?? this.sourceName,
      type: type ?? this.type,
      title: title ?? this.title,
      uri: uri ?? this.uri,
      folderTitle: folderTitle ?? this.folderTitle,
      matchTitle: matchTitle ?? this.matchTitle,
      matchYear: matchYear ?? this.matchYear,
      season: season ?? this.season,
      episode: episode ?? this.episode,
      mediaKind: mediaKind ?? this.mediaKind,
      groupPath: groupPath ?? this.groupPath,
      versionName: versionName ?? this.versionName,
      versionDirPath: versionDirPath ?? this.versionDirPath,
      manualSeries: manualSeries ?? this.manualSeries,
      size: size ?? this.size,
    );
  }

  factory MediaItem.fromJson(Map<String, dynamic> json) => MediaItem(
        id: json['id'] as String,
        sourceId: json['sourceId'] as String,
        sourceName: json['sourceName'] as String,
        type: sourceTypeFromValue(json['type'] as String? ?? 'local'),
        title: json['title'] as String,
        uri: json['uri'] as String,
        folderTitle: json['folderTitle'] as String? ?? '',
        matchTitle: json['matchTitle'] as String? ?? json['title'] as String,
        matchYear: (json['matchYear'] as num?)?.toInt(),
        season: (json['season'] as num?)?.toInt(),
        episode: (json['episode'] as num?)?.toInt(),
        mediaKind: json['mediaKind'] as String? ?? 'Unknown',
        groupPath: json['groupPath'] as String? ?? '',
        versionName: json['versionName'] as String? ?? '',
        versionDirPath: json['versionDirPath'] as String? ?? '',
        manualSeries: json['manualSeries'] as bool? ?? false,
        size: (json['size'] as num?)?.toInt(),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'sourceId': sourceId,
        'sourceName': sourceName,
        'type': sourceTypeValue(type),
        'title': title,
        'uri': uri,
        'folderTitle': folderTitle,
        'matchTitle': matchTitle,
        'matchYear': matchYear,
        'season': season,
        'episode': episode,
        'mediaKind': mediaKind,
        'groupPath': groupPath,
        'versionName': versionName,
        'versionDirPath': versionDirPath,
        'manualSeries': manualSeries,
        'size': size,
      };
}

class MediaFolderGroup {
  const MediaFolderGroup({
    required this.key,
    required this.title,
    required this.items,
    required this.representative,
    required this.latestPlayedAt,
  });

  final String key;
  final String title;
  final List<MediaItem> items;
  final MediaItem representative;
  final int latestPlayedAt;
}

class TmdbApiEndpoint {
  const TmdbApiEndpoint({
    required this.label,
    required this.url,
    this.custom = false,
  });

  final String label;
  final String url;
  final bool custom;
}

const defaultTmdbApiBaseUrl = 'https://api.tmdb.org/3';
const tmdbProxyEndpointValue = 'custom:tmdb-proxy';

const tmdbApiEndpoints = [
  TmdbApiEndpoint(label: 'api.tmdb.org', url: defaultTmdbApiBaseUrl),
  TmdbApiEndpoint(
    label: 'api.themoviedb.org',
    url: 'https://api.themoviedb.org/3',
  ),
  TmdbApiEndpoint(
    label: '自建 tmdb-proxy',
    url: tmdbProxyEndpointValue,
    custom: true,
  ),
];

String normalizeTmdbApiBaseUrl(String value) {
  final trimmed = value.trim();
  var normalized = trimmed.endsWith('/')
      ? trimmed.substring(0, trimmed.length - 1)
      : trimmed;
  if (normalized.isEmpty) return defaultTmdbApiBaseUrl;
  if (!normalized.startsWith('http://') && !normalized.startsWith('https://')) {
    normalized = 'https://$normalized';
  }
  final official = tmdbApiEndpoints
      .where((endpoint) => !endpoint.custom)
      .map((endpoint) => endpoint.url)
      .contains(normalized);
  if (official) return normalized;
  final uri = Uri.tryParse(normalized);
  if (uri == null || uri.host.isEmpty) return defaultTmdbApiBaseUrl;
  final path = uri.path.endsWith('/')
      ? uri.path.substring(0, uri.path.length - 1)
      : uri.path;
  if (path.isEmpty) {
    return _tmdbUriWithPath(uri, '/3');
  }
  return _tmdbUriWithPath(uri, path);
}

bool isOfficialTmdbApiBaseUrl(String value) {
  final normalized = normalizeTmdbApiBaseUrl(value);
  return tmdbApiEndpoints
      .where((endpoint) => !endpoint.custom)
      .any((endpoint) => endpoint.url == normalized);
}

String selectedTmdbEndpointValue(String value) {
  final normalized = normalizeTmdbApiBaseUrl(value);
  return isOfficialTmdbApiBaseUrl(normalized)
      ? normalized
      : tmdbProxyEndpointValue;
}

String tmdbProxyDisplayBaseUrl(String value) {
  final normalized = normalizeTmdbApiBaseUrl(value);
  if (isOfficialTmdbApiBaseUrl(normalized)) return '';
  return normalized.endsWith('/3')
      ? normalized.substring(0, normalized.length - 2)
      : normalized;
}

String tmdbImageBaseUrlForApiBaseUrl(String value) {
  final normalized = normalizeTmdbApiBaseUrl(value);
  if (isOfficialTmdbApiBaseUrl(normalized)) {
    return 'https://image.tmdb.org/t/p';
  }
  final uri = Uri.parse(normalized);
  return _tmdbUriWithPath(uri, '/t/p');
}

String _tmdbUriWithPath(Uri uri, String path) {
  return Uri(
    scheme: uri.scheme,
    userInfo: uri.userInfo,
    host: uri.host,
    port: uri.hasPort ? uri.port : null,
    path: path,
  ).toString();
}

String tmdbEndpointLabel(String value) {
  final selected = selectedTmdbEndpointValue(value);
  return tmdbApiEndpoints
      .firstWhere((endpoint) => endpoint.url == selected)
      .label;
}

String tmdbEndpointHost(String value) {
  final normalized = normalizeTmdbApiBaseUrl(value);
  return Uri.parse(normalized).host;
}

String selectedTmdbApiBaseUrl(String value) {
  final normalized = normalizeTmdbApiBaseUrl(value);
  return normalized;
}

class TmdbConfig {
  const TmdbConfig({
    this.accessToken = '',
    this.language = 'zh-CN',
    this.region = 'CN',
    this.apiBaseUrl = defaultTmdbApiBaseUrl,
  });

  final String accessToken;
  final String language;
  final String region;
  final String apiBaseUrl;

  bool get enabled => accessToken.trim().isNotEmpty;
  String get normalizedApiBaseUrl => normalizeTmdbApiBaseUrl(apiBaseUrl);
  String get imageBaseUrl =>
      tmdbImageBaseUrlForApiBaseUrl(normalizedApiBaseUrl);

  TmdbConfig copyWith({
    String? accessToken,
    String? language,
    String? region,
    String? apiBaseUrl,
  }) {
    return TmdbConfig(
      accessToken: accessToken ?? this.accessToken,
      language: language ?? this.language,
      region: region ?? this.region,
      apiBaseUrl: normalizeTmdbApiBaseUrl(apiBaseUrl ?? this.apiBaseUrl),
    );
  }

  factory TmdbConfig.fromJson(Map<String, dynamic> json) => TmdbConfig(
        accessToken: json['accessToken'] as String? ?? '',
        language: json['language'] as String? ?? 'zh-CN',
        region: json['region'] as String? ?? 'CN',
        apiBaseUrl: selectedTmdbApiBaseUrl(json['apiBaseUrl'] as String? ?? ''),
      );

  Map<String, dynamic> toJson() => {
        'accessToken': accessToken,
        'language': language,
        'region': region,
        'apiBaseUrl': normalizedApiBaseUrl,
      };
}

class DanmuConfig {
  const DanmuConfig({
    this.enabled = false,
    this.apiBaseUrl = '',
    this.apiToken = '',
    this.visible = true,
    this.fontSize = 18,
    this.opacity = 0.92,
    this.speed = 1,
    this.offsetMs = 0,
    this.maxLines = 8,
    this.topPadding = 24,
  });

  final bool enabled;
  final String apiBaseUrl;
  final String apiToken;
  final bool visible;
  final double fontSize;
  final double opacity;
  final double speed;
  final int offsetMs;
  final int maxLines;
  final double topPadding;

  String get normalizedApiBaseUrl => normalizeDanmuApiBaseUrl(apiBaseUrl);
  String get normalizedApiToken => normalizeDanmuApiToken(apiToken);
  String get requestBaseUrl =>
      buildDanmuRequestBaseUrl(normalizedApiBaseUrl, normalizedApiToken);
  bool get available => enabled && requestBaseUrl.isNotEmpty;

  DanmuConfig copyWith({
    bool? enabled,
    String? apiBaseUrl,
    String? apiToken,
    bool? visible,
    double? fontSize,
    double? opacity,
    double? speed,
    int? offsetMs,
    int? maxLines,
    double? topPadding,
  }) {
    final endpoint = _normalizeDanmuEndpointParts(
      apiBaseUrl ?? this.apiBaseUrl,
      apiToken ?? this.apiToken,
    );
    return DanmuConfig(
      enabled: enabled ?? this.enabled,
      apiBaseUrl: endpoint.apiBaseUrl,
      apiToken: endpoint.apiToken,
      visible: visible ?? this.visible,
      fontSize: fontSize ?? this.fontSize,
      opacity: opacity ?? this.opacity,
      speed: speed ?? this.speed,
      offsetMs: offsetMs ?? this.offsetMs,
      maxLines: maxLines ?? this.maxLines,
      topPadding: topPadding ?? this.topPadding,
    );
  }

  factory DanmuConfig.fromJson(Map<String, dynamic> json) {
    final endpoint = _normalizeDanmuEndpointParts(
      json['apiBaseUrl'] as String? ?? '',
      json['apiToken'] as String? ?? '',
    );
    return DanmuConfig(
      enabled: json['enabled'] as bool? ?? false,
      apiBaseUrl: endpoint.apiBaseUrl,
      apiToken: endpoint.apiToken,
      visible: json['visible'] as bool? ?? true,
      fontSize: (json['fontSize'] as num?)?.toDouble() ?? 18,
      opacity: (json['opacity'] as num?)?.toDouble() ?? 0.92,
      speed: (json['speed'] as num?)?.toDouble() ?? 1,
      offsetMs: (json['offsetMs'] as num?)?.toInt() ?? 0,
      maxLines: (json['maxLines'] as num?)?.toInt() ?? 8,
      topPadding: (json['topPadding'] as num?)?.toDouble() ?? 24,
    );
  }

  Map<String, dynamic> toJson() => {
        'enabled': enabled,
        'apiBaseUrl': normalizedApiBaseUrl,
        'apiToken': normalizedApiToken,
        'visible': visible,
        'fontSize': fontSize,
        'opacity': opacity,
        'speed': speed,
        'offsetMs': offsetMs,
        'maxLines': maxLines,
        'topPadding': topPadding,
      };
}

String normalizeDanmuApiBaseUrl(String value) =>
    _normalizeDanmuEndpointParts(value, '').apiBaseUrl;

String normalizeDanmuApiToken(String value) => value.trim().replaceAll('/', '');

String buildDanmuRequestBaseUrl(String apiBaseUrl, String apiToken) {
  final base = normalizeDanmuApiBaseUrl(apiBaseUrl);
  if (base.isEmpty) return '';
  final token = normalizeDanmuApiToken(apiToken);
  if (token.isEmpty || token == '87654321') return base;
  final uri = Uri.tryParse(base);
  if (uri == null) return base;
  final segments = uri.pathSegments.where((part) => part.isNotEmpty).toList();
  if (segments.isNotEmpty && segments.last == token) return base;
  return Uri(
    scheme: uri.scheme,
    userInfo: uri.userInfo,
    host: uri.host,
    port: uri.hasPort ? uri.port : null,
    pathSegments: [...segments, token],
  ).toString().replaceFirst(RegExp(r'/$'), '');
}

_DanmuEndpointParts _normalizeDanmuEndpointParts(
  String apiBaseUrl,
  String apiToken,
) {
  var normalized = apiBaseUrl.trim();
  while (normalized.endsWith('/')) {
    normalized = normalized.substring(0, normalized.length - 1);
  }
  final tokenFromField = normalizeDanmuApiToken(apiToken);
  if (normalized.isEmpty) {
    return _DanmuEndpointParts('', tokenFromField);
  }
  if (!normalized.startsWith('http://') && !normalized.startsWith('https://')) {
    normalized = 'https://$normalized';
  }
  final uri = Uri.tryParse(normalized);
  if (uri == null || uri.host.isEmpty) {
    return _DanmuEndpointParts('', tokenFromField);
  }
  final segments = uri.pathSegments.where((part) => part.isNotEmpty).toList();
  if (segments.length >= 2 &&
      segments[segments.length - 2] == 'api' &&
      segments.last == 'v2') {
    segments.removeLast();
    segments.removeLast();
  }
  var token = tokenFromField;
  if (segments.isNotEmpty &&
      (token.isEmpty || segments.last == token) &&
      !_danmuKnownPathSegments.contains(segments.last)) {
    token = segments.removeLast();
  }
  final baseUrl = Uri(
    scheme: uri.scheme,
    userInfo: uri.userInfo,
    host: uri.host,
    port: uri.hasPort ? uri.port : null,
    pathSegments: segments,
  ).toString().replaceFirst(RegExp(r'/$'), '');
  return _DanmuEndpointParts(baseUrl, token);
}

const _danmuKnownPathSegments = {
  'api',
  'v1',
  'v2',
  'search',
  'match',
  'bangumi',
  'comment',
  'danmaku',
};

class _DanmuEndpointParts {
  const _DanmuEndpointParts(this.apiBaseUrl, this.apiToken);

  final String apiBaseUrl;
  final String apiToken;
}

class MediaMetadata {
  const MediaMetadata({
    required this.itemId,
    required this.tmdbId,
    required this.mediaType,
    required this.title,
    this.tmdbType,
    this.originalTitle,
    this.overview,
    this.posterPath,
    this.backdropPath,
    this.stillPath,
    this.logoPath,
    this.profilePaths = const [],
    this.castNames = const [],
    this.genres = const [],
    this.releaseDate,
    this.voteAverage,
    this.totalSeasons,
    this.totalEpisodes,
    this.showSeasons = const [],
    this.seasonTmdbId,
    this.seasonName,
    this.seasonOverview,
    this.seasonAirDate,
    this.seasonEpisodeCount,
    this.seasonPosterPath,
    this.seasonEpisodes = const [],
    this.episodeTmdbId,
    this.episodeName,
    this.episodeOverview,
    this.episodeRuntime,
    this.episodeType,
    this.episodeVoteCount,
    this.updatedAt,
    this.schemaVersion = 0,
  });

  final String itemId;
  final int tmdbId;
  final String mediaType;
  final String title;
  final String? tmdbType;
  final String? originalTitle;
  final String? overview;
  final String? posterPath;
  final String? backdropPath;
  final String? stillPath;
  final String? logoPath;
  final List<String> profilePaths;
  final List<String> castNames;
  final List<String> genres;
  final String? releaseDate;
  final double? voteAverage;
  final int? totalSeasons;
  final int? totalEpisodes;
  final List<Map<String, dynamic>> showSeasons;
  final int? seasonTmdbId;
  final String? seasonName;
  final String? seasonOverview;
  final String? seasonAirDate;
  final int? seasonEpisodeCount;
  final String? seasonPosterPath;
  final List<Map<String, dynamic>> seasonEpisodes;
  final int? episodeTmdbId;
  final String? episodeName;
  final String? episodeOverview;
  final int? episodeRuntime;
  final String? episodeType;
  final int? episodeVoteCount;
  final int? updatedAt;
  final int schemaVersion;

  String? get posterUrl => tmdbImageUrl(posterPath, 'w500');
  String? get backdropUrl => tmdbImageUrl(backdropPath, 'w780');
  String? get stillUrl => tmdbImageUrl(stillPath, 'w780');
  String? get logoUrl => tmdbImageUrl(logoPath, 'w300');
  List<String> get profileUrls =>
      profilePaths.map((path) => tmdbImageUrl(path, 'w185')).nonNulls.toList();

  factory MediaMetadata.fromJson(Map<String, dynamic> json) => MediaMetadata(
        itemId: json['itemId'] as String,
        tmdbId: (json['tmdbId'] as num).toInt(),
        mediaType: json['mediaType'] as String? ?? 'movie',
        title: json['title'] as String? ?? '',
        tmdbType: json['tmdbType'] as String?,
        originalTitle: json['originalTitle'] as String?,
        overview: json['overview'] as String?,
        posterPath: json['posterPath'] as String?,
        backdropPath: json['backdropPath'] as String?,
        stillPath: json['stillPath'] as String?,
        logoPath: json['logoPath'] as String?,
        profilePaths: (json['profilePaths'] as List<dynamic>? ?? const [])
            .whereType<String>()
            .toList(),
        castNames: (json['castNames'] as List<dynamic>? ?? const [])
            .whereType<String>()
            .toList(),
        genres: (json['genres'] as List<dynamic>? ?? const [])
            .whereType<String>()
            .toList(),
        releaseDate: json['releaseDate'] as String?,
        voteAverage: (json['voteAverage'] as num?)?.toDouble(),
        totalSeasons: (json['totalSeasons'] as num?)?.toInt(),
        totalEpisodes: (json['totalEpisodes'] as num?)?.toInt(),
        showSeasons: (json['showSeasons'] as List<dynamic>? ?? const [])
            .whereType<Map>()
            .map((entry) => Map<String, dynamic>.from(entry))
            .toList(),
        seasonTmdbId: (json['seasonTmdbId'] as num?)?.toInt(),
        seasonName: json['seasonName'] as String?,
        seasonOverview: json['seasonOverview'] as String?,
        seasonAirDate: json['seasonAirDate'] as String?,
        seasonEpisodeCount: (json['seasonEpisodeCount'] as num?)?.toInt(),
        seasonPosterPath: json['seasonPosterPath'] as String?,
        seasonEpisodes: (json['seasonEpisodes'] as List<dynamic>? ?? const [])
            .whereType<Map>()
            .map((entry) => Map<String, dynamic>.from(entry))
            .toList(),
        episodeTmdbId: (json['episodeTmdbId'] as num?)?.toInt(),
        episodeName: json['episodeName'] as String?,
        episodeOverview: json['episodeOverview'] as String?,
        episodeRuntime: (json['episodeRuntime'] as num?)?.toInt(),
        episodeType: json['episodeType'] as String?,
        episodeVoteCount: (json['episodeVoteCount'] as num?)?.toInt(),
        updatedAt: (json['updatedAt'] as num?)?.toInt(),
        schemaVersion: (json['schemaVersion'] as num?)?.toInt() ?? 0,
      );

  Map<String, dynamic> toJson() => {
        'itemId': itemId,
        'tmdbId': tmdbId,
        'mediaType': mediaType,
        'title': title,
        'tmdbType': tmdbType,
        'originalTitle': originalTitle,
        'overview': overview,
        'posterPath': posterPath,
        'backdropPath': backdropPath,
        'stillPath': stillPath,
        'logoPath': logoPath,
        'profilePaths': profilePaths,
        'castNames': castNames,
        'genres': genres,
        'releaseDate': releaseDate,
        'voteAverage': voteAverage,
        'totalSeasons': totalSeasons,
        'totalEpisodes': totalEpisodes,
        'showSeasons': showSeasons,
        'seasonTmdbId': seasonTmdbId,
        'seasonName': seasonName,
        'seasonOverview': seasonOverview,
        'seasonAirDate': seasonAirDate,
        'seasonEpisodeCount': seasonEpisodeCount,
        'seasonPosterPath': seasonPosterPath,
        'seasonEpisodes': seasonEpisodes,
        'episodeTmdbId': episodeTmdbId,
        'episodeName': episodeName,
        'episodeOverview': episodeOverview,
        'episodeRuntime': episodeRuntime,
        'episodeType': episodeType,
        'episodeVoteCount': episodeVoteCount,
        'updatedAt': updatedAt,
        'schemaVersion': schemaVersion,
      };
}

class TmdbSearchCandidate {
  const TmdbSearchCandidate({
    required this.tmdbId,
    required this.mediaType,
    required this.title,
    this.originalTitle,
    this.overview,
    this.posterPath,
    this.backdropPath,
    this.releaseDate,
    this.tmdbType,
    this.genres = const [],
    this.originCountry = const [],
    this.voteAverage,
    this.popularity,
  });

  final int tmdbId;
  final String mediaType;
  final String title;
  final String? originalTitle;
  final String? overview;
  final String? posterPath;
  final String? backdropPath;
  final String? releaseDate;
  final String? tmdbType;
  final List<String> genres;
  final List<String> originCountry;
  final double? voteAverage;
  final double? popularity;

  bool get isTv => mediaType == 'tv';
  String get mediaTypeLabel => mediaCategoryLabel(mediaCategoryKey(
        mediaType: mediaType,
        tmdbType: tmdbType,
        genres: genres,
      ));

  String get displayDate =>
      releaseDate?.trim().isNotEmpty == true ? releaseDate! : '日期未知';
  String get displayCountry =>
      originCountry.isEmpty ? '地区未知' : originCountry.join(' / ');

  factory TmdbSearchCandidate.fromSearchJson(
    Map<String, dynamic> json, {
    required String mediaType,
    String? tmdbType,
    List<String> genres = const [],
  }) {
    final title =
        mediaType == 'tv' ? json['name'] as String? : json['title'] as String?;
    final originalTitle = mediaType == 'tv'
        ? json['original_name'] as String?
        : json['original_title'] as String?;
    final date = mediaType == 'tv'
        ? json['first_air_date'] as String?
        : json['release_date'] as String?;
    return TmdbSearchCandidate(
      tmdbId: (json['id'] as num?)?.toInt() ?? 0,
      mediaType: mediaType,
      title: title?.trim().isNotEmpty == true
          ? title!.trim()
          : originalTitle?.trim() ?? '',
      originalTitle: originalTitle,
      overview: json['overview'] as String?,
      posterPath: json['poster_path'] as String?,
      backdropPath: json['backdrop_path'] as String?,
      releaseDate: date,
      tmdbType: tmdbType,
      genres: genres,
      originCountry: (json['origin_country'] as List<dynamic>? ?? const [])
          .whereType<String>()
          .toList(),
      voteAverage: (json['vote_average'] as num?)?.toDouble(),
      popularity: (json['popularity'] as num?)?.toDouble(),
    );
  }
}

bool mediaGenresContainAnimation(Iterable<String> genres) {
  return genres.any((genre) {
    final normalized = genre.trim().toLowerCase();
    return normalized == 'animation' ||
        normalized == '动画' ||
        normalized == '動漫' ||
        normalized == 'anime';
  });
}

String mediaCategoryKey({
  required String? mediaType,
  String? tmdbType,
  Iterable<String> genres = const [],
}) {
  if (mediaGenresContainAnimation(genres)) return 'anime';
  final normalizedMediaType = mediaType?.trim().toLowerCase();
  if (normalizedMediaType == 'movie') return 'movie';
  if (normalizedMediaType != 'tv') {
    return normalizedMediaType?.isNotEmpty == true
        ? normalizedMediaType!
        : 'tv';
  }
  return switch (tmdbType?.trim().toLowerCase()) {
    'reality' => 'variety',
    'talk show' => 'talk',
    'documentary' => 'documentary',
    'news' => 'news',
    'video' => 'other',
    _ => 'tv',
  };
}

String mediaCategoryLabel(String key) {
  return switch (key) {
    'anime' => '动漫',
    'tv' => '电视剧',
    'variety' => '综艺',
    'talk' => '访谈',
    'documentary' => '纪录片',
    'news' => '新闻',
    'movie' => '电影',
    'other' => '其他',
    _ => key.toUpperCase(),
  };
}

class LibraryHomeEntry {
  const LibraryHomeEntry({
    required this.folderId,
    required this.sourceId,
    required this.folderPath,
    this.itemId,
    required this.showId,
    required this.tmdbId,
    required this.title,
    this.overview,
    this.posterPath,
    this.backdropPath,
    this.voteAverage,
    this.releaseDate,
    this.totalEpisodes,
    required this.localFileCount,
    this.latestPlayedAt,
    this.matched = false,
    this.mediaType,
    this.tmdbType,
    this.genres = const [],
  });

  final int folderId;
  final String sourceId;
  final String folderPath;
  final String? itemId;
  final int showId;
  final int tmdbId;
  final String title;
  final String? overview;
  final String? posterPath;
  final String? backdropPath;
  final double? voteAverage;
  final String? releaseDate;
  final int? totalEpisodes;
  final int localFileCount;
  final int? latestPlayedAt;
  final bool matched;
  final String? mediaType;
  final String? tmdbType;
  final List<String> genres;

  factory LibraryHomeEntry.fromJson(Map<String, dynamic> json) {
    return LibraryHomeEntry(
      folderId: (json['folderId'] as num?)?.toInt() ?? 0,
      sourceId: json['sourceId'] as String? ?? '',
      folderPath: json['folderPath'] as String? ?? '',
      itemId: json['itemId'] as String?,
      showId: (json['showId'] as num?)?.toInt() ?? 0,
      tmdbId: (json['tmdbId'] as num?)?.toInt() ?? 0,
      title: json['title'] as String? ?? '',
      overview: json['overview'] as String?,
      posterPath: json['posterPath'] as String?,
      backdropPath: json['backdropPath'] as String?,
      voteAverage: (json['voteAverage'] as num?)?.toDouble(),
      releaseDate: json['releaseDate'] as String?,
      totalEpisodes: (json['totalEpisodes'] as num?)?.toInt(),
      localFileCount: (json['localFileCount'] as num?)?.toInt() ?? 0,
      latestPlayedAt: (json['latestPlayedAt'] as num?)?.toInt(),
      matched: json['matched'] == true,
      mediaType: json['mediaType'] as String?,
      tmdbType: json['tmdbType'] as String?,
      genres: (json['genres'] as List<dynamic>? ?? const [])
          .whereType<String>()
          .toList(),
    );
  }

  String get folderKey => '$sourceId:db:$folderPath';
}

class LibraryShowDetail {
  const LibraryShowDetail({
    required this.folderKey,
    this.genres = const [],
    this.castNames = const [],
    this.profilePaths = const [],
    required this.files,
  });

  final String folderKey;
  final List<String> genres;
  final List<String> castNames;
  final List<String?> profilePaths;
  final List<LibraryFileEntry> files;

  LibraryFileEntry? get currentFile {
    final played = files.where((file) => (file.lastPlayedAt ?? 0) > 0).toList()
      ..sort((a, b) => (b.lastPlayedAt ?? 0).compareTo(a.lastPlayedAt ?? 0));
    if (played.isNotEmpty) return played.first;
    final progress = files.where((file) => (file.positionMs ?? 0) > 0).toList()
      ..sort((a, b) => (b.positionMs ?? 0).compareTo(a.positionMs ?? 0));
    if (progress.isNotEmpty) return progress.first;
    return files.firstOrNull;
  }

  LibraryFileEntry? get representative => currentFile ?? files.firstOrNull;

  factory LibraryShowDetail.fromJson(Map<String, dynamic> json) {
    return LibraryShowDetail(
      folderKey: json['folderKey'] as String? ?? '',
      genres: (json['genres'] as List<dynamic>? ?? const [])
          .whereType<String>()
          .toList(),
      castNames: (json['castNames'] as List<dynamic>? ?? const [])
          .whereType<String>()
          .toList(),
      profilePaths: (json['profilePaths'] as List<dynamic>? ?? const [])
          .map((value) => value is String ? value : null)
          .toList(),
      files: (json['files'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(LibraryFileEntry.fromJson)
          .toList(),
    );
  }
}

class LibraryFileEntry {
  const LibraryFileEntry({
    required this.fileId,
    required this.itemId,
    required this.relativePath,
    required this.filename,
    this.size,
    this.guessSeason,
    this.guessEpisode,
    this.positionMs,
    this.durationMs,
    this.lastPlayedAt,
    this.showId,
    this.tmdbId,
    this.showTitle,
    this.originalTitle,
    this.showOverview,
    this.posterPath,
    this.backdropPath,
    this.logoPath,
    this.voteAverage,
    this.releaseDate,
    this.totalSeasons,
    this.totalEpisodes,
    this.episodeId,
    this.seasonNumber,
    this.episodeNumber,
    this.episodeName,
    this.episodeOverview,
    this.episodeAirDate,
    this.runtime,
    this.stillPath,
    this.versionName,
    this.versionDirPath,
  });

  final int fileId;
  final String itemId;
  final String relativePath;
  final String filename;
  final int? size;
  final int? guessSeason;
  final int? guessEpisode;
  final int? positionMs;
  final int? durationMs;
  final int? lastPlayedAt;
  final int? showId;
  final int? tmdbId;
  final String? showTitle;
  final String? originalTitle;
  final String? showOverview;
  final String? posterPath;
  final String? backdropPath;
  final String? logoPath;
  final double? voteAverage;
  final String? releaseDate;
  final int? totalSeasons;
  final int? totalEpisodes;
  final int? episodeId;
  final int? seasonNumber;
  final int? episodeNumber;
  final String? episodeName;
  final String? episodeOverview;
  final String? episodeAirDate;
  final int? runtime;
  final String? stillPath;
  final String? versionName;
  final String? versionDirPath;

  factory LibraryFileEntry.fromJson(Map<String, dynamic> json) {
    return LibraryFileEntry(
      fileId: (json['fileId'] as num?)?.toInt() ?? 0,
      itemId: json['itemId'] as String? ?? '',
      relativePath: json['relativePath'] as String? ?? '',
      filename: json['filename'] as String? ?? '',
      size: (json['size'] as num?)?.toInt(),
      guessSeason: (json['guessSeason'] as num?)?.toInt(),
      guessEpisode: (json['guessEpisode'] as num?)?.toInt(),
      positionMs: (json['positionMs'] as num?)?.toInt(),
      durationMs: (json['durationMs'] as num?)?.toInt(),
      lastPlayedAt: (json['lastPlayedAt'] as num?)?.toInt(),
      showId: (json['showId'] as num?)?.toInt(),
      tmdbId: (json['tmdbId'] as num?)?.toInt(),
      showTitle: json['showTitle'] as String?,
      originalTitle: json['originalTitle'] as String?,
      showOverview: json['showOverview'] as String?,
      posterPath: json['posterPath'] as String?,
      backdropPath: json['backdropPath'] as String?,
      logoPath: json['logoPath'] as String?,
      voteAverage: (json['voteAverage'] as num?)?.toDouble(),
      releaseDate: json['releaseDate'] as String?,
      totalSeasons: (json['totalSeasons'] as num?)?.toInt(),
      totalEpisodes: (json['totalEpisodes'] as num?)?.toInt(),
      episodeId: (json['episodeId'] as num?)?.toInt(),
      seasonNumber: (json['seasonNumber'] as num?)?.toInt(),
      episodeNumber: (json['episodeNumber'] as num?)?.toInt(),
      episodeName: json['episodeName'] as String?,
      episodeOverview: json['episodeOverview'] as String?,
      episodeAirDate: json['episodeAirDate'] as String?,
      runtime: (json['runtime'] as num?)?.toInt(),
      stillPath: json['stillPath'] as String?,
      versionName: json['versionName'] as String?,
      versionDirPath: json['versionDirPath'] as String?,
    );
  }

  String get displayTitle {
    if (episodeName?.isNotEmpty == true) return episodeName!;
    return filename.isEmpty ? relativePath : filename;
  }

  int? get displayEpisode => episodeNumber ?? guessEpisode;
  int? get displaySeason => seasonNumber ?? guessSeason;
  String get versionKey => versionDirPath?.trim().isNotEmpty == true
      ? versionDirPath!.trim()
      : (versionName?.trim().isNotEmpty == true ? versionName!.trim() : '默认');
  String get versionLabel => versionName?.trim().isNotEmpty == true
      ? versionName!.trim()
      : (versionDirPath?.trim().isNotEmpty == true
          ? versionDirPath!.split('/').where((part) => part.isNotEmpty).last
          : '默认');
}

class LibraryRecentEntry {
  const LibraryRecentEntry({
    required this.fileId,
    required this.itemId,
    required this.relativePath,
    required this.filename,
    this.size,
    required this.positionMs,
    this.durationMs,
    this.lastPlayedAt,
    this.showTitle,
    this.posterPath,
    this.backdropPath,
    this.seasonNumber,
    this.episodeNumber,
    this.episodeName,
    this.stillPath,
  });

  final int fileId;
  final String itemId;
  final String relativePath;
  final String filename;
  final int? size;
  final int positionMs;
  final int? durationMs;
  final int? lastPlayedAt;
  final String? showTitle;
  final String? posterPath;
  final String? backdropPath;
  final int? seasonNumber;
  final int? episodeNumber;
  final String? episodeName;
  final String? stillPath;

  factory LibraryRecentEntry.fromJson(Map<String, dynamic> json) {
    return LibraryRecentEntry(
      fileId: (json['fileId'] as num?)?.toInt() ?? 0,
      itemId: json['itemId'] as String? ?? '',
      relativePath: json['relativePath'] as String? ?? '',
      filename: json['filename'] as String? ?? '',
      size: (json['size'] as num?)?.toInt(),
      positionMs: (json['positionMs'] as num?)?.toInt() ?? 0,
      durationMs: (json['durationMs'] as num?)?.toInt(),
      lastPlayedAt: (json['lastPlayedAt'] as num?)?.toInt(),
      showTitle: json['showTitle'] as String?,
      posterPath: json['posterPath'] as String?,
      backdropPath: json['backdropPath'] as String?,
      seasonNumber: (json['seasonNumber'] as num?)?.toInt(),
      episodeNumber: (json['episodeNumber'] as num?)?.toInt(),
      episodeName: json['episodeName'] as String?,
      stillPath: json['stillPath'] as String?,
    );
  }

  String get displayTitle {
    final prefix = showTitle?.isNotEmpty == true ? showTitle! : filename;
    if (episodeNumber == null) return prefix;
    final name = episodeName?.isNotEmpty == true ? ' $episodeName' : '';
    return '$prefix 第 $episodeNumber 集$name';
  }
}

class WebdavSourceDraft {
  const WebdavSourceDraft({
    required this.name,
    required this.baseUrl,
    required this.username,
    required this.password,
    this.otpCode = '',
    required this.directory,
  });

  final String name;
  final String baseUrl;
  final String username;
  final String password;
  final String otpCode;
  final String directory;
}

class SyncConfig {
  const SyncConfig({
    required this.baseUrl,
    required this.username,
    required this.password,
    required this.configPath,
    this.databasePath = '/Player/metadata.sqlite',
    this.syncConfigFile = true,
    this.syncDatabase = true,
  });

  final String baseUrl;
  final String username;
  final String password;
  final String configPath;
  final String databasePath;
  final bool syncConfigFile;
  final bool syncDatabase;

  MediaSourceConfig asSource() => MediaSourceConfig.webdav(
        id: 'sync',
        name: '同步 WebDAV',
        baseUrl: baseUrl,
        username: username,
        password: password,
        directory: '/',
      );

  factory SyncConfig.fromJson(Map<String, dynamic> json) => SyncConfig(
        baseUrl: json['baseUrl'] as String? ?? '',
        username: json['username'] as String? ?? '',
        password: json['password'] as String? ?? '',
        configPath: json['configPath'] as String? ?? '/Player/config.json',
        databasePath:
            json['databasePath'] as String? ?? '/Player/metadata.sqlite',
        syncConfigFile: json['syncConfigFile'] as bool? ?? true,
        syncDatabase: json['syncDatabase'] as bool? ?? true,
      );

  Map<String, dynamic> toJson() => {
        'baseUrl': baseUrl,
        'username': username,
        'password': password,
        'configPath': configPath,
        'databasePath': databasePath,
        'syncConfigFile': syncConfigFile,
        'syncDatabase': syncDatabase,
      };
}

class WebdavEntry {
  const WebdavEntry(
      {required this.name,
      required this.path,
      required this.url,
      required this.isDir,
      this.size});

  final String name;
  final String path;
  final String url;
  final bool isDir;
  final int? size;
}

class LocalEntry {
  const LocalEntry(
      {required this.name, required this.path, required this.isDir, this.size});

  final String name;
  final String path;
  final bool isDir;
  final int? size;
}
