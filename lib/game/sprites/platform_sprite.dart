import 'dart:math';
import 'package:flame/components.dart';
import 'package:flutter/material.dart';
import '../core/letter_target.dart';

/// A floating platform made of brick blocks.
/// Supports multi-layer positioning and optional up/down movement.
class PlatformSprite extends LetterTarget {
  String _activeLetter;
  final double speed;
  final int blockCount;
  final int layer; // 1=low, 2=mid, 3=high
  final bool isMoving;
  final double moveRange;
  final double moveSpeed;
  bool _consumed = false;
  bool _used = false; // letter already matched, can't trigger again
  static const double _blockSize = 32.0;

  // Movement state
  double _moveTime = 0;
  late final double _baseY;

  // Colors per layer
  static const Color _brickColorLow = Color(0xFFD2691E);
  static const Color _brickColorMid = Color(0xFFE0A060);
  static const Color _brickColorHigh = Color(0xFFF0C890);
  static const Color _brickDark = Color(0xFF8B4513);
  static const Color _brickLight = Color(0xFFDEB887);
  static const Color _mortar = Color(0xFFA0522D);

  PlatformSprite({
    required String letter,
    required this.speed,
    required double groundY,
    required double startX,
    this.blockCount = 4,
    this.layer = 1,
    this.isMoving = false,
    this.moveRange = 40,
    this.moveSpeed = 1.5,
  }) : _activeLetter = letter {
    size = Vector2(_blockSize * blockCount, _blockSize);
    anchor = Anchor.bottomLeft;

    // Calculate Y based on layer
    final layerOffset = switch (layer) {
      1 => 60.0 + Random().nextDouble() * 30,  // low
      2 => 120.0 + Random().nextDouble() * 30, // mid
      3 => 180.0 + Random().nextDouble() * 30, // high
      _ => 60.0,
    };
    _baseY = groundY - layerOffset;
    position = Vector2(startX, _baseY);
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

    // Up/down movement
    if (isMoving) {
      _moveTime += dt;
      position.y = _baseY + sin(_moveTime * moveSpeed) * moveRange;
    }

    // Remove if off screen
    if (position.x + size.x < -50) {
      removeFromParent();
    }
  }

  @override
  void render(Canvas canvas) {
    // Select brick color based on layer
    final brickColor = switch (layer) {
      1 => _brickColorLow,
      2 => _brickColorMid,
      3 => _brickColorHigh,
      _ => _brickColorLow,
    };

    for (int i = 0; i < blockCount; i++) {
      final x = i * _blockSize;
      _drawBrick(canvas, Offset(x, 0), _blockSize, brickColor);
    }

    // Moving indicator: small arrows on the platform
    if (isMoving) {
      final arrowPaint = Paint()..color = const Color(0x88FFFFFF);
      // Up arrow
      final cx = size.x / 2;
      final path = Path()
        ..moveTo(cx - 6, -8)
        ..lineTo(cx, -14)
        ..lineTo(cx + 6, -8)
        ..close();
      canvas.drawPath(path, arrowPaint);
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
                color: Colors.black.withAlpha(178),
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
      // Used state: show checkmark
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

  void _drawBrick(Canvas canvas, Offset pos, double s, Color brickColor) {
    final rect = RRect.fromRectAndRadius(
      Rect.fromLTWH(pos.dx, pos.dy, s, s),
      const Radius.circular(2),
    );
    canvas.drawRRect(rect, Paint()..color = brickColor);
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
