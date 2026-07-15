import 'dart:math';
import 'package:flame/game.dart';
import 'package:flame/events.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'components/scrolling_background.dart';
import 'components/hud.dart';
import 'components/coin_effect.dart';
import 'sprites/mario_sprite.dart';
import 'sprites/obstacle_sprite.dart';
import '../utils/audio_manager.dart';

/// Main game class for Typing Mario.
/// An auto-runner where obstacles appear with letters; the player
/// must type the correct letter to destroy them.
class TypingMarioGame extends FlameGame with KeyboardEvents {
  final void Function(int score)? onGameOver;

  TypingMarioGame({this.onGameOver});

  // ─── State ────────────────────────────────────────────────────────────
  int score = 0;
  int lives = 3;
  double gameSpeed = 120; // base obstacle speed
  bool isGameOver = false;
  bool isPaused = false;

  double _spawnTimer = 0;
  double _spawnDelay = 2.0; // seconds between obstacles
  bool _waitingForSpawn = true;
  int _correctStreak = 0;

  // Screen shake state
  double _shakeTimer = 0;
  double _shakeIntensity = 0;
  Vector2 _cameraBase = Vector2.zero();

  // Components
  late MarioSprite _mario;
  late HudComponent _hud;
  ObstacleSprite? _currentObstacle;
  ScrollingBackground? _background;
  final AudioManager _audio = AudioManager();
  final Random _rng = Random();

  // Screen dimensions (cached)
  late double _screenW;
  late double _groundY;

  // All static letter options
  static const String _letters = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ';

  @override
  Future<void> onLoad() async {
    super.onLoad();

    _screenW = size.x;
    _groundY = size.y * 0.78;

    // Background
    _background = ScrollingBackground();
    add(_background!);

    // Mario
    _mario = MarioSprite(groundY: _groundY);
    add(_mario);
    _mario.setRunning();

    // HUD
    _hud = HudComponent();
    add(_hud);

    // Initialize audio
    await _audio.init();

    // Start spawn timer
    _spawnTimer = _spawnDelay;
    _waitingForSpawn = true;

    // Camera base position
    _cameraBase = camera.viewfinder.position.clone();
  }

  @override
  void update(double dt) {
    super.update(dt);
    if (isGameOver || isPaused) return;

    // Screen shake effect
    _updateShake(dt);

    // Spawn obstacles
    if (_waitingForSpawn) {
      _spawnTimer -= dt;
      if (_spawnTimer <= 0) {
        _spawnObstacle();
        _waitingForSpawn = false;
      }
    }

    // Check if current obstacle passed Mario (damage)
    if (_currentObstacle != null &&
        !_currentObstacle!.isDestroyed &&
        _currentObstacle!.hasPassedMario) {
      _onObstaclePassed();
    }
  }

  // ─── Obstacle spawning ────────────────────────────────────────────────

  void _spawnObstacle() {
    if (isGameOver) return;

    // Pick a random letter
    final letter = _letters[_rng.nextInt(_letters.length)];

    final obstacle = ObstacleSprite(
      letter: letter,
      speed: gameSpeed,
      groundY: _groundY,
      startX: _screenW + 20,
    );
    add(obstacle);
    _currentObstacle = obstacle;

    // Show letter hint in HUD
    _hud.showLetterHint(letter);

    // Speak the letter
    _audio.speakLetter(letter);
  }

  void _scheduleNextSpawn() {
    _waitingForSpawn = true;
    _spawnTimer = _spawnDelay;
    _hud.hideLetterHint();
  }

  // ─── Input handling ───────────────────────────────────────────────────

  @override
  KeyEventResult onKeyEvent(KeyEvent event, Set<LogicalKeyboardKey> keysPressed) {
    if (isGameOver) return KeyEventResult.ignored;
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    // Get the typed character
    final key = event.logicalKey;
    String? typedLetter;

    // Check for letter keys A-Z
    if (key.keyId >= LogicalKeyboardKey.keyA.keyId &&
        key.keyId <= LogicalKeyboardKey.keyZ.keyId) {
      typedLetter = String.fromCharCode(
        'A'.codeUnitAt(0) +
            (key.keyId - LogicalKeyboardKey.keyA.keyId),
      );
    }

    if (typedLetter != null) {
      onLetterTyped(typedLetter);
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  /// Public method for on-screen keyboard to call.
  void onLetterTyped(String letter) {
    if (isGameOver) return;
    final upper = letter.toUpperCase();

    // If no current obstacle, ignore
    if (_currentObstacle == null || _currentObstacle!.isDestroyed) return;

    // Compare case-insensitively
    if (upper == _currentObstacle!.letter.toUpperCase()) {
      _onCorrectLetter();
    } else {
      _onWrongLetter();
    }
  }

  // ─── Correct / Wrong letter handling ──────────────────────────────────

  void _onCorrectLetter() {
    if (_currentObstacle == null) return;

    // Destroy obstacle
    _currentObstacle!.destroy();

    // Mario jumps
    _mario.jump();

    // Play jump + stomp + coin sounds (classic Mario combo)
    _audio.playJumpSound();
    _audio.playStompSound();
    _audio.playCoinSound();

    // Score
    score += 10;
    _correctStreak++;
    _hud.setScore(score);

    // Coin effect at obstacle position
    add(CoinEffect(
      position: Vector2(
        _currentObstacle!.position.x + _currentObstacle!.size.x / 2,
        _currentObstacle!.position.y - _currentObstacle!.size.y / 2,
      ),
    ));

    // Encouragement on streaks of 3
    if (_correctStreak >= 3 && _correctStreak % 3 == 0) {
      _audio.playEncouragement();
    }

    // Increase difficulty slightly
    gameSpeed = (gameSpeed + 3).clamp(120, 350);
    _spawnDelay = (_spawnDelay - 0.05).clamp(0.8, 2.0);

    // Schedule next obstacle
    _scheduleNextSpawn();
  }

  void _onWrongLetter() {
    _correctStreak = 0;
    // Wrong key: just bump sound + small shake, NO life loss.
    // Life is only lost when an enemy reaches Mario without being destroyed.
    _shakeScreen();
    _audio.playBumpSound();
  }

  void _onObstaclePassed() {
    if (_currentObstacle == null) return;
    _correctStreak = 0;
    // Play stomp sound (enemy hits Mario) before losing life
    _audio.playStompSound();
    _loseLife();

    // Remove the obstacle
    _currentObstacle!.removeFromParent();
    _currentObstacle = null;

    // Schedule next
    _scheduleNextSpawn();
  }

  void _loseLife() {
    lives--;
    _hud.setLives(lives);
    _mario.hurt();

    if (lives <= 0) {
      _triggerGameOver();
    }
  }

  // ─── Game over ────────────────────────────────────────────────────────

  void _triggerGameOver() {
    isGameOver = true;
    _mario.die();
    _audio.playGameOverSound();

    // Delay before navigating
    Future.delayed(const Duration(seconds: 2), () {
      onGameOver?.call(score);
    });
  }

  // ─── Screen shake ─────────────────────────────────────────────────────

  void _shakeScreen() {
    _shakeTimer = 0.4;
    _shakeIntensity = 8.0;
  }

  void _updateShake(double dt) {
    if (_shakeTimer > 0) {
      _shakeTimer -= dt;
      final ox = (_rng.nextDouble() * 2 - 1) * _shakeIntensity;
      final oy = (_rng.nextDouble() * 2 - 1) * _shakeIntensity;
      camera.viewfinder.position = _cameraBase + Vector2(ox, oy);
      _shakeIntensity *= 0.9;
    } else {
      camera.viewfinder.position = _cameraBase.clone();
    }
  }

  // ─── Cleanup ──────────────────────────────────────────────────────────

  @override
  void onRemove() {
    _audio.dispose();
    super.onRemove();
  }
}
