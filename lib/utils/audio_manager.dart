import 'dart:async';
import 'dart:math';
import 'dart:typed_data';
import 'dart:io';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:path_provider/path_provider.dart';

/// Audio manager: authentic NES-style square wave sound effects + TTS for letters.
///
/// Sound effect data based on reverse-engineering of original Super Mario Bros (NES):
/// - All effects use **square wave** (NES APU pulse channel emulation)
/// - Coin: B5(494Hz) → E6(659Hz), 80ms gap
/// - Jump: D5(587Hz) → dip to C#5(554Hz) → chromatic climb to D6(1175Hz)
/// - Stomp: short low burst
/// - Game Over: C5→G4→E4→A4→B4→A4→G#4→A4→G4→G4→D4→E4
/// - Power-up: rapid ascending arpeggio C→E→G→C→E→G→high C
/// - 1-Up: E5→G5→E6→C6→D6→G6
/// - Bump: short noise burst
/// - Pipe: descending B→A#→A→G#→G
class AudioManager {
  static final AudioManager _instance = AudioManager._internal();
  factory AudioManager() => _instance;
  AudioManager._internal();

  final FlutterTts _tts = FlutterTts();
  final AudioPlayer _sfxPlayer = AudioPlayer(playerId: 'sfx');
  final AudioPlayer _sfxPlayer2 = AudioPlayer(playerId: 'sfx2');
  bool _initialized = false;
  bool _ttsReady = false;

  // TTS queue: prevents speak() from cancelling an in-progress utterance
  final _ttsQueue = <String>[];
  bool _ttsSpeaking = false;

  // Cached sound file paths
  String? _coinPath;
  String? _jumpPath;
  String? _stompPath;
  String? _gameOverPath;
  String? _powerUpPath;
  String? _oneUpPath;
  String? _bumpPath;
  String? _pipePath;

  static const Map<String, String> letterWords = {
    'A': 'Apple', 'B': 'Ball', 'C': 'Cat', 'D': 'Dog', 'E': 'Egg',
    'F': 'Fish', 'G': 'Goat', 'H': 'Hat', 'I': 'Ice cream', 'J': 'Jump',
    'K': 'Kite', 'L': 'Lion', 'M': 'Moon', 'N': 'Nest', 'O': 'Orange',
    'P': 'Pig', 'Q': 'Queen', 'R': 'Rain', 'S': 'Sun', 'T': 'Tree',
    'U': 'Umbrella', 'V': 'Van', 'W': 'Water', 'X': 'Xylophone',
    'Y': 'Yellow', 'Z': 'Zoo',
  };

  // ─── Note frequencies (Hz) ─────────────────────────────────────────────
  static const double _C4 = 261.63;
  static const double _D4 = 293.66;
  static const double _E4 = 329.63;
  static const double _G4 = 392.00;
  static const double _A4 = 440.00;
  static const double _As4 = 466.16;
  static const double _B4 = 493.88;
  static const double _Cs5 = 554.37;
  static const double _D5 = 587.33;
  static const double _Ds5 = 622.25;
  static const double _E5 = 659.25;
  static const double _F5 = 698.46;
  static const double _Fs5 = 739.99;
  static const double _G5 = 783.99;
  static const double _Gs5 = 830.61;
  static const double _A5 = 880.00;
  static const double _As5 = 932.33;
  static const double _B5 = 987.77;
  static const double _C6 = 1046.50;
  static const double _Cs6 = 1108.73;
  static const double _d6 = 1174.66;
  static const double _e6 = 1318.51;
  static const double _g6 = 1567.98;

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    // Initialize TTS
    try {
      await _tts.setLanguage('en-US');
      await _tts.setSpeechRate(0.35);
      await _tts.setVolume(1.0);
      await _tts.setPitch(1.0);
      await _tts.awaitSpeakCompletion(true);
      _ttsReady = true;
    } catch (_) {
      _ttsReady = false;
    }

    // Generate all sound effect WAV files
    try {
      _coinPath = await _generateFile(_buildCoin(), 'coin.wav');
      _jumpPath = await _generateFile(_buildJump(), 'jump.wav');
      _stompPath = await _generateFile(_buildStomp(), 'stomp.wav');
      _gameOverPath = await _generateFile(_buildGameOver(), 'gameover.wav');
      _powerUpPath = await _generateFile(_buildPowerUp(), 'powerup.wav');
      _oneUpPath = await _generateFile(_buildOneUp(), 'oneup.wav');
      _bumpPath = await _generateFile(_buildBump(), 'bump.wav');
      _pipePath = await _generateFile(_buildPipe(), 'pipe.wav');
    } catch (_) {
      // Sound generation failed - game still works without sounds
    }
  }

  // ─── WAV builder ──────────────────────────────────────────────────────

  Uint8List _buildWav(Float32List samples, {int sampleRate = 22050}) {
    final numChannels = 1;
    final bitsPerSample = 16;
    final dataSize = samples.length * (bitsPerSample ~/ 8);
    final headerSize = 44;

    final bytes = Uint8List(headerSize + dataSize);
    final bd = ByteData.view(bytes.buffer);

    // RIFF header
    bd.setUint8(0, 0x52); bd.setUint8(1, 0x49); bd.setUint8(2, 0x46); bd.setUint8(3, 0x46);
    bd.setUint32(4, 36 + dataSize, Endian.little);
    bd.setUint8(8, 0x57); bd.setUint8(9, 0x41); bd.setUint8(10, 0x56); bd.setUint8(11, 0x45);

    // fmt chunk
    bd.setUint8(12, 0x66); bd.setUint8(13, 0x6d); bd.setUint8(14, 0x74); bd.setUint8(15, 0x20);
    bd.setUint32(16, 16, Endian.little);
    bd.setUint16(20, 1, Endian.little);
    bd.setUint16(22, numChannels, Endian.little);
    bd.setUint32(24, sampleRate, Endian.little);
    bd.setUint32(28, sampleRate * numChannels * (bitsPerSample ~/ 8), Endian.little);
    bd.setUint16(32, numChannels * (bitsPerSample ~/ 8), Endian.little);
    bd.setUint16(34, bitsPerSample, Endian.little);

    // data chunk
    bd.setUint8(36, 0x64); bd.setUint8(37, 0x61); bd.setUint8(38, 0x74); bd.setUint8(39, 0x61);
    bd.setUint32(40, dataSize, Endian.little);

    for (int i = 0; i < samples.length; i++) {
      final v = (samples[i] * 32767).clamp(-32768, 32767).toInt();
      bd.setInt16(44 + i * 2, v, Endian.little);
    }

    return bytes;
  }

  /// Generate a square wave tone at [freq] for [durationMs] with ADSR envelope.
  Float32List _squareWave({
    required double freq,
    required int durationMs,
    double volume = 0.5,
    int attackMs = 2,
    int decayMs = 10,
    double sustainLevel = 0.7,
    int releaseMs = 20,
  }) {
    final sampleRate = 22050;
    final numSamples = (sampleRate * durationMs / 1000).toInt();
    final samples = Float32List(numSamples);

    final attackSamples = (sampleRate * attackMs / 1000).toInt();
    final decaySamples = (sampleRate * decayMs / 1000).toInt();
    final releaseSamples = (sampleRate * releaseMs / 1000).toInt();
    final sustainEnd = numSamples - releaseSamples;

    for (int i = 0; i < numSamples; i++) {
      final t = i / sampleRate;
      final wave = sin(2 * pi * freq * t) >= 0 ? 1.0 : -1.0;

      double env;
      if (i < attackSamples) {
        env = i / attackSamples;
      } else if (i < attackSamples + decaySamples) {
        final d = (i - attackSamples) / decaySamples;
        env = 1.0 - (1.0 - sustainLevel) * d;
      } else if (i < sustainEnd) {
        env = sustainLevel;
      } else {
        final r = (i - sustainEnd) / releaseSamples;
        env = sustainLevel * (1.0 - r);
      }
      env = env.clamp(0.0, 1.0);

      samples[i] = (wave * volume * env).toDouble();
    }

    return samples;
  }

  Float32List _concat(List<Float32List> segments) {
    int total = 0;
    for (final s in segments) { total += s.length; }
    final result = Float32List(total);
    int offset = 0;
    for (final s in segments) {
      result.setAll(offset, s);
      offset += s.length;
    }
    return result;
  }

  Float32List _silence(int durationMs) {
    final sampleRate = 22050;
    final n = (sampleRate * durationMs / 1000).toInt();
    return Float32List(n);
  }

  // ─── Sound effect builders ────────────────────────────────────────────

  Float32List _buildCoin() {
    return _concat([
      _squareWave(freq: _B5, durationMs: 80, volume: 0.5, attackMs: 1, decayMs: 5, sustainLevel: 0.8, releaseMs: 15),
      _silence(5),
      _squareWave(freq: _e6, durationMs: 380, volume: 0.5, attackMs: 1, decayMs: 10, sustainLevel: 0.8, releaseMs: 80),
    ]);
  }

  Float32List _buildJump() {
    final notes = [
      [_D5, 15], [_Cs5, 10],
      [_Ds5, 12], [_E5, 12], [_F5, 12], [_Fs5, 12],
      [_G5, 12], [_Gs5, 12], [_A5, 12], [_As5, 12],
      [_B5, 12], [_C6, 12], [_Cs6, 12], [_d6, 100],
    ];
    final segments = <Float32List>[];
    for (final n in notes) {
      segments.add(_squareWave(
        freq: n[0] as double,
        durationMs: n[1] as int,
        volume: 0.35,
        attackMs: 1,
        decayMs: 3,
        sustainLevel: 0.8,
        releaseMs: 8,
      ));
    }
    return _concat(segments);
  }

  Float32List _buildStomp() {
    return _concat([
      _squareWave(freq: _B4, durationMs: 40, volume: 0.5, attackMs: 1, decayMs: 5, sustainLevel: 0.6, releaseMs: 30),
      _squareWave(freq: _G4, durationMs: 60, volume: 0.4, attackMs: 1, decayMs: 5, sustainLevel: 0.5, releaseMs: 40),
    ]);
  }

  Float32List _buildGameOver() {
    final quarter = 400;
    final eighth = quarter ~/ 2;
    final segments = <Float32List>[];
    final v = 0.45;

    void addNote(double freq, int durMs) {
      segments.add(_squareWave(
        freq: freq, durationMs: durMs, volume: v,
        attackMs: 2, decayMs: 10, sustainLevel: 0.7, releaseMs: 30,
      ));
      segments.add(_silence(15));
    }

    addNote(_C4 * 2, quarter * 3 ~/ 2);
    addNote(_G4, quarter * 3 ~/ 2);
    addNote(_E4, quarter);
    addNote(_A4, eighth);
    addNote(_B4, eighth);
    addNote(_A4, eighth);
    addNote(_As4, eighth);
    addNote(_Gs5, eighth);
    addNote(_A4, eighth);
    addNote(_G4, eighth);
    addNote(_D4, eighth);
    addNote(_E4, quarter * 2);

    return _concat(segments);
  }

  Float32List _buildPowerUp() {
    final notes = [_C4 * 2, _E4 * 2, _G4 * 2, _C6, _e6, _g6, _C6 * 2];
    final segments = <Float32List>[];
    for (final f in notes) {
      segments.add(_squareWave(
        freq: f, durationMs: 50, volume: 0.4,
        attackMs: 1, decayMs: 5, sustainLevel: 0.8, releaseMs: 10,
      ));
    }
    return _concat(segments);
  }

  Float32List _buildOneUp() {
    final notes = [_E5, _G5, _e6, _C6, _d6, _g6];
    final segments = <Float32List>[];
    for (final f in notes) {
      segments.add(_squareWave(
        freq: f, durationMs: 60, volume: 0.4,
        attackMs: 1, decayMs: 5, sustainLevel: 0.8, releaseMs: 15,
      ));
    }
    return _concat(segments);
  }

  Float32List _buildBump() {
    final sampleRate = 22050;
    final numSamples = (sampleRate * 80 / 1000).toInt();
    final samples = Float32List(numSamples);
    final rng = Random();
    for (int i = 0; i < numSamples; i++) {
      final env = 1.0 - (i / numSamples);
      samples[i] = ((rng.nextDouble() * 2 - 1) * 0.3 * env).toDouble();
    }
    return samples;
  }

  Float32List _buildPipe() {
    final notes = [_B4, _As4, _A4, _Gs5, _G4];
    final segments = <Float32List>[];
    for (final f in notes) {
      segments.add(_squareWave(
        freq: f, durationMs: 60, volume: 0.4,
        attackMs: 1, decayMs: 5, sustainLevel: 0.7, releaseMs: 20,
      ));
    }
    return _concat(segments);
  }

  Future<String> _generateFile(Float32List samples, String filename) async {
    final wavBytes = _buildWav(samples);
    final dir = await getTemporaryDirectory();
    final path = '${dir.path}/$filename';
    final file = File(path);
    await file.writeAsBytes(wavBytes);
    return path;
  }

  // ─── TTS queue ─────────────────────────────────────────────────────────

  void _enqueueTts(String text) {
    if (!_ttsReady) return;
    _ttsQueue.add(text);
    _processTtsQueue();
  }

  Future<void> _processTtsQueue() async {
    if (_ttsSpeaking) return;
    if (_ttsQueue.isEmpty) return;

    _ttsSpeaking = true;
    final text = _ttsQueue.removeAt(0);
    try {
      await _tts.speak(text);
    } catch (_) {}
    _ttsSpeaking = false;

    if (_ttsQueue.isNotEmpty) {
      _processTtsQueue();
    }
  }

  // ─── Public API ────────────────────────────────────────────────────────

  void speakLetter(String letter) {
    final upper = letter.toUpperCase();
    final word = letterWords[upper] ?? upper;
    _enqueueTts('$upper, $word');
  }

  void playCoinSound() {
    if (_coinPath != null) {
      _sfxPlayer.play(DeviceFileSource(_coinPath!));
    }
  }

  void playJumpSound() {
    if (_jumpPath != null) {
      _sfxPlayer2.play(DeviceFileSource(_jumpPath!));
    }
  }

  void playStompSound() {
    if (_stompPath != null) {
      _sfxPlayer.play(DeviceFileSource(_stompPath!));
    }
  }

  void playBumpSound() {
    if (_bumpPath != null) {
      _sfxPlayer2.play(DeviceFileSource(_bumpPath!), volume: 0.4);
    }
  }

  void playPowerUpSound() {
    if (_powerUpPath != null) {
      _sfxPlayer.play(DeviceFileSource(_powerUpPath!));
    }
  }

  void playOneUpSound() {
    if (_oneUpPath != null) {
      _sfxPlayer.play(DeviceFileSource(_oneUpPath!));
    }
  }

  void playPipeSound() {
    if (_pipePath != null) {
      _sfxPlayer2.play(DeviceFileSource(_pipePath!));
    }
  }

  void playGameOverSound() {
    if (_gameOverPath != null) {
      _sfxPlayer.play(DeviceFileSource(_gameOverPath!));
    }
    _enqueueTts('Game over! Great job!');
  }

  void playEncouragement() {
    final phrases = ['Great job!', 'Amazing!', 'Wonderful!', 'Keep going!'];
    phrases.shuffle();
    _enqueueTts(phrases.first);
  }

  void dispose() {
    _tts.stop();
    _ttsQueue.clear();
    _sfxPlayer.dispose();
    _sfxPlayer2.dispose();
  }
}
