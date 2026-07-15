import 'package:flame/components.dart';
import 'package:flutter/material.dart';
import '../../utils/pixel_painter.dart';

/// HUD component: displays score (top-right), lives (top-left),
/// and current letter hint (center-top).
/// Caches TextPainters for performance.
class HudComponent extends Component with HasGameReference {
  int _score = 0;
  int _lives = 3;
  String _currentLetter = '';
  bool _showHint = false;
  double _hintTimer = 0;

  // Score flash animation
  int _displayedScore = 0;
  double _scoreFlashTimer = 0;

  // Cached text painters (recreated only when score changes)
  TextPainter _scorePainter = TextPainter();
  String _lastScoreText = '';

  // Cached hint painters
  TextPainter _hintPainter = TextPainter();
  String _lastHintText = '';

  static const TextStyle _scoreStyle = TextStyle(
    fontSize: 28,
    fontWeight: FontWeight.w900,
    color: Colors.white,
    fontFamily: 'monospace',
    shadows: [
      Shadow(offset: Offset(2, 2), color: Colors.black87),
    ],
  );

  static const TextStyle _hintStyle = TextStyle(
    fontSize: 36,
    fontWeight: FontWeight.w900,
    color: Colors.white,
    fontFamily: 'monospace',
  );

  void setScore(int score) {
    _score = score;
    _scoreFlashTimer = 0.5;
  }

  void setLives(int lives) {
    _lives = lives;
  }

  void showLetterHint(String letter) {
    _currentLetter = letter;
    _showHint = true;
    _hintTimer = 1.5;
  }

  void hideLetterHint() {
    _showHint = false;
  }

  @override
  void update(double dt) {
    super.update(dt);
    if (_hintTimer > 0) {
      _hintTimer -= dt;
      if (_hintTimer <= 0) {
        _showHint = false;
      }
    }
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

  void _ensureHintPainter() {
    if (_currentLetter.isEmpty) return;
    final upper = _currentLetter.toUpperCase();
    final lower = _currentLetter.toLowerCase();
    final text = '$upper  $lower';
    if (text == _lastHintText) return;
    _lastHintText = text;
    _hintPainter = TextPainter(
      text: TextSpan(text: text, style: _hintStyle),
      textDirection: TextDirection.ltr,
    );
    _hintPainter.layout();
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

    // Letter hint (center-top) - pulsing
    if (_showHint && _currentLetter.isNotEmpty) {
      final bubbleCenter = Offset(w / 2, 50);

      // Draw bubble background
      final bubblePaint = Paint()
        ..color = Colors.blue.shade700.withValues(alpha: 0.8);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: bubbleCenter, width: 140, height: 60),
          const Radius.circular(16),
        ),
        bubblePaint,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: bubbleCenter, width: 140, height: 60),
          const Radius.circular(16),
        ),
        Paint()
          ..color = Colors.white
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3,
      );

      // Draw cached letter text
      _ensureHintPainter();
      _hintPainter.paint(
        canvas,
        Offset(
          bubbleCenter.dx - _hintPainter.width / 2,
          bubbleCenter.dy - _hintPainter.height / 2,
        ),
      );
    }
  }
}
