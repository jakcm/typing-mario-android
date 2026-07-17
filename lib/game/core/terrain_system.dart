import 'dart:math';

/// Represents a single terrain segment with a flat top surface at a given height.
class TerrainSegment {
  double startX;
  double endX;
  double groundY;

  TerrainSegment({
    required this.startX,
    required this.endX,
    required this.groundY,
  });
}

/// Generates and manages scrolling terrain segments with step-like height changes.
///
/// The terrain is a series of horizontal segments at different heights,
/// creating a staircase effect. Mario auto-walks up/down the steps.
class TerrainSystem {
  final List<TerrainSegment> _segments = [];
  final double baseGroundY; // default ground Y (center of variation)
  final double screenHeight;
  final Random _rng;

  // Height variation range from baseGroundY
  static const double _maxUpOffset = -100.0; // higher ground = smaller Y
  static const double _maxDownOffset = 60.0; // lower ground = larger Y
  static const double _minSegmentWidth = 250.0;
  static const double _maxSegmentWidth = 500.0;
  static const double _maxStepDelta = 45.0; // max height change per segment

  double _rightEdge = 0; // rightmost X of generated terrain

  TerrainSystem({
    required this.baseGroundY,
    required this.screenHeight,
    Random? random,
  }) : _rng = random ?? Random();

  int get segmentCount => _segments.length;

  /// Initialize terrain with a wide flat starting area.
  void init(double screenWidth) {
    _segments.clear();
    // Starting flat area: wide enough for Mario to start
    _segments.add(TerrainSegment(
      startX: -200,
      endX: screenWidth * 3,
      groundY: baseGroundY,
    ));
    _rightEdge = screenWidth * 3;
  }

  /// Get ground Y at a given world X position.
  double getGroundYAt(double x) {
    for (final seg in _segments) {
      if (x >= seg.startX && x < seg.endX) {
        return seg.groundY;
      }
    }
    // Fallback: nearest segment
    if (_segments.isNotEmpty) {
      double minDist = double.infinity;
      double nearestY = baseGroundY;
      for (final seg in _segments) {
        final center = (seg.startX + seg.endX) / 2;
        final dist = (x - center).abs();
        if (dist < minDist) {
          minDist = dist;
          nearestY = seg.groundY;
        }
      }
      return nearestY;
    }
    return baseGroundY;
  }

  /// Scroll all segments left and generate new segments ahead.
  void update(double dt, double speed) {
    final scrollAmount = speed * dt;

    // Scroll all segments
    for (final seg in _segments) {
      seg.startX -= scrollAmount;
      seg.endX -= scrollAmount;
    }
    _rightEdge -= scrollAmount;

    // Remove segments that scrolled far off-screen left
    _segments.removeWhere((s) => s.endX < -500);

    // Generate new segments to fill the right side (up to 2 screen widths ahead)
    while (_rightEdge < 2000) {
      _generateNextSegment();
    }
  }

  void _generateNextSegment() {
    final lastSeg = _segments.isNotEmpty ? _segments.last : null;
    final lastY = lastSeg?.groundY ?? baseGroundY;

    // Determine new height: step up or down within limits
    double delta = (_rng.nextDouble() * 2 - 1) * _maxStepDelta;
    // Round to a nice step (multiples of ~15px for visible staircase feel)
    delta = (delta / 15).round() * 15.0;

    double newY = lastY + delta;
    // Clamp within allowed range
    final minY = baseGroundY + _maxUpOffset;
    final maxY = baseGroundY + _maxDownOffset;
    if (newY < minY) newY = minY;
    if (newY > maxY) newY = maxY;

    // If delta is very small, force a bigger step for visual variety
    if (delta.abs() < 10) {
      newY = lastY + (_rng.nextBool() ? 30 : -30);
      newY = newY.clamp(minY, maxY);
    }

    final width = _minSegmentWidth + _rng.nextDouble() * (_maxSegmentWidth - _minSegmentWidth);
    final startX = lastSeg?.endX ?? _rightEdge;
    final endX = startX + width;

    _segments.add(TerrainSegment(
      startX: startX,
      endX: endX,
      groundY: newY,
    ));
    _rightEdge = endX;
  }

  /// Get all visible segments for rendering (clipped to screen).
  List<TerrainSegment> getVisibleSegments(double screenLeft, double screenRight) {
    return _segments
        .where((s) => s.endX > screenLeft - 100 && s.startX < screenRight + 100)
        .toList();
  }

  /// Reset terrain system for a new game.
  void reset(double screenWidth) {
    init(screenWidth);
  }
}
