part of 'package:player_flutter/main.dart';

class PlaybackSnapshot {
  const PlaybackSnapshot({
    required this.source,
    required this.position,
    required this.wasPlaying,
    required this.volume,
    required this.speed,
    required this.fitMode,
    required this.fullscreen,
    required this.danmuVisible,
    this.audioTrack,
    this.subtitleTrack,
    this.subtitleDelay,
    this.audioDelay,
  });

  final PlayerMediaSource source;
  final Duration position;
  final bool wasPlaying;
  final double volume;
  final double speed;
  final PlayerTrack? audioTrack;
  final PlayerTrack? subtitleTrack;
  final Duration? subtitleDelay;
  final Duration? audioDelay;
  final VideoFitMode fitMode;
  final bool fullscreen;
  final bool danmuVisible;
}

PlayerTrack? matchPlayerTrack(
  PlayerTrack? wanted,
  List<PlayerTrack> candidates,
) {
  if (wanted == null || candidates.isEmpty) return null;
  var bestScore = 0;
  PlayerTrack? best;
  for (final candidate in candidates) {
    var score = 0;
    if (_sameTrackText(wanted.language, candidate.language)) score += 8;
    if (_sameTrackText(wanted.title, candidate.title)) score += 4;
    if (_sameTrackText(wanted.codec, candidate.codec)) score += 3;
    if (wanted.channelCount != null &&
        wanted.channelCount == candidate.channelCount) {
      score += 2;
    }
    if (wanted.isDefault == candidate.isDefault) score += 1;
    if (wanted.isForced == candidate.isForced) score += 1;
    if (score > bestScore) {
      bestScore = score;
      best = candidate;
    }
  }
  return bestScore >= 3 ? best : null;
}

bool _sameTrackText(String? left, String? right) {
  final a = left?.trim().toLowerCase();
  final b = right?.trim().toLowerCase();
  return a != null && a.isNotEmpty && a == b;
}
