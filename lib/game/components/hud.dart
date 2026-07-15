import 'dart:math';
import 'package:flame/components.dart';
import 'package:flutter/material.dart';
import '../../utils/pixel_painter.dart';

/// HUD component: displays score (top-right) and lives (top-left).
/// Letter hint removed — letters are shown on objects themselves.
class HudComponent extends Component with HasGameReference {
  int _score = 0;
  int _lives = 3;

  // Power-up status indicators
  double _invincibleTimer = 0;
  double _slowTimer = 0;

  // Score flash animation
  int _displayedScore = 0;
  double _scoreFlashTimer = 0;

  // Cached text painters (recreated only when score changes)
  TextPainter _scorePainter = TextPainter();
  String _lastScoreText = '';

  static const TextStyle _scoreStyle = TextStyle(
    fontSize: 28,
    fontWeight: FontWeight.w900,
    color: Colors.white,
    fontFamily: 'monospace',
    shadows: [
      Shadow(offset: Offset(2, 2), color: Colors.black87),
    ],
  );

  void setScore(int score) {
    _score = score;
    _scoreFlashTimer = 0.5;
  }

  void setLives(int lives) {
    _lives = lives;
  }

  /// Set power-up timer displays (called each frame by game).
  void setPowerUpTimers({double invincible = 0, double slow = 0}) {
    _invincibleTimer = invincible;
    _slowTimer = slow;
  }

  @override
  void update(double dt) {
    super.update(dt);
    if (_scoreFlashTimer > 0) {
      _scoreFlashTimer -= dt;
    }
    // Animate displayed score toward actual score
    if (_displayedScore < _score) {
      _displayedScore += 2;
      if (_displayedScore > _score) _displayedScore = _score;
    }
  }

  void _ensureScorePainter() {
    final text = 'Score: $_displayedScore';
    if (text == _lastScoreText) return;
    _lastScoreText = text;
    _scorePainter = TextPainter(
      text: TextSpan(text: text, style: _scoreStyle),
      textDirection: TextDirection.ltr,
    );
    _scorePainter.layout();
  }

  @override
  void render(Canvas canvas) {
    final w = game.size.x;

    // Score (top-right) — cached painter
    _ensureScorePainter();
    _scorePainter.paint(canvas, Offset(w - 220, 16));

    // Lives (top-left) - draw hearts
    for (int i = 0; i < _lives; i++) {
      PixelPainter.drawHeart(canvas, Offset(16 + i * 36.0, 14), 1.2);
    }

    // Power-up status indicators (below hearts)
    double statusY = 52;
    if (_invincibleTimer > 0) {
      final starAlpha = (200 + 55 * sin(DateTime.now().millisecondsSinceEpoch * 0.008)).round().clamp(0, 255);
      PixelPainter.drawStar(canvas, Offset(16, statusY), 0.9, alpha: starAlpha);
      final invText = TextPainter(
        text: TextSpan(text: '★ ${_invincibleTimer.toStringAsFixed(0)}s', style: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w900,
          color: Colors.yellow.shade600,
          fontFamily: 'monospace',
          shadows: const [Shadow(offset: Offset(1, 1), color: Colors.black54)],
        )),
        textDirection: TextDirection.ltr,
      )..layout();
      invText.paint(canvas, Offset(42, statusY + 2));
      statusY += 28;
    }
    if (_slowTimer > 0) {
      PixelPainter.drawBoots(canvas, Offset(18, statusY), 0.8);
      final slowText = TextPainter(
        text: TextSpan(text: '🥾 ${_slowTimer.toStringAsFixed(0)}s', style: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w900,
          color: Colors.blue.shade300,
          fontFamily: 'monospace',
          shadows: const [Shadow(offset: Offset(1, 1), color: Colors.black54)],
        )),
        textDirection: TextDirection.ltr,
      )..layout();
      slowText.paint(canvas, Offset(42, statusY + 2));
    }
  }
}
