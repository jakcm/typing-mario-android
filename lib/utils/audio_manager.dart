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

  /// Critical gameplay effects must use MediaPlayer on Android. SoundPool
  /// (PlayerMode.lowLatency) does not emit completion events, so a FIFO channel
  /// driven by onPlayerComplete would play its first request and remain busy
  /// forever, silently retaining every later coin/stomp/damage request.
  static const PlayerMode criticalEffectPlayerMode = PlayerMode.mediaPlayer;

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
  final _CriticalEffectChannel _coinChannel = _CriticalEffectChannel('coin');
  final _CriticalEffectChannel _stompChannel = _CriticalEffectChannel('stomp');
  final _CriticalEffectChannel _damageChannel = _CriticalEffectChannel(
    'damage',
  );
  // Only low-value spam cues are bounded. Reward, stomp, damage, life-loss,
  // power-up, and game-over channels remain lossless FIFOs.
  final _CriticalEffectChannel _jumpChannel = _CriticalEffectChannel(
    'jump',
    maxPending: 1,
    coalescePendingDuplicates: true,
  );
  final _CriticalEffectChannel _bumpChannel = _CriticalEffectChannel(
    'bump',
    maxPending: 1,
    coalescePendingDuplicates: true,
  );
  final _CriticalEffectChannel _powerUpChannel = _CriticalEffectChannel(
    'powerup',
  );
  final _CriticalEffectChannel _oneUpChannel = _CriticalEffectChannel('oneup');
  final _CriticalEffectChannel _gameOverChannel = _CriticalEffectChannel(
    'gameover',
  );

  bool _initialized = false;
  bool _bgmShouldPlay = false;
  bool _bgmStarting = false;
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
      await _coinChannel.init();
      await _stompChannel.init();
      await _damageChannel.init();
      await _jumpChannel.init();
      await _bumpChannel.init();
      await _powerUpChannel.init();
      await _oneUpChannel.init();
      await _gameOverChannel.init();
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

  /// Every gameplay cue has an isolated FIFO channel. No cue can replace
  /// another cue, and rapid identical events are retained until played.
  void playCoinSound() => _coinChannel.play('audio/sfx/coin.wav');
  void playStompSound() => _stompChannel.play('audio/sfx/stomp.wav');
  void playDamageSound() =>
      _damageChannel.play('audio/sfx/bump.wav', volume: 0.8);

  void playJumpSound() => _jumpChannel.play('audio/sfx/jump.wav');
  void playBumpSound() => _bumpChannel.play('audio/sfx/bump.wav', volume: 0.45);
  void playPowerUpSound() => _powerUpChannel.play('audio/sfx/powerup.wav');
  void playOneUpSound() => _oneUpChannel.play('audio/sfx/oneup.wav');
  void playGameOverSound() => _gameOverChannel.play('audio/sfx/gameover.wav');
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
    unawaited(_startBgm());
  }

  Future<void> _startBgm() async {
    if (!_initialized || !_bgmShouldPlay || _bgmStarting) return;
    _bgmStarting = true;
    try {
      // Resume preserves the loop position after pause. Fresh sessions start
      // from the bundled source, which loops natively without Dart callbacks.
      if (_bgmPlayer.state == PlayerState.paused) {
        await _bgmPlayer.resume();
      } else if (_bgmPlayer.state != PlayerState.playing) {
        await _bgmPlayer.play(AssetSource('audio/sfx/bgm.wav'));
      }
    } catch (error) {
      debugPrint('BGM playback failed: $error');
    } finally {
      _bgmStarting = false;
    }
  }

  /// Called at a low frequency from the game loop only to repair real media
  /// interruptions; normal looping happens natively without Dart restarts.
  void ensureBgmPlaying() {
    if (_bgmShouldPlay && _bgmPlayer.state != PlayerState.playing) {
      unawaited(_startBgm());
    }
  }

  void pauseBgm() {
    _bgmShouldPlay = false;
    unawaited(_bgmPlayer.pause());
    _stopShortAudio();
  }

  void resumeBgm() {
    _bgmShouldPlay = true;
    unawaited(_startBgm());
  }

  void stopBgm() {
    _bgmShouldPlay = false;
    unawaited(_bgmPlayer.stop());
  }

  void _stopShortAudio() {
    for (final player in _voicePlayers) {
      unawaited(player.stop());
    }
    _coinChannel.stop();
    _stompChannel.stop();
    _damageChannel.stop();
    _jumpChannel.stop();
    _bumpChannel.stop();
    _powerUpChannel.stop();
    _oneUpChannel.stop();
    _gameOverChannel.stop();
  }

  /// Reset a game session while retaining native player objects.
  void dispose() {
    stopBgm();
    _stopShortAudio();
  }

  Future<void> close() async {
    await _bgmPlayer.dispose();
    for (final player in _voicePlayers) {
      await player.dispose();
    }
    await _coinChannel.close();
    await _stompChannel.close();
    await _damageChannel.close();
    await _jumpChannel.close();
    await _bumpChannel.close();
    await _powerUpChannel.close();
    await _oneUpChannel.close();
    await _gameOverChannel.close();
    _initialized = false;
  }
}

class _CriticalEffectChannel {
  _CriticalEffectChannel(
    String id, {
    int? maxPending,
    bool coalescePendingDuplicates = false,
  }) : _player = AudioPlayer(playerId: 'critical-$id'),
       _queue = CriticalAudioQueue<_EffectRequest>(
         maxPending: maxPending,
         coalescePendingDuplicates: coalescePendingDuplicates,
       ) {
    _listenForCompletion();
  }

  final AudioPlayer _player;
  final CriticalAudioQueue<_EffectRequest> _queue;
  StreamSubscription<void>? _completionSubscription;
  Future<void> _operations = Future<void>.value();

  void _listenForCompletion() {
    _completionSubscription = _player.onPlayerComplete.listen(
      (_) => _serialize(_advance),
    );
  }

  Future<void> init() async {
    await _player.setAudioContext(AudioManager._gameAudioContext);
    await _player.setPlayerMode(AudioManager.criticalEffectPlayerMode);
    await _player.setReleaseMode(ReleaseMode.stop);
  }

  void play(String asset, {double volume = 1.0}) {
    if (!AudioManager()._initialized) return;
    final request = _EffectRequest(asset, volume);
    _serialize(() async {
      final next = _queue.enqueue(request);
      if (next != null) await _start(next);
    });
  }

  Future<void> _start(_EffectRequest request) async {
    try {
      await _player.play(AssetSource(request.asset), volume: request.volume);
    } catch (error) {
      debugPrint('Critical audio playback failed for ${request.asset}: $error');
      await _advance();
    }
  }

  Future<void> _advance() async {
    final next = _queue.complete();
    if (next != null) await _start(next);
  }

  void _serialize(Future<void> Function() operation) {
    _operations = _operations.then((_) => operation()).catchError((error) {
      debugPrint('Critical audio channel operation failed: $error');
    });
  }

  void stop() {
    // Canceling the old session's listener before stop makes a late native
    // completion incapable of advancing requests enqueued for the new session.
    // Stop/reset/relisten and all play calls share this operation chain.
    _serialize(() async {
      await _completionSubscription?.cancel();
      _completionSubscription = null;
      await _player.stop();
      _queue.reset();
      _listenForCompletion();
    });
  }

  Future<void> close() async {
    await _operations;
    await _completionSubscription?.cancel();
    await _player.dispose();
  }
}

class _EffectRequest {
  const _EffectRequest(this.asset, this.volume);
  final String asset;
  final double volume;

  @override
  bool operator ==(Object other) =>
      other is _EffectRequest && other.asset == asset && other.volume == volume;

  @override
  int get hashCode => Object.hash(asset, volume);
}
