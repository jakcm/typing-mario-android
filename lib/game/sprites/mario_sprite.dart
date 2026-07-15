import 'package:flame/components.dart';
import 'package:flutter/material.dart';
import '../../utils/pixel_painter.dart';

/// Mario states
enum MarioState { running, jumping, hurt, dead, idle }

/// Mario sprite component drawn programmatically with pixel art.
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
      if (position.y >= _groundY) {
        position.y = _groundY;
        state = MarioState.running;
        _jumpVelocity = 0;
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
  }

  @override
  void render(Canvas canvas) {
    if (!_visible && state == MarioState.hurt) return;
    if (state == MarioState.dead) return;

    final scale = 1.0;

    // Draw shadow under Mario
    final shadowPaint = Paint()..color = Colors.black.withValues(alpha: 0.2);
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(size.x / 2, size.y - 2),
        width: 40,
        height: 8,
      ),
      shadowPaint,
    );

    PixelPainter.drawMario(
      canvas,
      Offset(8, 4),
      scale,
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
  }

  double get leftEdge => position.x;
  double get rightEdge => position.x + size.x;
}
