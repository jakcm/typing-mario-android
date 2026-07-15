import 'dart:math';
import 'package:flame/components.dart';
import 'package:flutter/material.dart';
import '../../utils/pixel_painter.dart';

/// Coin particle effect that flies up and fades out when a letter is correct.
/// Uses simple alpha blending instead of saveLayer for performance.
class CoinEffect extends PositionComponent with HasGameReference {
  double _timer = 0;
  final double _duration = 1.0;
  final List<_CoinParticle> _particles = [];

  CoinEffect({required Vector2 position}) {
    this.position = position;
    size = Vector2(40, 40);
    anchor = Anchor.center;
  }

  @override
  Future<void> onLoad() async {
    super.onLoad();
    final rng = Random();
    // Create 5 coin particles
    for (int i = 0; i < 5; i++) {
      _particles.add(_CoinParticle(
        offsetX: 0,
        offsetY: 0,
        velocityX: (rng.nextDouble() - 0.5) * 60,
        velocityY: -(rng.nextDouble() * 100 + 60),
        rotationSpeed: (rng.nextDouble() - 0.5) * 6,
        scale: 0.7 + rng.nextDouble() * 0.4,
      ));
    }
  }

  @override
  void update(double dt) {
    super.update(dt);
    _timer += dt;
    if (_timer >= _duration) {
      removeFromParent();
      return;
    }
    for (final p in _particles) {
      p.offsetX += p.velocityX * dt;
      p.offsetY += p.velocityY * dt;
      p.velocityY += 200 * dt; // gravity
      p.rotation += p.rotationSpeed * dt;
    }
  }

  @override
  void render(Canvas canvas) {
    final opacity = 1.0 - (_timer / _duration);
    if (opacity <= 0) return;
    final alpha = (opacity * 255).toInt();

    for (final p in _particles) {
      canvas.save();
      canvas.translate(p.offsetX, p.offsetY);
      canvas.rotate(p.rotation);
      // Draw coin with alpha — no saveLayer, much faster
      PixelPainter.drawCoin(
        canvas,
        Offset(-12 * p.scale, -12 * p.scale),
        p.scale,
        alpha: alpha,
      );
      canvas.restore();
    }
  }
}

class _CoinParticle {
  double offsetX;
  double offsetY;
  double velocityX;
  double velocityY;
  double rotationSpeed;
  double rotation = 0;
  double scale;

  _CoinParticle({
    required this.offsetX,
    required this.offsetY,
    required this.velocityX,
    required this.velocityY,
    required this.rotationSpeed,
    required this.scale,
  });
}
