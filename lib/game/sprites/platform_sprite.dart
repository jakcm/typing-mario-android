import 'dart:math';
import 'package:flame/components.dart';
import 'package:flutter/material.dart';
import '../core/letter_target.dart';

/// A floating platform made of brick blocks.
/// The first brick displays a letter. Pressing the letter makes Mario jump onto it.
/// The platform stays visible and continues scrolling after use.
class PlatformSprite extends LetterTarget {
  String _activeLetter;
  final double speed;
  final int blockCount;
  bool _consumed = false;
  bool _used = false; // letter already matched, can't trigger again
  static const double _blockSize = 32.0;

  // Colors
  static const Color _brickColor = Color(0xFFD2691E);
  static const Color _brickDark = Color(0xFF8B4513);
  static const Color _brickLight = Color(0xFFDEB887);
  static const Color _mortar = Color(0xFFA0522D);

  PlatformSprite({
    required String letter,
    required this.speed,
    required double groundY,
    required double startX,
    this.blockCount = 4,
  }) : _activeLetter = letter {
    size = Vector2(_blockSize * blockCount, _blockSize);
    anchor = Anchor.bottomLeft;
    position = Vector2(startX, groundY - 60 - Random().nextDouble() * 30);
  }

  @override
  String get letter => _activeLetter;

  @override
  bool get isConsumed => _consumed;

  bool get isUsed => _used;

  /// When letter matched: mark as used. Don't consume — platform stays visible.
  @override
  void onLetterMatched() {
    if (_used) return;
    _used = true;
    // Keep _activeLetter intact for cleanup; guard in game layer prevents re-matching
  }

  @override
  bool collidesWith(Rect marioBounds) {
    if (_consumed) return false;
    final platRect = Rect.fromLTWH(
      position.x,
      position.y - size.y,
      size.x,
      size.y,
    );
    return marioBounds.overlaps(platRect);
  }

  @override
  void update(double dt) {
    super.update(dt);
    // Scroll left
    position.x -= speed * dt;

    // Remove if off screen
    if (position.x + size.x < -50) {
      removeFromParent();
    }
  }

  @override
  void render(Canvas canvas) {
    for (int i = 0; i < blockCount; i++) {
      final x = i * _blockSize;
      _drawBrick(canvas, Offset(x, 0), _blockSize);
    }

    // Draw letter on first brick (only if not yet used)
    if (!_used) {
      final letterPaint = TextPainter(
        text: TextSpan(
          text: _activeLetter.toUpperCase(),
          style: TextStyle(
            fontSize: _blockSize * 0.65,
            fontWeight: FontWeight.w900,
            color: Colors.white,
            fontFamily: 'monospace',
            shadows: [
              Shadow(
                offset: const Offset(1, 1),
                color: Colors.black.withValues(alpha: 0.7),
              ),
            ],
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      letterPaint.paint(
        canvas,
        Offset(
          (_blockSize - letterPaint.width) / 2,
          (_blockSize - letterPaint.height) / 2,
        ),
      );
    } else {
      // Used state: show checkmark or dimmed indicator
      final usedPaint = TextPainter(
        text: const TextSpan(
          text: '✓',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w900,
            color: Color(0x88FFFFFF),
            fontFamily: 'monospace',
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      usedPaint.paint(
        canvas,
        Offset(
          (_blockSize - usedPaint.width) / 2,
          (_blockSize - usedPaint.height) / 2,
        ),
      );
    }
  }

  void _drawBrick(Canvas canvas, Offset pos, double s) {
    final rect = RRect.fromRectAndRadius(
      Rect.fromLTWH(pos.dx, pos.dy, s, s),
      const Radius.circular(2),
    );
    canvas.drawRRect(rect, Paint()..color = _brickColor);
    canvas.drawRect(
      Rect.fromLTWH(pos.dx + 2, pos.dy + s * 0.33, s - 4, 2),
      Paint()..color = _mortar,
    );
    canvas.drawRect(
      Rect.fromLTWH(pos.dx + 2, pos.dy + s * 0.66, s - 4, 2),
      Paint()..color = _mortar,
    );
    canvas.drawRect(
      Rect.fromLTWH(pos.dx + s * 0.5 - 1, pos.dy + 2, 2, s * 0.33 - 2),
      Paint()..color = _mortar,
    );
    canvas.drawRect(
      Rect.fromLTWH(pos.dx + s * 0.25 - 1, pos.dy + s * 0.35, 2, s * 0.31 - 2),
      Paint()..color = _mortar,
    );
    canvas.drawRect(
      Rect.fromLTWH(pos.dx + s * 0.75 - 1, pos.dy + s * 0.35, 2, s * 0.31 - 2),
      Paint()..color = _mortar,
    );
    canvas.drawRect(
      Rect.fromLTWH(pos.dx + s * 0.5 - 1, pos.dy + s * 0.68, 2, s * 0.30 - 2),
      Paint()..color = _mortar,
    );
    canvas.drawRect(
      Rect.fromLTWH(pos.dx, pos.dy, s, 2),
      Paint()..color = _brickLight,
    );
    canvas.drawRect(
      Rect.fromLTWH(pos.dx, pos.dy + s - 2, s, 2),
      Paint()..color = _brickDark,
    );
    canvas.drawRRect(rect, Paint()
      ..color = _brickDark
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1);
  }

  double get platformTopY => position.y - size.y;
}
