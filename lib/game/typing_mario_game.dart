import 'dart:math';
import 'package:flame/game.dart';
import 'package:flame/events.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'components/scrolling_background.dart';
import 'components/hud.dart';
import 'components/coin_effect.dart';
import 'core/terrain_system.dart';
import 'sprites/mario_sprite.dart';
import 'sprites/obstacle_sprite.dart';
import 'sprites/floating_coin.dart';
import 'sprites/platform_sprite.dart';
import 'sprites/gap_sprite.dart';
import 'sprites/powerup_sprite.dart';
import 'core/letter_target.dart';
import '../utils/audio_manager.dart';

/// Main game class for Typing Mario.
/// An auto-runner where obstacles, coins, platforms, gaps, and power-ups appear
/// with letters; the player types letters to interact with them.
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
  late TerrainSystem _terrain;
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
  double _powerUpTimer = 0;

  static const double _obstacleDelay = 2.0;
  static const double _coinDelay = 6.0;
  static const double _platformDelay = 10.0;
  static const double _gapDelay = 14.0;
  static const double _powerUpDelay = 18.0; // 18-28s between power-ups

  // Screen dimensions (cached)
  late double _screenW;
  late double _groundY;

  static const String _allLetters = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ';

  // Active platform Mario is standing on (null = on ground)
  PlatformSprite? _activePlatform;

  // ─── Power-up / effect timers ─────────────────────────────────────────
  double _invincibleTimer = 0; // seconds remaining
  double _slowTimer = 0; // seconds remaining

  // ─── Theme tracking ──────────────────────────────────────────────────
  int _lastThemeScore = 0; // score at last theme switch
  static const int _themeScoreInterval = 100; // switch every 100 points

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

    // Terrain system
    _terrain = TerrainSystem(baseGroundY: _groundY, screenHeight: size.y);
    _terrain.init(_screenW);

    // Background (now needs terrain reference)
    _background = ScrollingBackground(terrainSystem: _terrain);
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
    _powerUpTimer = 12.0;

    // Camera base position
    _cameraBase = camera.viewfinder.position.clone();
  }

  @override
  void update(double dt) {
    super.update(dt);
    if (isGameOver || isPaused) return;

    // Keep BGM alive
    _audio.ensureBgmPlaying();

    // Screen shake
    _updateShake(dt);

    // ─── Terrain system ─────────────────────────────────────────────────
    _terrain.update(dt, gameSpeed);

    // Update Mario's ground Y based on terrain at his position
    final marioTerrainY = _terrain.getGroundYAt(_mario.position.x);
    _mario.updateDynamicGround(marioTerrainY);
    _groundY = marioTerrainY; // update for spawning reference

    // ─── Effect timers ──────────────────────────────────────────────────
    if (_invincibleTimer > 0) {
      _invincibleTimer -= dt;
      if (_invincibleTimer <= 0) {
        _invincibleTimer = 0;
        _mario.setInvincible(false);
      }
    }
    if (_slowTimer > 0) {
      _slowTimer -= dt;
      if (_slowTimer <= 0) {
        _slowTimer = 0;
      }
    }

    // ─── Theme switching by score ───────────────────────────────────────
    if (score - _lastThemeScore >= _themeScoreInterval) {
      _lastThemeScore = score;
      _background!.switchTheme(_background!.getNextTheme());
    }

    // ─── Update HUD power-up timers ────────────────────────────────────
    _hud.setPowerUpTimers(
      invincible: _invincibleTimer,
      slow: _slowTimer,
    );

    // ─── Spawn timers ───────────────────────────────────────────────────
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

    // Power-ups
    _powerUpTimer -= dt;
    if (_powerUpTimer <= 0) {
      _spawnPowerUp();
      _powerUpTimer = _powerUpDelay + _rng.nextDouble() * 10;
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
    final obsGroundY = _terrain.getGroundYAt(_screenW + 20);
    final obstacle = ObstacleSprite(
      letter: letter,
      speed: _effectiveSpeed(gameSpeed),
      groundY: obsGroundY,
      startX: _screenW + 20,
    );
    add(obstacle);
    _activeTargets.add(obstacle);

    // Speak the letter
    _audio.speakLetter(letter);
  }

  void _spawnCoin() {
    final letter = _pickAvailableLetter();
    final coinGroundY = _terrain.getGroundYAt(_screenW + 20);
    final coin = FloatingCoinSprite(
      letter: letter,
      speed: _effectiveSpeed(gameSpeed * 0.8),
      groundY: coinGroundY,
      startX: _screenW + 20,
    );
    add(coin);
    _activeTargets.add(coin);
  }

  void _spawnPlatform() {
    final letter = _pickAvailableLetter();
    final platGroundY = _terrain.getGroundYAt(_screenW + 20);

    // Multi-layer: weighted random selection
    final layerRoll = _rng.nextDouble();
    final layer = layerRoll < 0.6 ? 1 : (layerRoll < 0.9 ? 2 : 3);

    // 25% chance of moving platform
    final isMoving = _rng.nextDouble() < 0.25;

    final platform = PlatformSprite(
      letter: letter,
      speed: _effectiveSpeed(gameSpeed * 0.9),
      groundY: platGroundY,
      startX: _screenW + 20,
      blockCount: 3 + _rng.nextInt(3), // 3-5 blocks
      layer: layer,
      isMoving: isMoving,
      moveRange: 30 + _rng.nextDouble() * 20,
      moveSpeed: 1.0 + _rng.nextDouble() * 1.0,
    );
    add(platform);
    _activeTargets.add(platform);
  }

  void _spawnGap() {
    final letter = _pickAvailableLetter();
    final gapGroundY = _terrain.getGroundYAt(_screenW + 20);
    final gap = GapSprite(
      letter: letter,
      speed: _effectiveSpeed(gameSpeed),
      groundY: gapGroundY,
      startX: _screenW + 20,
      screenHeight: size.y,
    );
    add(gap);
    _activeTargets.add(gap);
  }

  void _spawnPowerUp() {
    if (isGameOver) return;
    if (_countType<PowerUpSprite>() >= 1) return; // max 1 on screen

    final letter = _pickAvailableLetter();
    final puGroundY = _terrain.getGroundYAt(_screenW + 20);

    // Random type selection
    final types = PowerUpType.values;
    final type = types[_rng.nextInt(types.length)];

    final powerUp = PowerUpSprite(
      letter: letter,
      speed: _effectiveSpeed(gameSpeed * 0.75),
      groundY: puGroundY,
      startX: _screenW + 20,
      type: type,
    );
    add(powerUp);
    _activeTargets.add(powerUp);
  }

  /// Get effective speed accounting for slow effect.
  double _effectiveSpeed(double baseSpeed) {
    return _slowTimer > 0 ? baseSpeed * 0.5 : baseSpeed;
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

    // Find matching target (priority: obstacles > power-ups > coins > platforms > gaps)
    LetterTarget? match;
    for (final target in _activeTargets) {
      if (target.isConsumed) continue;
      if (target is PlatformSprite && target.isUsed) continue;
      if (target.letter.toUpperCase() == upper) {
        if (target is ObstacleSprite) {
          match = target;
          break; // Obstacles have highest priority
        }
        if (target is PowerUpSprite) {
          match = target;
          break; // Power-ups second priority (urgent to collect)
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
    } else if (target is PowerUpSprite) {
      _handlePowerUpCollected(target);
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
    _obstacleTimer = 0.5;
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

  void _handlePowerUpCollected(PowerUpSprite powerUp) {
    _audio.playPowerUpSound();

    switch (powerUp.type) {
      case PowerUpType.star:
        // 10 seconds of invincibility
        _invincibleTimer = 10.0;
        _mario.setInvincible(true);
        break;
      case PowerUpType.mushroom:
        // Extra life
        lives++;
        _hud.setLives(lives);
        _audio.playOneUpSound();
        break;
      case PowerUpType.coinRain:
        // Batch score
        score += 50;
        _hud.setScore(score);
        // Triple coin effect
        for (int i = 0; i < 3; i++) {
          add(CoinEffect(
            position: Vector2(
              powerUp.position.x + _rng.nextDouble() * 40 - 20,
              powerUp.position.y - 30 - _rng.nextDouble() * 30,
            ),
          ));
        }
        break;
      case PowerUpType.speedBoots:
        // 8 seconds slow obstacles
        _slowTimer = 8.0;
        break;
    }

    score += 20; // bonus for collecting any power-up
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

      // Check power-up collision with Mario (jump to collect)
      if (target is PowerUpSprite && target.collidesWith(marioRect)) {
        target.onLetterMatched();
        _handlePowerUpCollected(target);
        _releaseLetter(target.letter);
      }

      // Check obstacle collision with Mario (damage or invincibility destroy)
      if (target is ObstacleSprite && !target.isDestroyed) {
        if (target.collidesWith(marioRect) && !target.hasPassedMario) {
          target.hasPassedMario = true;

          if (_invincibleTimer > 0) {
            // Invincible: destroy obstacle without taking damage
            target.destroy();
            _releaseLetter(target.letter);
            score += 15;
            _hud.setScore(score);
            _audio.playStompSound();
            _obstacleTimer = 0.5;
          } else {
            _onObstacleHitMario(target);
          }
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
          toRemove.add(target);
          _releaseLetter(target.letter);
        } else if (target is ObstacleSprite && target.isDestroyed) {
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
