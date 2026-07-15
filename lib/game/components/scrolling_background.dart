import 'dart:ui' as ui;
import 'dart:math';
import 'package:flame/components.dart';
import 'package:flutter/material.dart';
import '../core/terrain_system.dart';

/// Background theme identifiers.
enum BgTheme { grassland, mountain, waterside, town, desert }

/// Color/gradient definition for a theme.
class _ThemeColors {
  final Color skyTop;
  final Color skyBottom;
  final Color groundColor;
  final Color grassColor;
  final Color grassLight;
  final Color groundDetail;
  final Color cliffFace;
  const _ThemeColors({
    required this.skyTop,
    required this.skyBottom,
    required this.groundColor,
    required this.grassColor,
    required this.grassLight,
    required this.groundDetail,
    required this.cliffFace,
  });
}

/// Infinite scrolling background with parallax scenery, themed visuals,
/// step-terrain rendering, and animated theme transitions.
class ScrollingBackground extends Component with HasGameReference {
  final TerrainSystem terrainSystem;

  ScrollingBackground({required this.terrainSystem});

  double _cloudOffset = 0;
  double _groundOffset = 0;
  double _farOffset = 0; // distant scenery parallax

  // Cloud data: [x-offset, y-position, scale]
  final List<List<double>> _clouds = [
    [0, 40, 1.2],
    [300, 70, 0.8],
    [600, 30, 1.0],
    [150, 90, 0.6],
    [500, 55, 1.1],
  ];

  // Theme state
  BgTheme _currentTheme = BgTheme.grassland;
  BgTheme? _transitionFrom;
  double _transitionProgress = 1.0; // 1.0 = fully on current theme
  static const double _transitionDuration = 0.8;

  // Theme definitions
  static const Map<BgTheme, _ThemeColors> _themeColors = {
    BgTheme.grassland: _ThemeColors(
      skyTop: Color(0xFF5C94FC),
      skyBottom: Color(0xFF87CEEB),
      groundColor: Color(0xFF8B4513),
      grassColor: Color(0xFF228B22),
      grassLight: Color(0xFF32CD32),
      groundDetail: Color(0xFF6D3510),
      cliffFace: Color(0xFF6D3510),
    ),
    BgTheme.mountain: _ThemeColors(
      skyTop: Color(0xFF4A6FA5),
      skyBottom: Color(0xFF8EAEC4),
      groundColor: Color(0xFF5C5C5C),
      grassColor: Color(0xFF3B6B3B),
      grassLight: Color(0xFF5A8A5A),
      groundDetail: Color(0xFF3A3A3A),
      cliffFace: Color(0xFF4A4A4A),
    ),
    BgTheme.waterside: _ThemeColors(
      skyTop: Color(0xFF2196F3),
      skyBottom: Color(0xFF64B5F6),
      groundColor: Color(0xFF1565C0),
      grassColor: Color(0xFF2E7D32),
      grassLight: Color(0xFF43A047),
      groundDetail: Color(0xFF0D47A1),
      cliffFace: Color(0xFF1B5E20),
    ),
    BgTheme.town: _ThemeColors(
      skyTop: Color(0xFF7986CB),
      skyBottom: Color(0xFFB0BEC5),
      groundColor: Color(0xFF5D4037),
      grassColor: Color(0xFF7CB342),
      grassLight: Color(0xFF9CCC65),
      groundDetail: Color(0xFF3E2723),
      cliffFace: Color(0xFF4E342E),
    ),
    BgTheme.desert: _ThemeColors(
      skyTop: Color(0xFFFFB74D),
      skyBottom: Color(0xFFFFE0B2),
      groundColor: Color(0xFFD4A03C),
      grassColor: Color(0xFFC8A23C),
      grassLight: Color(0xFFE0C060),
      groundDetail: Color(0xFFB8860B),
      cliffFace: Color(0xFFB8860B),
    ),
  };

  /// Request a theme change (starts transition animation).
  void switchTheme(BgTheme newTheme) {
    if (newTheme == _currentTheme && _transitionFrom == null) return;
    _transitionFrom = _currentTheme;
    _currentTheme = newTheme;
    _transitionProgress = 0.0;
  }

  /// Get the next theme in the cycle.
  BgTheme getNextTheme() {
    const themes = BgTheme.values;
    final idx = themes.indexOf(_currentTheme);
    return themes[(idx + 1) % themes.length];
  }

  @override
  void update(double dt) {
    super.update(dt);

    // Parallax speeds
    _farOffset -= 10 * dt;
    _cloudOffset -= 20 * dt;
    _groundOffset -= 100 * dt;

    // Wrap offsets
    if (_farOffset < -1200) _farOffset += 1200;
    if (_cloudOffset < -800) _cloudOffset += 800;
    if (_groundOffset < -800) _groundOffset += 800;

    // Transition animation
    if (_transitionProgress < 1.0) {
      _transitionProgress += dt / _transitionDuration;
      if (_transitionProgress >= 1.0) {
        _transitionProgress = 1.0;
        _transitionFrom = null;
      }
    }
  }

  @override
  void render(Canvas canvas) {
    final w = game.size.x;
    final h = game.size.y;
    final defaultGroundY = h * 0.78;

    // Resolve blended colors during transition
    final tc = _resolveColors();

    // ─── Sky gradient ───
    final skyPaint = Paint()
      ..shader = ui.Gradient.linear(
        Offset(0, 0),
        Offset(0, defaultGroundY),
        [tc.skyTop, tc.skyBottom],
      );
    canvas.drawRect(Rect.fromLTWH(0, 0, w, h), skyPaint);

    // ─── Distant scenery (theme-specific, slowest parallax) ───
    _drawFarScenery(canvas, w, h, defaultGroundY);

    // ─── Clouds ───
    final cloudPaint = Paint()..color = Colors.white.withAlpha(216);
    for (final cloud in _clouds) {
      final cx = (cloud[0] + _cloudOffset) % (w + 200) - 100;
      _drawPixelCloud(canvas, cloudPaint, cx, cloud[1], cloud[2]);
    }

    // ─── Step terrain ground ───
    _drawTerrainGround(canvas, w, h, tc);
  }

  void _drawTerrainGround(Canvas canvas, double w, double h, _ThemeColors tc) {
    final segments = terrainSystem.getVisibleSegments(0, w);
    if (segments.isEmpty) {
      // Fallback: flat ground at default Y
      final gy = h * 0.78;
      canvas.drawRect(Rect.fromLTWH(0, gy, w, h - gy), Paint()..color = tc.groundColor);
      canvas.drawRect(Rect.fromLTWH(0, gy, w, 20), Paint()..color = tc.grassColor);
      return;
    }

    // Draw each segment
    for (final seg in segments) {
      final sx = seg.startX.clamp(0.0, w);
      final ex = seg.endX.clamp(0.0, w);
      if (sx >= ex) continue;

      final gy = seg.groundY;
      // Ground fill
      canvas.drawRect(Rect.fromLTWH(sx, gy, ex - sx, h - gy), Paint()..color = tc.groundColor);
      // Grass top layer
      canvas.drawRect(Rect.fromLTWH(sx, gy, ex - sx, 20), Paint()..color = tc.grassColor);
      // Grass tufts
      _drawGrassTufts(canvas, sx, ex, gy, tc.grassLight);
      // Ground detail lines
      _drawGroundDetails(canvas, sx, ex, gy, tc.groundDetail);
    }

    // Draw cliff faces at height transitions between adjacent segments
    for (int i = 0; i < segments.length - 1; i++) {
      final left = segments[i];
      final right = segments[i + 1];
      // Cliff at the boundary (where left ends and right begins)
      final boundaryX = left.endX.clamp(0.0, w);
      if (boundaryX <= 0 || boundaryX >= w) continue;

      final topY = min(left.groundY, right.groundY);
      final botY = max(left.groundY, right.groundY);

      if (botY - topY > 2) {
        // There's a height difference — draw cliff face
        canvas.drawRect(
          Rect.fromLTWH(boundaryX - 3, topY, 6, botY - topY),
          Paint()..color = tc.cliffFace,
        );
        // Grass edge on top of cliff
        if (left.groundY < right.groundY) {
          // Left side is higher — cliff goes down on the right
          canvas.drawRect(
            Rect.fromLTWH(boundaryX - 2, topY, 5, 6),
            Paint()..color = tc.grassColor,
          );
        } else {
          canvas.drawRect(
            Rect.fromLTWH(boundaryX - 2, botY - 6, 5, 6),
            Paint()..color = tc.grassColor,
          );
        }
      }
    }
  }

  void _drawGrassTufts(Canvas canvas, double sx, double ex, double gy, Color color) {
    final paint = Paint()..color = color;
    final ps = 6.0;
    final start = (sx / (ps * 6)).floor() * (ps * 6);
    for (double x = start + (_groundOffset % (ps * 6)); x < ex; x += ps * 6) {
      if (x + ps * 4 > sx) {
        canvas.drawRect(Rect.fromLTWH(x, gy - ps, ps, ps), paint);
        canvas.drawRect(Rect.fromLTWH(x + ps * 2, gy - ps * 1.5, ps, ps * 1.5), paint);
        canvas.drawRect(Rect.fromLTWH(x + ps * 4, gy - ps, ps, ps), paint);
      }
    }
  }

  void _drawGroundDetails(Canvas canvas, double sx, double ex, double gy, Color color) {
    final paint = Paint()..color = color;
    final start = (sx / 80).floor() * 80;
    for (double x = start + (_groundOffset % 80); x < ex; x += 80) {
      if (x + 40 > sx) {
        canvas.drawRect(Rect.fromLTWH(x, gy + 30, 40, 4), paint);
      }
      if (x + 80 > sx) {
        canvas.drawRect(Rect.fromLTWH(x + 50, gy + 55, 30, 4), paint);
      }
    }
  }

  // ─── Far scenery (theme-specific distant silhouettes) ────────────────

  void _drawFarScenery(Canvas canvas, double w, double h, double defaultGroundY) {
    final theme = _resolveFarTheme();
    switch (theme) {
      case BgTheme.grassland:
        _drawHills(canvas, w, defaultGroundY, const Color(0xFF3B8C3B));
        break;
      case BgTheme.mountain:
        _drawMountains(canvas, w, defaultGroundY);
        break;
      case BgTheme.waterside:
        _drawWater(canvas, w, defaultGroundY, h);
        break;
      case BgTheme.town:
        _drawBuildings(canvas, w, defaultGroundY);
        break;
      case BgTheme.desert:
        _drawDunes(canvas, w, defaultGroundY);
        break;
    }
  }

  BgTheme _resolveFarTheme() {
    return _transitionProgress < 0.5 && _transitionFrom != null
        ? _transitionFrom!
        : _currentTheme;
  }

  void _drawHills(Canvas canvas, double w, double gy, Color color) {
    final paint = Paint()..color = color.withAlpha(100);
    for (double x = (_farOffset % 400) - 200; x < w + 200; x += 200) {
      final hillPath = Path()
        ..moveTo(x - 80, gy)
        ..quadraticBezierTo(x, gy - 60, x + 80, gy)
        ..close();
      canvas.drawPath(hillPath, paint);
    }
  }

  void _drawMountains(Canvas canvas, double w, double gy) {
    // Far mountains (darker, bigger)
    final farPaint = Paint()..color = const Color(0xFF546E7A).withAlpha(120);
    for (double x = (_farOffset % 500) - 100; x < w + 250; x += 250) {
      final path = Path()
        ..moveTo(x - 120, gy)
        ..lineTo(x, gy - 130)
        ..lineTo(x + 120, gy)
        ..close();
      canvas.drawPath(path, farPaint);
    }
    // Near mountains (lighter, smaller)
    final nearPaint = Paint()..color = const Color(0xFF78909C).withAlpha(90);
    for (double x = (_farOffset % 350) + 50; x < w + 180; x += 180) {
      final path = Path()
        ..moveTo(x - 90, gy)
        ..lineTo(x, gy - 80)
        ..lineTo(x + 90, gy)
        ..close();
      canvas.drawPath(path, nearPaint);
    }
  }

  void _drawWater(Canvas canvas, double w, double gy, double h) {
    // Water surface below ground level
    final waterPaint = Paint()..color = const Color(0xFF1565C0).withAlpha(80);
    canvas.drawRect(Rect.fromLTWH(0, gy + 20, w, h - gy - 20), waterPaint);
    // Gentle wave lines
    final wavePaint = Paint()
      ..color = const Color(0xFF64B5F6).withAlpha(60)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    for (int row = 0; row < 4; row++) {
      final path = Path();
      final baseY = gy + 25 + row * 15.0;
      path.moveTo(0, baseY);
      for (double x = 0; x < w; x += 20) {
        path.lineTo(x + 10, baseY + sin((x + _farOffset * 2) * 0.05) * 4);
        path.lineTo(x + 20, baseY);
      }
      canvas.drawPath(path, wavePaint);
    }
    // Lily pads
    final lilyPaint = Paint()..color = const Color(0xFF2E7D32).withAlpha(100);
    for (double x = (_farOffset * 0.8 % 300); x < w; x += 150) {
      canvas.drawOval(
        Rect.fromCenter(center: Offset(x + 50, gy + 40), width: 24, height: 10),
        lilyPaint,
      );
    }
  }

  void _drawBuildings(Canvas canvas, double w, double gy) {
    // City silhouette
    final buildingPaint = Paint()..color = const Color(0xFF37474F).withAlpha(100);
    final windowPaint = Paint()..color = const Color(0xFFFFF176).withAlpha(120);
    final rng = Random(42); // Fixed seed for consistent buildings

    for (double x = (_farOffset % 400) - 50; x < w + 200; x += 80 + rng.nextDouble() * 40) {
      final bw = 30.0 + rng.nextDouble() * 40;
      final bh = 40.0 + rng.nextDouble() * 100;
      canvas.drawRect(Rect.fromLTWH(x, gy - bh, bw, bh), buildingPaint);
      // Windows (2 columns)
      for (double wy = gy - bh + 10; wy < gy - 10; wy += 18) {
        canvas.drawRect(Rect.fromLTWH(x + 6, wy, 6, 8), windowPaint);
        canvas.drawRect(Rect.fromLTWH(x + bw - 12, wy, 6, 8), windowPaint);
      }
    }
  }

  void _drawDunes(Canvas canvas, double w, double gy) {
    // Sand dunes (smooth curves)
    final dunePaint = Paint()..color = const Color(0xFFD4A03C).withAlpha(70);
    for (double x = (_farOffset % 500) - 200; x < w + 250; x += 250) {
      final path = Path()
        ..moveTo(x - 150, gy)
        ..quadraticBezierTo(x - 50, gy - 50, x, gy - 30)
        ..quadraticBezierTo(x + 50, gy - 60, x + 150, gy)
        ..close();
      canvas.drawPath(path, dunePaint);
    }
    // Cactus silhouettes
    final cactusPaint = Paint()..color = const Color(0xFF2E7D32).withAlpha(80);
    for (double x = (_farOffset * 0.7 % 600); x < w; x += 300) {
      // Main trunk
      canvas.drawRect(Rect.fromLTWH(x + 60, gy - 45, 10, 45), cactusPaint);
      // Left arm
      canvas.drawRect(Rect.fromLTWH(x + 45, gy - 35, 15, 6), cactusPaint);
      canvas.drawRect(Rect.fromLTWH(x + 45, gy - 50, 6, 21), cactusPaint);
      // Right arm
      canvas.drawRect(Rect.fromLTWH(x + 71, gy - 28, 15, 6), cactusPaint);
      canvas.drawRect(Rect.fromLTWH(x + 80, gy - 43, 6, 21), cactusPaint);
    }
  }

  // ─── Color blending during transitions ───────────────────────────────

  _ThemeColors _resolveColors() {
    if (_transitionFrom == null || _transitionProgress >= 1.0) {
      return _themeColors[_currentTheme]!;
    }
    final from = _themeColors[_transitionFrom!]!;
    final to = _themeColors[_currentTheme]!;
    final t = _transitionProgress;
    return _ThemeColors(
      skyTop: Color.lerp(from.skyTop, to.skyTop, t)!,
      skyBottom: Color.lerp(from.skyBottom, to.skyBottom, t)!,
      groundColor: Color.lerp(from.groundColor, to.groundColor, t)!,
      grassColor: Color.lerp(from.grassColor, to.grassColor, t)!,
      grassLight: Color.lerp(from.grassLight, to.grassLight, t)!,
      groundDetail: Color.lerp(from.groundDetail, to.groundDetail, t)!,
      cliffFace: Color.lerp(from.cliffFace, to.cliffFace, t)!,
    );
  }

  // ─── Pixel cloud ─────────────────────────────────────────────────────

  void _drawPixelCloud(Canvas canvas, Paint paint, double x, double y, double scale) {
    final s = 10.0 * scale;
    canvas.drawRect(Rect.fromLTWH(x + s, y, s * 2, s), paint);
    canvas.drawRect(Rect.fromLTWH(x, y + s, s * 4, s), paint);
    canvas.drawRect(Rect.fromLTWH(x, y + s * 2, s * 4, s), paint);
    canvas.drawRect(Rect.fromLTWH(x + s * 0.5, y + s * 3, s * 3, s), paint);
  }

  double get groundY => game.size.y * 0.78;
}
