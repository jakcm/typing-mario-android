import 'dart:math';
import 'package:flame/components.dart';
import 'package:flutter/material.dart';
import '../core/letter_target.dart';
import '../../utils/pixel_painter.dart';

/// A floating coin with a letter that can be collected by typing the letter
/// or by Mario jumping into it.
class FloatingCoinSprite extends LetterTarget {
  final String _letter;
  double speed;
  bool _consumed = false;
  double _time = 0;
  double _opacity = 1.0;
  final double _floatBaseY;

  FloatingCoinSprite({
    required String letter,
    required this.speed,
    required double groundY,
    required double startX,
  }) : _letter = letter,
       _floatBaseY = groundY - 90 - Random().nextDouble() * 40 {
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
    final coinRect = Rect.fromLTWH(
      position.x,
      position.y - size.y,
      size.x,
      size.y,
    );
    return marioBounds.overlaps(coinRect);
  }

  @override
  void update(double dt) {
    super.update(dt);
    if (_consumed) {
      // Quick fade up and disappear
      position.y -= 120 * dt;
      _opacity -= 3 * dt;
      if (_opacity <= 0) removeFromParent();
      return;
    }

    _time += dt;
    // Scroll left
    position.x -= speed * dt;
    // Gentle bob up and down
    position.y = _floatBaseY + sin(_time * 3) * 6;

    // Remove if off screen
    if (position.x + size.x < -50) {
      removeFromParent();
    }
  }

  @override
  void render(Canvas canvas) {
    final a = (_opacity * 255).round().clamp(0, 255);

    // Draw coin pixel art
    PixelPainter.drawCoin(canvas, const Offset(12, 8), 1.0, alpha: a);

    // The coin may fade for a few frames after collection, but its letter must
    // vanish immediately so the released letter cannot appear twice on screen.
    if (!_consumed) {
      final letterPaint = TextPainter(
        text: TextSpan(
          text: _letter.toUpperCase(),
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w900,
            color: Colors.white.withValues(alpha: _opacity.clamp(0.0, 1.0)),
            fontFamily: 'monospace',
            shadows: [
              Shadow(
                offset: const Offset(1, 1),
                color: Colors.black.withValues(alpha: _opacity * 0.8),
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
}
