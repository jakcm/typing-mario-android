import 'package:flame/components.dart';
import 'dart:ui' show Rect;

/// Abstract interface for all letter-bearing game objects.
/// Implemented by ObstacleSprite, FloatingCoinSprite, PlatformSprite, GapSprite.
abstract class LetterTarget extends PositionComponent {
  /// Current horizontal scroll speed. The game owns effect-time adjustments.
  double get speed;
  set speed(double value);

  /// The letter assigned to this target.
  String get letter;

  /// Whether this target has been consumed (destroyed/collected/jumped-on).
  bool get isConsumed;

  /// Called when the player types the matching letter.
  void onLetterMatched();

  /// Check collision with Mario's bounding rectangle.
  bool collidesWith(Rect marioBounds);
}
