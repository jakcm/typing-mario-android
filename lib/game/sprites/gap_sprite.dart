import 'package:flame/components.dart';
import 'package:flutter/material.dart';
import '../core/letter_target.dart';

/// A gap (hole) in the ground. The landing brick on the right side shows a letter.
/// Pressing the letter makes Mario jump over the gap to the landing brick.
/// If NOT pressed, the gap passes under Mario with a bump effect (no life loss).
class GapSprite extends LetterTarget {
  String _activeLetter;
  final double speed;
  bool _consumed = false;
  bool _missTriggered = false;
  static const double gapWidth = 120.0;
  static const double brickSize = 32.0;

  static const Color _gapColor = Color(0xFF0a0a1a);
  static const Color _gapEdge = Color(0xFF4a3520);
  static const Color _brickColor = Color(0xFFD2691E);
  static const Color _brickDark = Color(0xFF8B4513);
  static const Color _brickLight = Color(0xFFDEB887);
  static const Color _mortar = Color(0xFFA0522D);

  GapSprite({
    required String letter,
    required this.speed,
    required double groundY,
    required double startX,
    required double screenHeight,
  })  : _activeLetter = letter {
    // Component covers the gap hole + landing brick at ground level
    final groundDepth = screenHeight - groundY;
    size = Vector2(gapWidth + brickSize, groundDepth);
    anchor = Anchor.topLeft;
    position = Vector2(startX, groundY);
  }

  @override
  String get letter => _activeLetter;

  @override
  bool get isConsumed => _consumed;

  bool get missTriggered => _missTriggered;

  /// Mark the gap as "missed" — fire bump effect but don't consume (gap keeps rendering).
  void markMissed() {
    _missTriggered = true;
    _consumed = true;
    _activeLetter = '';
  }

  @override
  void onLetterMatched() {
    if (_consumed) return;
    _consumed = true;
    _activeLetter = '';
  }

  @override
  bool collidesWith(Rect marioBounds) {
    // Not used for gap — gap miss is detected by position comparison
    return false;
  }

  /// Left edge of the gap hole (world X).
  double get gapLeft => position.x;

  /// Right edge of the gap hole (world X).
  double get gapRight => position.x + gapWidth;

  @override
  void update(double dt) {
    super.update(dt);
    position.x -= speed * dt;

    if (position.x + size.x < -50) {
      removeFromParent();
    }
  }

  @override
  void render(Canvas canvas) {
    final groundDepth = size.y;

    // ─── Gap hole (dark void replacing the ground) ────────────────────
    canvas.drawRect(
      Rect.fromLTWH(0, 0, gapWidth, groundDepth),
      Paint()..color = _gapColor,
    );

    // Left edge (earth/cliff side)
    canvas.drawRect(
      Rect.fromLTWH(0, 0, 4, groundDepth),
      Paint()..color = _gapEdge,
    );
    // Right edge
    canvas.drawRect(
      Rect.fromLTWH(gapWidth - 4, 0, 4, groundDepth),
      Paint()..color = _gapEdge,
    );
    // Top grass edge
    canvas.drawRect(
      Rect.fromLTWH(0, 0, gapWidth, 3),
      Paint()..color = const Color(0xFF228B22),
    );
    // Depth shading (subtle gradient lines)
    for (double y = 10; y < groundDepth; y += 15) {
      final a = ((y / groundDepth) * 40).round().clamp(0, 40);
      canvas.drawRect(
        Rect.fromLTWH(4, y, gapWidth - 8, 1),
        Paint()..color = Color.fromARGB(a, 255, 255, 255),
      );
    }

    // ─── Landing brick (right side of gap, at ground surface) ─────────
    _drawBrick(canvas, Offset(gapWidth, 0), brickSize);

    // Letter on the brick
    if (!_consumed) {
      final letterPaint = TextPainter(
        text: TextSpan(
          text: _activeLetter.toUpperCase(),
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w900,
            color: Colors.yellow,
            fontFamily: 'monospace',
            shadows: [
              Shadow(offset: Offset(1, 1), color: Colors.black),
            ],
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      letterPaint.paint(
        canvas,
        Offset(
          gapWidth + (brickSize - letterPaint.width) / 2,
          (brickSize - letterPaint.height) / 2,
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
}
