part of 'package:player_flutter/main.dart';

enum PlayerBackendPreference {
  automatic,
  libmpvOnly,
  nativePreferred,
  nativeForDolbyVisionOnly,
}

PlayerBackendPreference playerBackendPreferenceFromValue(Object? value) =>
    PlayerBackendPreference.values.firstWhere(
      (preference) => preference.name == value,
      orElse: () => PlayerBackendPreference.automatic,
    );

String playerBackendPreferenceLabel(PlayerBackendPreference preference) =>
    switch (preference) {
      PlayerBackendPreference.automatic => '自动',
      PlayerBackendPreference.libmpvOnly => '始终使用 libmpv',
      PlayerBackendPreference.nativePreferred => '优先使用系统原生播放器',
      PlayerBackendPreference.nativeForDolbyVisionOnly =>
        '仅 Dolby Vision 使用系统播放器',
    };

String playerBackendPreferenceDescription(PlayerBackendPreference preference) =>
    switch (preference) {
      PlayerBackendPreference.automatic => '普通视频使用 libmpv，确认原生 DV 能力后自动切换',
      PlayerBackendPreference.libmpvOnly => '兼容 WebDAV、复杂容器、音轨和 ASS 字幕',
      PlayerBackendPreference.nativePreferred => '优先尝试系统播放器，失败会自动回退 libmpv',
      PlayerBackendPreference.nativeForDolbyVisionOnly =>
        '仅真实流信息确认 Dolby Vision 且设备 Profile 匹配时尝试',
    };

class HardwareDecoderInfo {
  const HardwareDecoderInfo({
    required this.name,
    required this.mimeType,
    required this.hardwareAccelerated,
    this.dolbyVisionProfiles = const {},
  });

  final String name;
  final String mimeType;
  final bool hardwareAccelerated;
  final Set<int> dolbyVisionProfiles;
}

class DeviceCapabilities {
  const DeviceCapabilities({
    required this.nativeBackendAvailable,
    required this.supportsNativeDolbyVision,
    required this.supportedDolbyVisionProfiles,
    required this.supportsHdr10,
    required this.hardwareDecoders,
    this.nativeBackendExperimental = false,
  });

  const DeviceCapabilities.unavailable()
      : nativeBackendAvailable = false,
        supportsNativeDolbyVision = false,
        supportedDolbyVisionProfiles = const {},
        supportsHdr10 = false,
        hardwareDecoders = const [],
        nativeBackendExperimental = false;

  final bool nativeBackendAvailable;
  final bool supportsNativeDolbyVision;
  final Set<int> supportedDolbyVisionProfiles;
  final bool supportsHdr10;
  final List<HardwareDecoderInfo> hardwareDecoders;
  final bool nativeBackendExperimental;
}

class DeviceCapabilityDetector {
  const DeviceCapabilityDetector();

  Future<DeviceCapabilities> detect() async {
    if (Platform.isWindows) {
      return const DeviceCapabilities(
        nativeBackendAvailable: true,
        supportsNativeDolbyVision: false,
        supportedDolbyVisionProfiles: {},
        supportsHdr10: false,
        hardwareDecoders: [
          HardwareDecoderInfo(
            name: 'Windows Media Foundation',
            mimeType: 'video/*',
            hardwareAccelerated: true,
          ),
        ],
        nativeBackendExperimental: true,
      );
    }
    if (!Platform.isAndroid) return const DeviceCapabilities.unavailable();
    try {
      final value = await appChannel.invokeMapMethod<String, dynamic>(
        'nativePlaybackCapabilities',
      );
      if (value == null) return const DeviceCapabilities.unavailable();
      final decoders = <HardwareDecoderInfo>[
        for (final item
            in value['hardwareDecoders'] as List<dynamic>? ?? const [])
          if (item is Map)
            HardwareDecoderInfo(
              name: '${item['name'] ?? 'unknown'}',
              mimeType: '${item['mimeType'] ?? 'video/*'}',
              hardwareAccelerated: item['hardwareAccelerated'] == true,
              dolbyVisionProfiles: {
                for (final profile
                    in item['dolbyVisionProfiles'] as List<dynamic>? ??
                        const [])
                  if (profile is int) profile,
              },
            ),
      ];
      return DeviceCapabilities(
        nativeBackendAvailable: true,
        supportsNativeDolbyVision: value['supportsNativeDolbyVision'] == true,
        supportedDolbyVisionProfiles: {
          for (final profile
              in value['supportedDolbyVisionProfiles'] as List<dynamic>? ??
                  const [])
            if (profile is int) profile,
        },
        supportsHdr10: value['supportsHdr10'] == true,
        hardwareDecoders: decoders,
      );
    } catch (_) {
      return const DeviceCapabilities.unavailable();
    }
  }
}

class PlayerBackendDecision {
  const PlayerBackendDecision({required this.backend, required this.reason});

  final PlayerBackend backend;
  final String reason;
}

class PlayerBackendFactory {
  const PlayerBackendFactory();

  bool wantsNative({
    required PlayerBackendPreference preference,
    required MediaInfo media,
    required DeviceCapabilities device,
  }) {
    if (preference == PlayerBackendPreference.libmpvOnly ||
        !device.nativeBackendAvailable) {
      return false;
    }
    if (preference == PlayerBackendPreference.nativePreferred) return true;
    return media.isDolbyVision && _supportsProfile(media, device);
  }

  PlayerBackendDecision createBackend({
    required PlayerMediaSource source,
    required MediaInfo media,
    required DeviceCapabilities device,
    required PlayerBackendPreference preference,
  }) {
    if (!wantsNative(
      preference: preference,
      media: media,
      device: device,
    )) {
      return PlayerBackendDecision(
        backend: LibmpvBackend(mediaInfo: media),
        reason: preference == PlayerBackendPreference.libmpvOnly
            ? 'user_selected_libmpv_only'
            : !media.isDolbyVision
                ? 'standard_or_unconfirmed_dolby_vision'
                : 'native_dolby_vision_profile_unsupported',
      );
    }
    if (source.isRemote && !source.nativeProxyReady) {
      return PlayerBackendDecision(
        backend: LibmpvBackend(mediaInfo: media),
        reason: 'remote_range_proxy_unavailable',
      );
    }
    final decoder = _matchingDecoder(media, device);
    if (Platform.isAndroid) {
      return PlayerBackendDecision(
        backend: AndroidNativeBackend(decoder: decoder),
        reason: preference == PlayerBackendPreference.nativePreferred
            ? 'user_selected_native_preferred'
            : 'dolby_vision_profile_supported',
      );
    }
    if (Platform.isWindows) {
      return PlayerBackendDecision(
        backend: WindowsNativeBackend(decoder: decoder),
        reason: preference == PlayerBackendPreference.nativePreferred
            ? 'user_selected_windows_native_experimental'
            : 'windows_native_dolby_vision_experimental',
      );
    }
    return PlayerBackendDecision(
      backend: LibmpvBackend(mediaInfo: media),
      reason: 'native_backend_unavailable',
    );
  }

  PlayerBackend createFallbackBackend(
          {MediaInfo media = const MediaInfo.unknown()}) =>
      LibmpvBackend(mediaInfo: media);

  bool _supportsProfile(MediaInfo media, DeviceCapabilities device) {
    if (!device.supportsNativeDolbyVision) return false;
    final profile = media.dolbyVisionProfile;
    return profile == null ||
        device.supportedDolbyVisionProfiles.contains(profile);
  }

  HardwareDecoderInfo? _matchingDecoder(
    MediaInfo media,
    DeviceCapabilities device,
  ) {
    final profile = media.dolbyVisionProfile;
    for (final decoder in device.hardwareDecoders) {
      if (!decoder.hardwareAccelerated) continue;
      if (profile == null || decoder.dolbyVisionProfiles.contains(profile)) {
        return decoder;
      }
    }
    return device.hardwareDecoders.firstOrNull;
  }
}
