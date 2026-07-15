import 'dart:ui' as ui;
import 'package:flame/components.dart';
import 'package:flutter/material.dart';

/// Infinite scrolling background with parallax clouds and ground.
class ScrollingBackground extends Component with HasGameReference {
  double _cloudOffset = 0;
  double _groundOffset = 0;

  // Cloud data: [x-offset, y-position, scale]
  final List<List<double>> _clouds = [
    [0, 40, 1.2],
    [300, 70, 0.8],
    [600, 30, 1.0],
    [150, 90, 0.6],
    [500, 55, 1.1],
  ];

  @override
  void update(double dt) {
    super.update(dt);
    // Parallax: clouds move slower than ground
    _cloudOffset -= 20 * dt;
    _groundOffset -= 100 * dt;
    // Wrap offsets
    if (_cloudOffset < -800) _cloudOffset += 800;
    if (_groundOffset < -800) _groundOffset += 800;
  }

  @override
  void render(Canvas canvas) {
    final w = game.size.x;
    final h = game.size.y;
    final groundY = h * 0.78;

    // Sky gradient
    final skyPaint = Paint()
      ..shader = ui.Gradient.linear(
        Offset(0, 0),
        Offset(0, groundY),
        [const Color(0xFF5C94FC), const Color(0xFF87CEEB)],
      );
    canvas.drawRect(Rect.fromLTWH(0, 0, w, groundY), skyPaint);

    // Clouds
    final cloudPaint = Paint()..color = Colors.white.withValues(alpha: 0.85);
    for (final cloud in _clouds) {
      final cx = (cloud[0] + _cloudOffset) % (w + 200) - 100;
      _drawPixelCloud(canvas, cloudPaint, cx, cloud[1], cloud[2]);
    }

    // Ground - brown earth
    final groundPaint = Paint()..color = const Color(0xFF8B4513);
    canvas.drawRect(Rect.fromLTWH(0, groundY, w, h - groundY), groundPaint);

    // Green grass top layer
    final grassPaint = Paint()..color = const Color(0xFF228B22);
    canvas.drawRect(Rect.fromLTWH(0, groundY, w, 20), grassPaint);

    // Grass tufts (pixel-style)
    final tuftPaint = Paint()..color = const Color(0xFF32CD32);
    final ps = 6.0;
    for (double x = _groundOffset % (ps * 6); x < w + ps * 6; x += ps * 6) {
      // Tuft pattern: small grass blades
      canvas.drawRect(Rect.fromLTWH(x, groundY - ps, ps, ps), tuftPaint);
      canvas.drawRect(Rect.fromLTWH(x + ps * 2, groundY - ps * 1.5, ps, ps * 1.5), tuftPaint);
      canvas.drawRect(Rect.fromLTWH(x + ps * 4, groundY - ps, ps, ps), tuftPaint);
    }

    // Ground detail lines (darker stripes)
    final detailPaint = Paint()..color = const Color(0xFF6D3510);
    for (double x = _groundOffset % 80; x < w + 80; x += 80) {
      canvas.drawRect(Rect.fromLTWH(x, groundY + 30, 40, 4), detailPaint);
      canvas.drawRect(Rect.fromLTWH(x + 50, groundY + 55, 30, 4), detailPaint);
    }
  }

  void _drawPixelCloud(Canvas canvas, Paint paint, double x, double y, double scale) {
    final s = 10.0 * scale;
    // Simple cloud shape: 3 rows of rectangles
    // Row 0: 2 blocks (top)
    canvas.drawRect(Rect.fromLTWH(x + s, y, s * 2, s), paint);
    // Row 1: 4 blocks (middle, wider)
    canvas.drawRect(Rect.fromLTWH(x, y + s, s * 4, s), paint);
    // Row 2: 4 blocks (bottom)
    canvas.drawRect(Rect.fromLTWH(x, y + s * 2, s * 4, s), paint);
    // Row 3: 2 blocks (base)
    canvas.drawRect(Rect.fromLTWH(x + s * 0.5, y + s * 3, s * 3, s), paint);
  }

  double get groundY => game.size.y * 0.78;
}
