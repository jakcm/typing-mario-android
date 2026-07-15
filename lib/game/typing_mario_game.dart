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
import 'sprites/floating_coin.dart';
import 'sprites/platform_sprite.dart';
import 'sprites/gap_sprite.dart';
import 'core/letter_target.dart';
import '../utils/audio_manager.dart';

/// Main game class for Typing Mario.
/// An auto-runner where obstacles, coins, platforms, and gaps appear with
/// letters; the player types letters to interact with them.
class TypingMarioGame extends FlameGame with KeyboardEvents {
  final void Function(int score)? onGameOver;

  TypingMarioGame({this.onGameOver});

  // ─── State ────────────────────────────────────────────────────────────
  int score = 0;
  int lives = 3;
  double gameSpeed = 120; // base obstacle speed
  bool isGameOver = false;
  bool isPaused = false;

  // Screen shake state
  double _shakeTimer = 0;
  double _shakeIntensity = 0;
  Vector2 _cameraBase = Vector2.zero();

  // Components
  late MarioSprite _mario;
  late HudComponent _hud;
  ScrollingBackground? _background;
  final AudioManager _audio = AudioManager();
  final Random _rng = Random();

  // ─── Multi-target system ──────────────────────────────────────────────
  final List<LetterTarget> _activeTargets = [];
  final Set<String> _usedLetters = {};
  int _correctStreak = 0;

  // Spawn timers
  double _obstacleTimer = 0;
  double _coinTimer = 0;
  double _platformTimer = 0;
  double _gapTimer = 0;

  static const double _obstacleDelay = 2.0;
  static const double _coinDelay = 6.0;
  static const double _platformDelay = 10.0;
  static const double _gapDelay = 14.0;

  // Screen dimensions (cached)
  late double _screenW;
  late double _groundY;

  static const String _allLetters = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ';

  // Active platform Mario is standing on (null = on ground)
  PlatformSprite? _activePlatform;

  // ─── Letter pool management ──────────────────────────────────────────

  String _pickAvailableLetter() {
    final available = _allLetters
        .split('')
        .where((l) => !_usedLetters.contains(l))
        .toList();
    if (available.isEmpty) return 'X'; // fallback
    final letter = available[_rng.nextInt(available.length)];
    _usedLetters.add(letter);
    return letter;
  }

  void _releaseLetter(String letter) {
    _usedLetters.remove(letter);
  }

  // ─── Lifecycle ────────────────────────────────────────────────────────

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

    // Start BGM
    _audio.startBgm();

    // Initialize spawn timers (stagger them)
    _obstacleTimer = 1.0;
    _coinTimer = 3.0;
    _platformTimer = 5.0;
    _gapTimer = 8.0;

    // Camera base position
    _cameraBase = camera.viewfinder.position.clone();
  }

  @override
  void update(double dt) {
    super.update(dt);
    if (isGameOver || isPaused) return;

    // Keep BGM alive even if Android audio focus/SFX/TTS interrupts it.
    _audio.ensureBgmPlaying();

    // Screen shake
    _updateShake(dt);

    // ─── Spawn timers ────────────────────────────────────────────────────
    // Obstacles: always ensure at least one is active
    _obstacleTimer -= dt;
    if (_obstacleTimer <= 0 && _countType<ObstacleSprite>() == 0) {
      _spawnObstacle();
      _obstacleTimer = _obstacleDelay;
    }

    // Coins
    _coinTimer -= dt;
    if (_coinTimer <= 0) {
      _spawnCoin();
      _coinTimer = _coinDelay + _rng.nextDouble() * 3;
    }

    // Platforms
    _platformTimer -= dt;
    if (_platformTimer <= 0) {
      _spawnPlatform();
      _platformTimer = _platformDelay + _rng.nextDouble() * 4;
    }

    // Gaps
    _gapTimer -= dt;
    if (_gapTimer <= 0) {
      _spawnGap();
      _gapTimer = _gapDelay + _rng.nextDouble() * 5;
    }

    // ─── Collision detection ────────────────────────────────────────────
    _checkCollisions();

    // ─── Platform scroll tracking ────────────────────────────────────────
    if (_activePlatform != null && _mario.isOnPlatform) {
      if (_activePlatform!.position.x + _activePlatform!.size.x <
          _mario.position.x) {
        // Platform scrolled past Mario — fall off
        _mario.fallOffPlatform();
        _activePlatform = null;
      } else {
        // Update platform ground Y to match scrolling platform
        _mario.updatePlatformGround(_activePlatform!.platformTopY);
      }
    }

    // ─── Cleanup off-screen / consumed targets ──────────────────────────
    _cleanupTargets();
  }

  int _countType<T extends LetterTarget>() {
    return _activeTargets.where((t) => t is T && !t.isConsumed).length;
  }

  // ─── Spawning ─────────────────────────────────────────────────────────

  void _spawnObstacle() {
    if (isGameOver) return;

    final letter = _pickAvailableLetter();
    final obstacle = ObstacleSprite(
      letter: letter,
      speed: gameSpeed,
      groundY: _groundY,
      startX: _screenW + 20,
    );
    add(obstacle);
    _activeTargets.add(obstacle);

    // Speak the letter
    _audio.speakLetter(letter);
  }

  void _spawnCoin() {
    final letter = _pickAvailableLetter();
    final coin = FloatingCoinSprite(
      letter: letter,
      speed: gameSpeed * 0.8,
      groundY: _groundY,
      startX: _screenW + 20,
    );
    add(coin);
    _activeTargets.add(coin);
  }

  void _spawnPlatform() {
    final letter = _pickAvailableLetter();
    final platform = PlatformSprite(
      letter: letter,
      speed: gameSpeed * 0.9,
      groundY: _groundY,
      startX: _screenW + 20,
      blockCount: 3 + _rng.nextInt(3), // 3-5 blocks
    );
    add(platform);
    _activeTargets.add(platform);
  }

  void _spawnGap() {
    final letter = _pickAvailableLetter();
    final gap = GapSprite(
      letter: letter,
      speed: gameSpeed,
      groundY: _groundY,
      startX: _screenW + 20,
      screenHeight: size.y,
    );
    add(gap);
    _activeTargets.add(gap);
  }

  // ─── Input handling ───────────────────────────────────────────────────

  @override
  KeyEventResult onKeyEvent(
    KeyEvent event,
    Set<LogicalKeyboardKey> keysPressed,
  ) {
    if (isGameOver) return KeyEventResult.ignored;
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    final key = event.logicalKey;

    // Space bar → jump
    if (key == LogicalKeyboardKey.space) {
      _mario.jump();
      _audio.playJumpSound();
      return KeyEventResult.handled;
    }

    // Check for letter keys A-Z
    String? typedLetter;
    if (key.keyId >= LogicalKeyboardKey.keyA.keyId &&
        key.keyId <= LogicalKeyboardKey.keyZ.keyId) {
      typedLetter = String.fromCharCode(
        'A'.codeUnitAt(0) + (key.keyId - LogicalKeyboardKey.keyA.keyId),
      );
    }

    if (typedLetter != null) {
      onLetterTyped(typedLetter);
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  /// Public method for on-screen keyboard letter buttons.
  void onLetterTyped(String letter) {
    if (isGameOver) return;
    final upper = letter.toUpperCase();

    // Find matching target (priority: obstacles > coins > platforms > gaps)
    LetterTarget? match;
    for (final target in _activeTargets) {
      if (target.isConsumed) continue;
      // Skip platforms that were already used (letter already triggered)
      if (target is PlatformSprite && target.isUsed) continue;
      if (target.letter.toUpperCase() == upper) {
        if (target is ObstacleSprite) {
          match = target;
          break; // Obstacles have highest priority
        }
        match ??= target;
      }
    }

    if (match != null) {
      _onTargetMatched(match);
    } else {
      _onWrongLetter();
    }
  }

  /// Public method for on-screen space bar (jump button).
  void onSpacePressed() {
    if (isGameOver) return;
    _mario.jump();
    _audio.playJumpSound();
  }

  // ─── Match handling ───────────────────────────────────────────────────

  void _onTargetMatched(LetterTarget target) {
    target.onLetterMatched();

    if (target is ObstacleSprite) {
      _handleObstacleDestroyed(target);
    } else if (target is FloatingCoinSprite) {
      _handleCoinCollected(target);
    } else if (target is PlatformSprite) {
      _handlePlatformJumped(target);
    } else if (target is GapSprite) {
      _handleGapCleared(target);
    }

    _correctStreak++;

    // Encouragement on streaks of 5
    if (_correctStreak >= 5 && _correctStreak % 5 == 0) {
      _audio.playEncouragement();
    }

    // Increase difficulty slightly
    gameSpeed = (gameSpeed + 2).clamp(120, 350);
  }

  void _handleObstacleDestroyed(ObstacleSprite obstacle) {
    _mario.jump();
    _audio.playJumpSound();
    _audio.playStompSound();
    _audio.playCoinSound();

    score += 10;
    _hud.setScore(score);

    // Coin effect
    add(
      CoinEffect(
        position: Vector2(
          obstacle.position.x + obstacle.size.x / 2,
          obstacle.position.y - obstacle.size.y / 2,
        ),
      ),
    );

    // Immediately spawn next obstacle
    _obstacleTimer = 0.5; // tiny delay for the death animation
  }

  void _handleCoinCollected(FloatingCoinSprite coin) {
    _audio.playCoinSound();
    score += 15;
    _hud.setScore(score);

    // Coin effect at coin position
    add(
      CoinEffect(
        position: Vector2(
          coin.position.x + coin.size.x / 2,
          coin.position.y - coin.size.y / 2,
        ),
      ),
    );
  }

  void _handlePlatformJumped(PlatformSprite platform) {
    _mario.jumpToPlatform(platform.platformTopY);
    _activePlatform = platform;
    _audio.playJumpSound();
    score += 5;
    _hud.setScore(score);
  }

  void _handleGapCleared(GapSprite gap) {
    _mario.jump();
    _audio.playJumpSound();
    score += 5;
    _hud.setScore(score);
  }

  /// Gap passed under Mario without letter — shake + bump sound, no life loss.
  void _onGapMissed(GapSprite gap) {
    _correctStreak = 0;
    _shakeScreen();
    _audio.playBumpSound();
  }

  void _onWrongLetter() {
    _correctStreak = 0;
    _shakeScreen();
    _audio.playBumpSound();
  }

  // ─── Collision detection ──────────────────────────────────────────────

  void _checkCollisions() {
    final marioRect = Rect.fromLTWH(
      _mario.position.x + 10,
      _mario.position.y - _mario.size.y + 10,
      _mario.size.x - 20,
      _mario.size.y - 10,
    );

    for (final target in _activeTargets.toList()) {
      if (target.isConsumed) continue;

      // Check coin collision with Mario (jump to collect)
      if (target is FloatingCoinSprite && target.collidesWith(marioRect)) {
        target.onLetterMatched();
        _handleCoinCollected(target);
        _releaseLetter(target.letter);
      }

      // Check obstacle collision with Mario (damage)
      if (target is ObstacleSprite && !target.isDestroyed) {
        if (target.collidesWith(marioRect) && !target.hasPassedMario) {
          target.hasPassedMario = true;
          _onObstacleHitMario(target);
        }
      }

      // Check gap miss: gap hole passed Mario's position without letter being used
      if (target is GapSprite && !target.missTriggered) {
        if (target.gapRight < _mario.position.x) {
          target.markMissed();
          _onGapMissed(target);
          _releaseLetter(target.letter);
        }
      }
    }
  }

  void _onObstacleHitMario(ObstacleSprite obstacle) {
    _correctStreak = 0;
    _audio.playStompSound();
    _loseLife();

    obstacle.destroy();
    _releaseLetter(obstacle.letter);

    // Spawn next obstacle quickly
    _obstacleTimer = 0.5;
  }

  void _loseLife() {
    lives--;
    _hud.setLives(lives);
    _mario.hurt();

    if (lives <= 0) {
      _triggerGameOver();
    }
  }

  // ─── Cleanup ──────────────────────────────────────────────────────────

  void _cleanupTargets() {
    final toRemove = <LetterTarget>[];
    for (final target in _activeTargets) {
      // Remove consumed targets that have finished their animation
      if (target.isConsumed) {
        if (target.parent == null) {
          // Already removed from scene
          toRemove.add(target);
          _releaseLetter(target.letter);
        } else if (target is ObstacleSprite && target.isDestroyed) {
          // Wait for death animation
          if (target.parent == null) {
            toRemove.add(target);
            _releaseLetter(target.letter);
          }
        } else {
          toRemove.add(target);
          _releaseLetter(target.letter);
        }
        continue;
      }

      // Remove targets that scrolled off screen (left side)
      if (target.position.x + target.size.x < -100) {
        toRemove.add(target);
        _releaseLetter(target.letter);

        // If an obstacle passed Mario, it's a hit
        if (target is ObstacleSprite && target.hasPassedMario) {
          // Already handled
        }
      }
    }

    for (final target in toRemove) {
      _activeTargets.remove(target);
      if (target.parent != null) {
        target.removeFromParent();
      }
    }
  }

  // ─── Game over ────────────────────────────────────────────────────────

  void _triggerGameOver() {
    isGameOver = true;
    _mario.die();
    _audio.stopBgm();
    _audio.playGameOverSound();

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
    _audio.stopBgm();
    _audio.dispose();
    super.onRemove();
  }
}
