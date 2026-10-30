import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/services.dart';

/// One place for the little bits of physical feedback the app gives back:
/// a haptic tick on taps and short, quiet sounds for meaningful moments.
///
/// Both channels are user-toggleable in Settings and both are best-effort —
/// a device with no vibrator, a browser that blocks audio, or a failed asset
/// load must never break the interaction, so every call swallows its errors.
class KindredFeedback {
  KindredFeedback._();

  static bool hapticsEnabled = true;
  static bool soundsEnabled = true;

  static final Map<String, AudioPlayer> _players = {};
  static bool _audioContextReady = false;

  /// UI sounds should be polite: respect the silent switch and duck under
  /// whatever else is playing instead of pausing the user's music.
  static Future<void> _ensureAudioContext() async {
    if (_audioContextReady) return;
    _audioContextReady = true;
    try {
      await AudioPlayer.global.setAudioContext(
        AudioContextConfig(
          respectSilence: true,
          focus: AudioContextConfigFocus.mixWithOthers,
        ).build(),
      );
    } catch (_) {}
  }

  static Future<void> _sound(String name, {double volume = 0.6}) async {
    if (!soundsEnabled) return;
    try {
      await _ensureAudioContext();
      final player = _players.putIfAbsent(name, () {
        final p = AudioPlayer();
        p.setReleaseMode(ReleaseMode.stop);
        p.setPlayerMode(PlayerMode.lowLatency);
        return p;
      });
      // Re-playing restarts from the top; stop first so rapid taps don't queue up.
      await player.stop();
      await player.play(AssetSource('sounds/$name.wav'), volume: volume);
    } catch (_) {}
  }

  static Future<void> _haptic(Future<void> Function() fn) async {
    if (!hapticsEnabled) return;
    try {
      await fn();
    } catch (_) {}
  }

  /// Every button/card press: a barely-there tick plus a soft click.
  static Future<void> tap() async {
    await _haptic(HapticFeedback.selectionClick);
    await _sound('tap', volume: 0.35);
  }

  /// Something changed state without being a "win" (claiming, opening, toggling).
  static Future<void> press() async {
    await _haptic(HapticFeedback.lightImpact);
  }

  /// A deliberate, slightly firmer confirmation tick with no sound.
  static Future<void> heavy() async {
    await _haptic(HapticFeedback.mediumImpact);
  }

  /// A request was claimed/completed/confirmed, or an act was verified.
  static Future<void> success() async {
    await _haptic(HapticFeedback.mediumImpact);
    await _sound('success');
  }

  /// A message sent or arrived.
  static Future<void> message() async {
    await _haptic(HapticFeedback.lightImpact);
    await _sound('message', volume: 0.5);
  }

  /// Level up, new badge, streak milestone.
  static Future<void> celebrate() async {
    await _haptic(HapticFeedback.heavyImpact);
    await _sound('level_up', volume: 0.7);
  }

  /// A failed action the user needs to notice.
  static Future<void> error() async {
    await _haptic(HapticFeedback.heavyImpact);
    await _sound('error', volume: 0.5);
  }

  static Future<void> dispose() async {
    for (final player in _players.values) {
      try {
        await player.dispose();
      } catch (_) {}
    }
    _players.clear();
  }
}
