import 'package:flame/components.dart';
import 'package:flutter/material.dart';
import '../../utils/pixel_painter.dart';
import 'letter_bubble.dart';

/// Enemy/obstacle that moves from right to left.
/// Has an assigned letter that the player must type to destroy it.
class ObstacleSprite extends PositionComponent with HasGameReference {
  final String letter;
  double speed;
  bool isDestroyed = false;
  bool hasPassedMario = false;
  double _destroyTimer = 0;
  double _walkFrame = 0;
  double _walkTimer = 0;
  late LetterBubble _letterBubble;

  static const double _destroyDuration = 0.6;

  ObstacleSprite({
    required this.letter,
    required this.speed,
    required double groundY,
    required double startX,
  }) {
    size = Vector2(52, 56);
    anchor = Anchor.bottomLeft;
    position = Vector2(startX, groundY);

    // Create letter bubble as a child
    _letterBubble = LetterBubble(letter: letter);
  }

  @override
  Future<void> onLoad() async {
    super.onLoad();
    _letterBubble.position = Vector2(size.x / 2, -size.y - 10);
    _letterBubble.anchor = Anchor.center;
    add(_letterBubble);
  }

  @override
  void update(double dt) {
    super.update(dt);

    if (isDestroyed) {
      _destroyTimer += dt;
      // Death animation: move down and spin
      position.y += 200 * dt;
      angle += 10 * dt;
      if (_destroyTimer >= _destroyDuration) {
        removeFromParent();
      }
      return;
    }

    // Move left
    position.x -= speed * dt;

    // Walk animation
    _walkTimer += dt;
    if (_walkTimer >= 0.2) {
      _walkTimer = 0;
      _walkFrame = (_walkFrame + 1) % 2;
    }

    // Check if passed Mario (x < Mario position)
    if (!hasPassedMario && position.x + size.x < 100) {
      hasPassedMario = true;
    }
  }

  @override
  void render(Canvas canvas) {
    if (isDestroyed) {
      // Draw flipped/falling goomba
      canvas.save();
      final centerX = size.x / 2;
      final centerY = size.y / 2;
      canvas.translate(centerX, centerY);
      canvas.scale(1, -1); // flip vertically
      canvas.translate(-centerX, -centerY);
      PixelPainter.drawGoomba(canvas, const Offset(4, 4), 1.0);
      canvas.restore();
      return;
    }

    // Draw shadow
    final shadowPaint = Paint()..color = Colors.black.withValues(alpha: 0.2);
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(size.x / 2, size.y - 2),
        width: 40,
        height: 8,
      ),
      shadowPaint,
    );

    // Draw walking goomba with simple bob animation
    final bobY = _walkFrame == 0 ? 0.0 : -2.0;
    PixelPainter.drawGoomba(canvas, Offset(4, 4 + bobY), 1.0);
  }

  /// Destroy this obstacle with death animation.
  void destroy() {
    if (isDestroyed) return;
    isDestroyed = true;
    _destroyTimer = 0;
    _letterBubble.isVisible = false;
  }

  /// Check if the obstacle's bounding box overlaps with Mario's area.
  bool overlapsMario(double marioLeft, double marioRight) {
    final obsLeft = position.x;
    final obsRight = position.x + size.x;
    return obsLeft < marioRight && obsRight > marioLeft;
  }
}
