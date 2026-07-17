import 'dart:math';
import 'package:flame/components.dart';
import 'package:flutter/material.dart';
import '../core/letter_target.dart';
import '../../utils/pixel_painter.dart';

/// Power-up types with distinct effects.
enum PowerUpType { star, mushroom, coinRain, speedBoots }

/// A power-up collectible with a letter that activates its effect when typed.
class PowerUpSprite extends LetterTarget {
  final String _letter;
  double speed;
  final PowerUpType type;
  bool _consumed = false;
  double _time = 0;
  double _opacity = 1.0;
  final double _floatBaseY;

  PowerUpSprite({
    required String letter,
    required this.speed,
    required double groundY,
    required double startX,
    required this.type,
  }) : _letter = letter,
       _floatBaseY = groundY - 80 - Random().nextDouble() * 60 {
    size = Vector2(48, 60);
    anchor = Anchor.bottomLeft;
    position = Vector2(startX, _floatBaseY);
  }

  @override
  String get letter => _letter;

  @override
  bool get isConsumed => _consumed;

  @override
  void onLetterMatched() {
    if (_consumed) return;
    _consumed = true;
  }

  @override
  bool collidesWith(Rect marioBounds) {
    if (_consumed) return false;
    final rect = Rect.fromLTWH(position.x, position.y - size.y, size.x, size.y);
    return marioBounds.overlaps(rect);
  }

  @override
  void update(double dt) {
    super.update(dt);
    if (_consumed) {
      position.y -= 120 * dt;
      _opacity -= 3 * dt;
      if (_opacity <= 0) removeFromParent();
      return;
    }

    _time += dt;
    position.x -= speed * dt;
    // Float bob (slightly larger amplitude than coins)
    position.y = _floatBaseY + sin(_time * 2.5) * 10;

    if (position.x + size.x < -50) {
      removeFromParent();
    }
  }

  @override
  void render(Canvas canvas) {
    final a = (_opacity * 255).round().clamp(0, 255);

    // Draw glow halo for star type
    if (type == PowerUpType.star) {
      final glowAlpha = (80 + 40 * sin(_time * 6)).round().clamp(0, 255);
      PixelPainter.drawInvincRing(
        canvas,
        const Offset(4, -6),
        1.5,
        alpha: (glowAlpha * _opacity).round().clamp(0, 255),
      );
    }

    // Draw the power-up icon
    switch (type) {
      case PowerUpType.star:
        PixelPainter.drawStar(canvas, const Offset(12, 8), 1.2, alpha: a);
        break;
      case PowerUpType.mushroom:
        PixelPainter.drawMushroom(canvas, const Offset(10, 6), 1.1, alpha: a);
        break;
      case PowerUpType.coinRain:
        PixelPainter.drawCoin(canvas, const Offset(4, 8), 1.0, alpha: a);
        PixelPainter.drawCoin(canvas, const Offset(20, 4), 0.8, alpha: a);
        PixelPainter.drawCoin(canvas, const Offset(14, 12), 0.8, alpha: a);
        break;
      case PowerUpType.speedBoots:
        PixelPainter.drawBoots(canvas, const Offset(12, 6), 1.1, alpha: a);
        break;
    }

    // Hide the letter as soon as collected, even while the icon fades out.
    // This allows its letter to be safely released to the next target.
    if (!_consumed) {
      final letterPaint = TextPainter(
        text: TextSpan(
          text: _letter.toUpperCase(),
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w900,
            color: _letterColor.withAlpha(a),
            fontFamily: 'monospace',
            shadows: [
              Shadow(
                offset: const Offset(1, 1),
                color: Colors.black.withAlpha((a * 0.8).round().clamp(0, 255)),
              ),
            ],
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      letterPaint.paint(
        canvas,
        Offset(
          (size.x - letterPaint.width) / 2,
          size.y - letterPaint.height - 2,
        ),
      );
    }
  }

  Color get _letterColor {
    switch (type) {
      case PowerUpType.star:
        return Colors.yellow.shade700;
      case PowerUpType.mushroom:
        return Colors.red.shade400;
      case PowerUpType.coinRain:
        return Colors.amber.shade600;
      case PowerUpType.speedBoots:
        return Colors.blue.shade300;
    }
  }
}
