import 'dart:math';
import 'package:flame/components.dart';
import 'package:flutter/material.dart';

/// Floating letter bubble that appears above an obstacle.
/// Shows both uppercase and lowercase versions with a pulse animation.
/// Caches TextPainters for performance.
class LetterBubble extends PositionComponent with HasGameReference {
  final String letter;
  bool isVisible = true;
  double _time = 0;

  // Cached painters
  late TextPainter _upperPainter;
  late TextPainter _lowerPainter;
  bool _paintersReady = false;

  LetterBubble({required this.letter}) {
    size = Vector2(80, 50);
    anchor = Anchor.center;
  }

  void _buildPainters() {
    if (_paintersReady) return;
    _paintersReady = true;

    final upper = letter.toUpperCase();
    final lower = letter.toLowerCase();

    _upperPainter = TextPainter(
      text: TextSpan(
        text: upper,
        style: TextStyle(
          fontSize: 28,
          fontWeight: FontWeight.w900,
          color: Colors.white,
          fontFamily: 'monospace',
          shadows: [
            Shadow(
              offset: const Offset(1, 1),
              color: Colors.black.withValues(alpha: 0.5),
            ),
          ],
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    _upperPainter.layout();

    _lowerPainter = TextPainter(
      text: TextSpan(
        text: lower,
        style: const TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w700,
          color: Color(0xFFFFD600),
          fontFamily: 'monospace',
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    _lowerPainter.layout();
  }

  @override
  void update(double dt) {
    super.update(dt);
    _time += dt;
    // Gentle bob up and down
    final bobOffset = sin(_time * 3) * 3;
    position.y = -60 + bobOffset;
  }

  @override
  void render(Canvas canvas) {
    if (!isVisible) return;

    _buildPainters(); // Build once, cached

    // Pulse scale effect
    final pulse = 1.0 + sin(_time * 4) * 0.08;

    canvas.save();
    // Apply pulse from center
    final cx = size.x / 2;
    final cy = size.y / 2;
    canvas.translate(cx, cy);
    canvas.scale(pulse, pulse);
    canvas.translate(-cx, -cy);

    // Bubble background with rounded rectangle
    final bubbleRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, 0, size.x, size.y),
      const Radius.circular(14),
    );

    // Outer glow / shadow
    canvas.drawRRect(
      bubbleRect.inflate(3),
      Paint()..color = Colors.black.withValues(alpha: 0.3),
    );

    // Main bubble
    final bubblePaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFF4FC3F7), Color(0xFF1565C0)],
      ).createShader(Rect.fromLTWH(0, 0, size.x, size.y));
    canvas.drawRRect(bubbleRect, bubblePaint);

    // Border
    canvas.drawRRect(
      bubbleRect,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );

    // Position: uppercase on the left, lowercase on the right, centered vertically
    final totalWidth = _upperPainter.width + 12 + _lowerPainter.width;
    final startX = (size.x - totalWidth) / 2;
    final textY = (size.y - _upperPainter.height) / 2;

    _upperPainter.paint(canvas, Offset(startX, textY));
    _lowerPainter.paint(
      canvas,
      Offset(startX + _upperPainter.width + 12, textY + 6),
    );

    canvas.restore();
  }
}
