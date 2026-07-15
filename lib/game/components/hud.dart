import 'package:flame/components.dart';
import 'package:flutter/material.dart';
import '../../utils/pixel_painter.dart';

/// HUD component: displays score (top-right) and lives (top-left).
/// Letter hint removed — letters are shown on objects themselves.
class HudComponent extends Component with HasGameReference {
  int _score = 0;
  int _lives = 3;

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
  }
}
