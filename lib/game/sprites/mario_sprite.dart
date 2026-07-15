import 'dart:math';
import 'package:flame/components.dart';
import 'package:flutter/material.dart';
import '../../utils/pixel_painter.dart';

/// Mario states
enum MarioState { running, jumping, hurt, dead, idle }

/// Mario sprite component drawn programmatically with pixel art.
/// Supports platform landing: when on a platform, the platform's top Y
/// acts as a temporary ground level. When the platform scrolls past,
/// Mario falls back to the real ground.
class MarioSprite extends PositionComponent with HasGameReference {
  MarioState state = MarioState.idle;
  int _frame = 0;
  double _frameTimer = 0;
  double _jumpVelocity = 0;
  double _groundY = 0;
  double _hurtTimer = 0;
  double _blinkTimer = 0;
  bool _visible = true;
  static const double _gravity = 900;
  static const double _jumpForce = -420;
  static const double _frameInterval = 0.15;

  // Platform support
  double? _platformGroundY; // When set, Mario stands on this Y instead of _groundY

  // Invincibility visual state
  bool isInvincible = false;
  double _invincBlinkTimer = 0;
  bool _invincVisible = true;

  MarioSprite({required double groundY}) {
    _groundY = groundY;
    size = Vector2(60, 64);
    anchor = Anchor.bottomLeft;
    position = Vector2(100, groundY);
  }

  @override
  void update(double dt) {
    super.update(dt);

    // Frame animation for running
    if (state == MarioState.running) {
      _frameTimer += dt;
      if (_frameTimer >= _frameInterval) {
        _frameTimer = 0;
        _frame = (_frame + 1) % 2;
      }
    }

    // Jump physics
    if (state == MarioState.jumping) {
      _jumpVelocity += _gravity * dt;
      position.y += _jumpVelocity * dt;

      // Check platform landing first (only when falling and platform is set)
      if (_platformGroundY != null && _jumpVelocity > 0 && position.y >= _platformGroundY!) {
        position.y = _platformGroundY!;
        state = MarioState.running;
        _jumpVelocity = 0;
      }
      // Check real ground landing
      else if (position.y >= _groundY) {
        position.y = _groundY;
        state = MarioState.running;
        _jumpVelocity = 0;
        _platformGroundY = null; // Clear platform when hitting real ground
      }
    }

    // Hurt blink
    if (state == MarioState.hurt) {
      _hurtTimer -= dt;
      _blinkTimer += dt;
      if (_blinkTimer >= 0.1) {
        _blinkTimer = 0;
        _visible = !_visible;
      }
      if (_hurtTimer <= 0) {
        state = MarioState.running;
        _visible = true;
      }
    }

    // Invincibility blink (overrides hurt blink for visibility)
    if (isInvincible) {
      _invincBlinkTimer += dt;
      _invincVisible = (sin(_invincBlinkTimer * 8) > -0.3);
    }
  }

  @override
  void render(Canvas canvas) {
    if (!_visible && state == MarioState.hurt) return;
    if (state == MarioState.dead) return;

    // Draw shadow under Mario
    final shadowPaint = Paint()..color = Colors.black.withAlpha(50);
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(size.x / 2, size.y - 2),
        width: 40,
        height: 8,
      ),
      shadowPaint,
    );

    // Invincibility golden glow effect
    if (isInvincible && _invincVisible) {
      final glowAlpha = (120 + 80 * sin(_invincBlinkTimer * 10)).round().clamp(0, 255);
      final glowPaint = Paint()
        ..color = Color.fromARGB(glowAlpha, 255, 215, 0) // gold
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(size.x / 2, size.y / 2),
          width: 56,
          height: 60,
        ),
        glowPaint,
      );
    }

    PixelPainter.drawMario(
      canvas,
      Offset(8, 4),
      1.0,
      frame: state == MarioState.jumping ? 1 : _frame,
    );
  }

  /// Make Mario jump.
  void jump() {
    if (state == MarioState.jumping && _jumpVelocity > 0) {
      // Allow double jump for gameplay feel
      _jumpVelocity = _jumpForce * 0.7;
      return;
    }
    state = MarioState.jumping;
    _jumpVelocity = _jumpForce;
  }

  /// Jump to a specific platform height. Calculates the jump force needed
  /// to reach the platform's top Y, then sets it as the landing target.
  void jumpToPlatform(double platformTopY) {
    state = MarioState.jumping;
    // v = -sqrt(2 * g * h), add margin so Mario slightly overshoots
    final heightDiff = _groundY - platformTopY;
    if (heightDiff > 0) {
      _jumpVelocity = -sqrt(2 * _gravity * (heightDiff + 15));
    } else {
      _jumpVelocity = _jumpForce;
    }
    _platformGroundY = platformTopY;
  }

  /// Update the platform ground Y (called by game each frame while on platform).
  void updatePlatformGround(double? y) {
    _platformGroundY = y;
  }

  /// Update the dynamic terrain ground Y each frame.
  /// When Mario is running on ground (not on a platform), his ground level
  /// follows the terrain. Handles up-steps (auto-climb) and down-steps (fall).
  void updateDynamicGround(double terrainGroundY) {
    if (_platformGroundY != null) return; // on a platform, ignore terrain

    if (state != MarioState.jumping) {
      final prevGround = _groundY;
      _groundY = terrainGroundY;

      // Going downhill: Mario needs to "fall" to the new ground
      if (terrainGroundY > prevGround + 5 && position.y < terrainGroundY - 2) {
        state = MarioState.jumping;
        _jumpVelocity = 50; // gentle downward
      }
      // Going uphill: snap Mario to new ground
      else {
        position.y = terrainGroundY;
      }
    } else {
      // While jumping, still update ground for landing
      _groundY = terrainGroundY;
    }
  }

  /// Set or clear invincibility state.
  void setInvincible(bool active) {
    isInvincible = active;
    if (active) {
      _invincBlinkTimer = 0;
      _invincVisible = true;
    } else {
      _invincVisible = true;
    }
  }

  /// Mario falls off the platform (when platform scrolls past).
  void fallOffPlatform() {
    if (_platformGroundY != null) {
      _platformGroundY = null;
      state = MarioState.jumping;
      _jumpVelocity = 0; // Start falling from current position
    }
  }

  bool get isOnPlatform => _platformGroundY != null;

  /// Play hurt animation.
  void hurt() {
    if (state == MarioState.hurt) return;
    state = MarioState.hurt;
    _hurtTimer = 1.0;
    _blinkTimer = 0;
    _visible = false;
  }

  /// Play death animation.
  void die() {
    state = MarioState.dead;
  }

  /// Set running state.
  void setRunning() {
    if (state != MarioState.jumping && state != MarioState.hurt) {
      state = MarioState.running;
    }
  }

  /// Reset Mario to starting position.
  void resetPosition() {
    position = Vector2(100, _groundY);
    state = MarioState.idle;
    _jumpVelocity = 0;
    _visible = true;
    _platformGroundY = null;
  }

  double get leftEdge => position.x;
  double get rightEdge => position.x + size.x;
}
