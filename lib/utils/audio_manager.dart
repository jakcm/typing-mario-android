import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

import 'critical_audio_queue.dart';

/// Audio for gameplay. All clips are bundled with the APK so Android TV does
/// not depend on system TTS, network access, or runtime audio generation.
class AudioManager {
  static final AudioManager _instance = AudioManager._internal();
  factory AudioManager() => _instance;
  AudioManager._internal();

  /// Gameplay effects use preloaded SoundPool players. They are dispatched
  /// immediately instead of waiting in a completion-driven FIFO (SoundPool does
  /// not emit completion events on Android).
  static const PlayerMode criticalEffectPlayerMode = PlayerMode.lowLatency;

  static const Map<String, String> letterWords = {
    'A': 'Apple',
    'B': 'Ball',
    'C': 'Cat',
    'D': 'Dog',
    'E': 'Egg',
    'F': 'Fish',
    'G': 'Goat',
    'H': 'Hat',
    'I': 'Ice cream',
    'J': 'Jump',
    'K': 'Kite',
    'L': 'Lion',
    'M': 'Moon',
    'N': 'Nest',
    'O': 'Orange',
    'P': 'Pig',
    'Q': 'Queen',
    'R': 'Rain',
    'S': 'Sun',
    'T': 'Tree',
    'U': 'Umbrella',
    'V': 'Van',
    'W': 'Water',
    'X': 'Xylophone',
    'Y': 'Yellow',
    'Z': 'Zoo',
  };

  static const _sfxPaths = <String>[
    'audio/sfx/coin.wav',
    'audio/sfx/jump.wav',
    'audio/sfx/stomp.wav',
    'audio/sfx/bump.wav',
    'audio/sfx/powerup.wav',
    'audio/sfx/oneup.wav',
    'audio/sfx/gameover.wav',
  ];

  static final AudioContext _gameAudioContext = AudioContext(
    android: const AudioContextAndroid(
      // SFX must never take focus away from the independently looping BGM.
      audioFocus: AndroidAudioFocus.none,
      contentType: AndroidContentType.sonification,
      usageType: AndroidUsageType.game,
    ),
    iOS: AudioContextIOS(category: AVAudioSessionCategory.ambient),
  );

  final AudioPlayer _bgmPlayer = AudioPlayer(playerId: 'bgm');
  final List<AudioPlayer> _voicePlayers = List.generate(
    2,
    (index) => AudioPlayer(playerId: 'voice-$index'),
  );
  late final _AudioPlayersEffectAdapter _effectAdapter =
      _AudioPlayersEffectAdapter();
  late BoundedEffectEngine _effectEngine = BoundedEffectEngine(
    adapter: _effectAdapter,
  );
  Future<void> _effectLifecycle = Future<void>.value();
  bool _effectsTerminal = false;

  bool _initialized = false;
  bool _bgmShouldPlay = false;
  late final DesiredPlaybackController _bgmController =
      DesiredPlaybackController(_AudioPlayersBgmAdapter(_bgmPlayer));
  final BgmRecoveryGate _bgmRecoveryGate = BgmRecoveryGate();
  final TerminalAudioLifecycleCoordinator _terminalLifecycle =
      TerminalAudioLifecycleCoordinator();
  int _nextVoicePlayer = 0;
  DateTime? _lastVoiceAt;

  Future<void> init() async {
    if (_initialized) return;

    try {
      await AudioPlayer.global.setAudioContext(_gameAudioContext);
      await _configurePlayer(_bgmPlayer, PlayerMode.mediaPlayer);
      await _bgmPlayer.setReleaseMode(ReleaseMode.loop);
      await _bgmPlayer.setVolume(0.28);
      for (final player in _voicePlayers) {
        await _configurePlayer(player, PlayerMode.lowLatency);
      }
      await _effectAdapter.init();
      // Load only the clips used at runtime. Word clips are intentionally not
      // queued: each monster now announces precisely one letter.
      await AudioCache.instance.loadAll([
        ..._sfxPaths,
        'audio/sfx/bgm.wav',
        ...letterWords.keys.map(
          (letter) => 'audio/letters/${letter.toLowerCase()}.wav',
        ),
      ]);
      _initialized = true;
      if (_bgmShouldPlay) _bgmController.setDesired(true);
    } catch (error, stackTrace) {
      // Keep initialization retryable instead of silently dropping every later
      // event behind a false "initialized" flag.
      debugPrint('Audio initialization failed: $error\n$stackTrace');
      rethrow;
    }
  }

  Future<void> _configurePlayer(AudioPlayer player, PlayerMode mode) async {
    await player.setAudioContext(_gameAudioContext);
    await player.setPlayerMode(mode);
  }

  /// Kept as a compatibility no-op for route callers. Word clips are not used.
  void setWordPronunciationEnabled(bool enabled) {}

  /// Plays exactly one embedded letter clip. No word clip is scheduled before
  /// or after it, preventing stale delayed pronunciations between monsters.
  void speakLetter(String letter) {
    final normalized = letter.toUpperCase();
    if (!_initialized || !letterWords.containsKey(normalized)) return;

    final now = DateTime.now();
    if (_lastVoiceAt != null &&
        now.difference(_lastVoiceAt!) < const Duration(milliseconds: 250)) {
      return;
    }
    _lastVoiceAt = now;
    _playVoice('audio/letters/${normalized.toLowerCase()}.wav');
  }

  /// Each cue has a small pool of preloaded players, so current game events
  /// start immediately instead of becoming delayed stale FIFO entries.
  void playCoinSound() => _effectEngine.play(EffectKind.coin);
  void playStompSound() => _effectEngine.play(EffectKind.stomp);
  void playDamageSound() => _effectEngine.play(EffectKind.damage, volume: 0.8);

  void playJumpSound() => _effectEngine.play(EffectKind.jump);
  void playBumpSound() => _effectEngine.play(EffectKind.bump, volume: 0.45);
  void playPowerUpSound() => _effectEngine.play(EffectKind.powerUp);
  void playOneUpSound() => _effectEngine.play(EffectKind.oneUp);
  void playGameOverSound() {
    _bgmShouldPlay = false;
    _bgmController.setDesired(false);
    _effectEngine.playGameOver();
  }

  AudioDiagnostics get effectDiagnostics => _effectEngine.diagnostics;
  void playEncouragement() {}

  void _playVoice(String asset) {
    final player = _voicePlayers[_nextVoicePlayer];
    _nextVoicePlayer = (_nextVoicePlayer + 1) % _voicePlayers.length;
    unawaited(_playSafely(player, asset, 1.0));
  }

  Future<void> _playSafely(
    AudioPlayer player,
    String asset,
    double volume,
  ) async {
    try {
      await player.play(AssetSource(asset), volume: volume);
    } catch (error) {
      debugPrint('Audio playback failed for $asset: $error');
    }
  }

  void startBgm() {
    _bgmShouldPlay = true;
    _bgmRecoveryGate.beginExplicitAttempt();
    if (_initialized) _bgmController.requestPlaying();
  }

  void ensureBgmPlaying() {
    if (!_initialized || !_bgmShouldPlay) return;
    if (_bgmPlayer.state == PlayerState.playing) {
      _bgmRecoveryGate.recordPlaying();
      return;
    }
    if (_bgmRecoveryGate.tryWatchdogRecovery()) {
      _bgmController.retryPlaying();
    }
  }

  void pauseBgm() {
    _bgmShouldPlay = false;
    _bgmController.setDesired(false);
    unawaited(_resetShortAudio());
  }

  void resumeBgm() => startBgm();

  void stopBgm() {
    _bgmShouldPlay = false;
    _bgmController.setDesired(false);
  }

  Future<void> _resetShortAudio() {
    if (_effectsTerminal) return _effectLifecycle;
    final oldEngine = _effectEngine;
    return _effectLifecycle = _effectLifecycle.then((_) async {
      await Future.wait([
        ..._voicePlayers.map((player) => player.stop()),
        oldEngine.shutdown(),
      ]);
      if (!_effectsTerminal && identical(_effectEngine, oldEngine)) {
        _effectEngine = BoundedEffectEngine(adapter: _effectAdapter);
      }
    });
  }

  /// Reset a game session while retaining the fixed native player set.
  void dispose() {
    stopBgm();
    unawaited(_resetShortAudio());
  }

  /// Terminal barrier: unlike a session reset this never creates a new engine.
  Future<void> stopAllAudio() => _terminalLifecycle.shutdown(_stopAllAudioOnce);

  Future<void> _stopAllAudioOnce() async {
    _bgmShouldPlay = false;
    _effectsTerminal = true;
    final engine = _effectEngine;
    final effects = _effectLifecycle = _effectLifecycle.then((_) async {
      await Future.wait([
        ..._voicePlayers.map((player) => player.stop()),
        engine.shutdown(),
      ]);
    });
    await Future.wait([effects, _bgmController.shutdown()]);
  }

  Future<void> close() async {
    await stopAllAudio();
    await _bgmPlayer.dispose();
    for (final player in _voicePlayers) {
      await player.dispose();
    }
    await _effectAdapter.close();
    _initialized = false;
  }
}

class _AudioPlayersEffectAdapter implements EffectPlayerAdapter {
  static const _assets = <EffectKind, String>{
    EffectKind.coin: 'audio/sfx/coin.wav',
    EffectKind.stomp: 'audio/sfx/stomp.wav',
    EffectKind.powerUp: 'audio/sfx/powerup.wav',
    EffectKind.oneUp: 'audio/sfx/oneup.wav',
    EffectKind.damage: 'audio/sfx/bump.wav',
    EffectKind.jump: 'audio/sfx/jump.wav',
    EffectKind.bump: 'audio/sfx/bump.wav',
    EffectKind.gameOver: 'audio/sfx/gameover.wav',
  };

  final List<AudioPlayer> _players = List.generate(
    defaultEffectSlotKinds.length,
    (slot) => AudioPlayer(
      playerId: 'effect-${defaultEffectSlotKinds[slot].name}-$slot',
    ),
  );

  Future<void> init() async {
    for (var slot = 0; slot < _players.length; slot++) {
      final player = _players[slot];
      await player.setAudioContext(AudioManager._gameAudioContext);
      await player.setPlayerMode(AudioManager.criticalEffectPlayerMode);
      await player.setReleaseMode(ReleaseMode.stop);
      await player.setSource(
        AssetSource(_assets[defaultEffectSlotKinds[slot]]!),
      );
    }
  }

  AudioPlayer _player(int slot, EffectKind kind) {
    assert(defaultEffectSlotKinds[slot] == kind);
    return _players[slot];
  }

  @override
  Future<void> stop(int slot, EffectKind kind) async {
    try {
      await _player(slot, kind).stop();
    } catch (error) {
      debugPrint('Effect stop failed for ${kind.name}: $error');
    }
  }

  @override
  Future<void> resume(int slot, EffectKind kind, double volume) async {
    final player = _player(slot, kind);
    try {
      await player.setVolume(volume);
      await player.resume();
    } catch (error) {
      debugPrint('Effect playback failed for ${kind.name}: $error');
    }
  }

  Future<void> close() async {
    await Future.wait(_players.map((player) => player.dispose()));
  }
}

class _AudioPlayersBgmAdapter implements DesiredPlaybackAdapter {
  _AudioPlayersBgmAdapter(this.player);
  final AudioPlayer player;

  @override
  Future<void> play() async {
    if (player.state == PlayerState.paused) {
      await player.resume();
    } else if (player.state != PlayerState.playing) {
      await player.play(AssetSource('audio/sfx/bgm.wav'));
    }
  }

  @override
  Future<void> stop() => player.stop();
}
