import 'package:flutter/material.dart';

/// A simple pixel-art renderer for game characters.
/// Each character is defined as a list of strings where each character
/// maps to a color. '.' is transparent.
class PixelPainter {
  // Color palette
  static const Color _red = Color(0xFFE4002B);
  static const Color _darkRed = Color(0xFFB00020);
  static const Color _brown = Color(0xFF8B4513);
  static const Color _skin = Color(0xFFFFCC99);
  static const Color _blue = Color(0xFF2962FF);
  static const Color _darkBlue = Color(0xFF1A237E);
  static const Color _yellow = Color(0xFFFFD600);
  static const Color _white = Colors.white;
  static const Color _black = Colors.black;
  static const Color _green = Color(0xFF2E7D32);
  static const Color _tan = Color(0xFFDEB887);
  static const Color _orange = Color(0xFFFF8F00);

  static Color? _colorForChar(String c) {
    switch (c) {
      case 'R':
        return _red;
      case 'r':
        return _darkRed;
      case 'B':
        return _brown;
      case 'S':
        return _skin;
      case 'D':
        return _blue;
      case 'd':
        return _darkBlue;
      case 'Y':
        return _yellow;
      case 'W':
        return _white;
      case 'K':
        return _black;
      case 'G':
        return _green;
      case 'T':
        return _tan;
      case 'O':
        return _orange;
      case '.':
        return null;
      default:
        return null;
    }
  }

  /// Draw a pixel-art pattern at the given offset.
  /// Each "pixel" in the pattern is drawn as a [pixelSize] x [pixelSize] rectangle.
  static void _drawPattern(
    Canvas canvas,
    Offset offset,
    List<String> pattern,
    double pixelSize, {
    int alpha = 255,
  }) {
    // Reuse one Paint for the entire sprite. This path runs for every game
    // object every frame, so allocating a Paint per pixel causes TV-side GC
    // pressure and raster jank.
    final paint = Paint();
    final alphaByte = alpha.clamp(0, 255);
    for (int row = 0; row < pattern.length; row++) {
      for (int col = 0; col < pattern[row].length; col++) {
        final c = pattern[row][col];
        final color = _colorForChar(c);
        if (color == null) continue;
        paint.color = color.withAlpha(alphaByte);
        canvas.drawRect(
          Rect.fromLTWH(
            offset.dx + col * pixelSize,
            offset.dy + row * pixelSize,
            pixelSize,
            pixelSize,
          ),
          paint,
        );
      }
    }
  }

  // ─── Mario (16 wide × 16 tall) ───────────────────────────────────────
  // R = red (hat/shirt), r = dark red, B = brown (hair/shoes), S = skin,
  // D = blue (overalls), W = white (eyes), K = black (outlines)

  static const List<String> _marioFrame0 = [
    '....RRRRR.......',
    '...RRRRRRRR.....',
    '...BBBSSBSK.....',
    '..BSBSSSBSSSK...',
    '..BSBBSSSBSSSK..',
    '..BBSSSSBBBBB...',
    '....SSSSSSSS....',
    '..RRDDRRRDR.....',
    '.RRRDDDRRRDRR...',
    'RRRRDDDDDRRRRR..',
    'SSSRDSSDSSDRRSS.',
    'SSSSDDDDDDDSSSS.',
    '.SSDDDDDDDDDS..',
    '..DDD....DDD....',
    '.BBB......BBB...',
    '.BBBB....BBBB...',
  ];

  static const List<String> _marioFrame1 = [
    '....RRRRR.......',
    '...RRRRRRRR.....',
    '...BBBSSBSK.....',
    '..BSBSSSBSSSK...',
    '..BSBBSSSBSSSK..',
    '..BBSSSSBBBBB...',
    '....SSSSSSSS....',
    '..RRDDRRRDR.....',
    '.RRRDDDRRRDRR...',
    'RRRRDDDDDRRRRR..',
    'SSSRDSSDSSDRRSS.',
    'SSSSDDDDDDDSSSS.',
    '.SSDDDDDDDDDS..',
    '..DDD....DDD....',
    '...BBB..BBB.....',
    '..BBBB..BBBB....',
  ];

  static void drawMario(
    Canvas canvas,
    Offset position,
    double scale, {
    int frame = 0,
  }) {
    final ps = 4.0 * scale; // pixel size
    final pattern = frame.isEven ? _marioFrame0 : _marioFrame1;
    _drawPattern(canvas, position, pattern, ps);
  }

  // ─── Goomba enemy (12 wide × 13 tall) ────────────────────────────────

  static const List<String> _goombaPixels = [
    '....BBBB....',
    '...BBBBBB...',
    '..BBBBBBBB..',
    '.BBBBBBBBBB.',
    '.BBBBBBBBBB.',
    'BBBBBBBBBBBB',
    'BWWBBBBBBWWB',
    'BWKBBBBBWKWB',
    'BWWBBBBBBWWB',
    '..TTTTTTTT..',
    '.TTTTTTTTTT.',
    '..KK....KK..',
    '.KKK....KKK.',
  ];

  static void drawGoomba(
    Canvas canvas,
    Offset position,
    double scale, {
    bool flipped = false,
  }) {
    final ps = 4.0 * scale;
    if (flipped) {
      canvas.save();
      canvas.translate(position.dx, position.dy);
      canvas.scale(1, -1);
      canvas.translate(-position.dx, -position.dy);
      _drawPattern(canvas, position, _goombaPixels, ps);
      canvas.restore();
    } else {
      _drawPattern(canvas, position, _goombaPixels, ps);
    }
  }

  // ─── Coin (8 wide × 8 tall) ──────────────────────────────────────────

  static const List<String> _coinPixels = [
    '..YYYY..',
    '.YYYYYY.',
    'YYOYOYYY',
    'YYOYYYYY',
    'YYOYYYYY',
    'YYOYOYYY',
    '.YYYYYY.',
    '..YYYY..',
  ];

  static void drawCoin(
    Canvas canvas,
    Offset position,
    double scale, {
    int alpha = 255,
  }) {
    final ps = 3.0 * scale;
    _drawPattern(canvas, position, _coinPixels, ps, alpha: alpha);
  }

  // ─── Heart (9 wide × 8 tall) ─────────────────────────────────────────

  static const List<String> _heartPixels = [
    '.RR..RR.',
    'RRRRRRRR',
    'RRRRRRRR',
    'RRRRRRRR',
    '.RRRRRR.',
    '..RRRR..',
    '...RR...',
    '........',
  ];

  static void drawHeart(Canvas canvas, Offset position, double scale) {
    final ps = 3.0 * scale;
    _drawPattern(canvas, position, _heartPixels, ps);
  }

  // ─── Cloud (simple, 10 wide × 5 tall) ────────────────────────────────

  static const List<String> _cloudPixels = [
    '...WWWW...',
    '..WWWWWW..',
    '.WWWWWWWW.',
    'WWWWWWWWWW',
    '.WWWWWWWW.',
  ];

  // ─── Star (8×8 golden star) ──────────────────────────────────────────

  static void drawCloud(Canvas canvas, Offset position, double scale) {
    final ps = 8.0 * scale;
    _drawPattern(canvas, position, _cloudPixels, ps);
  }

  static const List<String> _starPixels = [
    '...YY...',
    '...YY...',
    '.YYYYYY.',
    'YYYYYYYY',
    '.YYYYYY.',
    '..YY.YY.',
    '.YY...YY',
    'YY.....Y',
  ];

  static void drawStar(
    Canvas canvas,
    Offset position,
    double scale, {
    int alpha = 255,
  }) {
    final ps = 3.0 * scale;
    _drawPattern(canvas, position, _starPixels, ps, alpha: alpha);
  }

  // ─── Red Mushroom (10×10) ────────────────────────────────────────────

  static const List<String> _mushroomPixels = [
    '...RRRR...',
    '..RRRRRR..',
    '.RRWWRRRR.',
    '.RWWWRRRRR',
    'RRWWWRRRRR',
    'RRWWRRRRRR',
    '.RRRRRRRR.',
    '..TTTTTT..',
    '.TTTTTTTT.',
    '..TTTTTT..',
  ];

  static void drawMushroom(
    Canvas canvas,
    Offset position,
    double scale, {
    int alpha = 255,
  }) {
    final ps = 3.0 * scale;
    _drawPattern(canvas, position, _mushroomPixels, ps, alpha: alpha);
  }

  // ─── Speed Boots (8×8 blue boots) ────────────────────────────────────

  static const List<String> _bootsPixels = [
    '..DDDD..',
    '.DDDDDD.',
    '.DDDDDD.',
    'DDDDDDDB',
    'DDDDDDDB',
    '.DDDDDB.',
    '..KKKK..',
    '.KK..KK.',
  ];

  static void drawBoots(
    Canvas canvas,
    Offset position,
    double scale, {
    int alpha = 255,
  }) {
    final ps = 3.0 * scale;
    _drawPattern(canvas, position, _bootsPixels, ps, alpha: alpha);
  }

  // ─── Invincibility effect ring (10×10 golden ring) ───────────────────

  static const List<String> _invincRingPixels = [
    '...YYYY...',
    '..YY..YY..',
    '.YY....YY.',
    'YY......YY',
    'YY......YY',
    'YY......YY',
    'YY......YY',
    '.YY....YY.',
    '..YY..YY..',
    '...YYYY...',
  ];

  static void drawInvincRing(
    Canvas canvas,
    Offset position,
    double scale, {
    int alpha = 255,
  }) {
    final ps = 3.0 * scale;
    _drawPattern(canvas, position, _invincRingPixels, ps, alpha: alpha);
  }
}
