import 'dart:async';

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
  static final Map<String, int> _lastPlayedMs = {};
  static Future<void>? _audioContext;

  /// UI sounds should be polite: respect the silent switch and mix under
  /// whatever else is playing instead of pausing the user's music.
  ///
  /// The future is cached so the platform channel runs once, and cleared again
  /// if it fails so a later tap can retry.
  static Future<void> _ensureAudioContext() =>
      _audioContext ??= _configureAudioContext();

  static Future<void> _configureAudioContext() async {
    try {
      await AudioPlayer.global.setAudioContext(
        AudioContextConfig(
          respectSilence: true,
          focus: AudioContextConfigFocus.mixWithOthers,
        ).build(),
      );
    } catch (_) {
      _audioContext = null;
    }
  }

  /// Builds the players up front so the first real tap is not delayed by
  /// allocating one (and warming the audio session) on the interaction itself.
  static Future<void> warmUp() async {
    try {
      await _ensureAudioContext();
      for (final name in const ['tap', 'message', 'success', 'level_up', 'error']) {
        _playerFor(name);
      }
    } catch (_) {}
  }

  static AudioPlayer _playerFor(String name) => _players.putIfAbsent(name, () {
        final p = AudioPlayer();
        // Keep the decoded source so replays start instantly. The default
        // (media) player mode is used on purpose: lowLatency on Android routes
        // through SoundPool, which ignores per-play volume and can drop or
        // stutter rapid replays — that is what made the taps feel off.
        p.setReleaseMode(ReleaseMode.stop);
        return p;
      });

  static Future<void> _sound(String name, {double volume = 0.5}) async {
    if (!soundsEnabled) return;
    // Two widgets can react to the same interaction (a card and the button
    // inside it); without this the same clip fires twice and sounds doubled.
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - (_lastPlayedMs[name] ?? 0) < 45) return;
    _lastPlayedMs[name] = now;
    try {
      await _ensureAudioContext();
      await _playerFor(name).play(AssetSource('sounds/$name.wav'), volume: volume);
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
    unawaited(_haptic(HapticFeedback.selectionClick));
    unawaited(_sound('tap', volume: 0.22));
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
    unawaited(_haptic(HapticFeedback.mediumImpact));
    unawaited(_sound('success', volume: 0.5));
  }

  /// A message arrived in the conversation you are looking at.
  static Future<void> message() async {
    unawaited(_haptic(HapticFeedback.lightImpact));
    unawaited(_sound('message', volume: 0.4));
  }

  /// Level up, new badge, streak milestone.
  static Future<void> celebrate() async {
    unawaited(_haptic(HapticFeedback.heavyImpact));
    unawaited(_sound('level_up', volume: 0.6));
  }

  /// A failed action the user needs to notice.
  static Future<void> error() async {
    unawaited(_haptic(HapticFeedback.heavyImpact));
    unawaited(_sound('error', volume: 0.45));
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
