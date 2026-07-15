import 'package:flutter/material.dart';
import '../utils/pixel_painter.dart';

class MainMenuScreen extends StatefulWidget {
  const MainMenuScreen({super.key});

  @override
  State<MainMenuScreen> createState() => _MainMenuScreenState();
}

class _MainMenuScreenState extends State<MainMenuScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  late Animation<double> _bounceAnim;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..repeat(reverse: true);
    _bounceAnim = Tween<double>(begin: 0, end: -15).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF5C94FC), Color(0xFF87CEEB), Color(0xFF87CEEB)],
            stops: [0.0, 0.5, 1.0],
          ),
        ),
        child: Stack(
          children: [
            // Clouds
            CustomPaint(
              size: Size.infinite,
              painter: _MenuCloudPainter(),
            ),
            // Ground
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Container(
                height: 80,
                decoration: const BoxDecoration(
                  color: Color(0xFF8B4513),
                  border: Border(
                    top: BorderSide(color: Color(0xFF228B22), width: 20),
                  ),
                ),
              ),
            ),
            // Grass tufts on top of ground
            Positioned(
              bottom: 78,
              left: 0,
              right: 0,
              child: CustomPaint(
                size: Size(MediaQuery.of(context).size.width, 25),
                painter: _GrassTuftsPainter(),
              ),
            ),
            // Content
            Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Animated Mario
                  AnimatedBuilder(
                    animation: _bounceAnim,
                    builder: (context, child) {
                      return Transform.translate(
                        offset: Offset(0, _bounceAnim.value),
                        child: child,
                      );
                    },
                    child: SizedBox(
                      width: 80,
                      height: 80,
                      child: CustomPaint(
                        painter: _MenuMarioPainter(),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  // Title with shadow
                  const Text(
                    'TYPING MARIO',
                    style: TextStyle(
                      fontSize: 48,
                      fontWeight: FontWeight.w900,
                      color: Colors.red,
                      fontFamily: 'monospace',
                      letterSpacing: 4,
                      shadows: [
                        Shadow(offset: Offset(3, 3), color: Colors.black87),
                        Shadow(offset: Offset(-1, -1), color: Colors.white24),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    '🎹 Type Letters to Save Mario! 🎮',
                    style: TextStyle(
                      fontSize: 20,
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'monospace',
                      shadows: [
                        Shadow(offset: Offset(2, 2), color: Colors.black54),
                      ],
                    ),
                  ),
                  const SizedBox(height: 30),
                  // Start button
                  GestureDetector(
                    onTap: () {
                      Navigator.pushNamed(context, '/game');
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 60,
                        vertical: 20,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.red,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.white, width: 4),
                        boxShadow: const [
                          BoxShadow(
                            color: Colors.black38,
                            offset: Offset(4, 4),
                            blurRadius: 0,
                          ),
                        ],
                      ),
                      child: const Text(
                        'START GAME',
                        style: TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.w900,
                          color: Colors.white,
                          fontFamily: 'monospace',
                          letterSpacing: 3,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MenuCloudPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.white.withValues(alpha: 0.8);
    _drawCloud(canvas, paint, Offset(size.width * 0.15, 60), 1.2);
    _drawCloud(canvas, paint, Offset(size.width * 0.55, 40), 0.9);
    _drawCloud(canvas, paint, Offset(size.width * 0.85, 75), 1.0);
  }

  void _drawCloud(Canvas canvas, Paint paint, Offset pos, double scale) {
    final s = 12.0 * scale;
    for (var entry in [
      [0, 1, 4], [1, -1, 6], [2, -2, 8], [3, -2, 8],
      [4, -1, 6], [5, 0, 4]
    ]) {
      for (int x = entry[1]; x < entry[1] + entry[2]; x++) {
        canvas.drawRect(
          Rect.fromLTWH(pos.dx + x * s, pos.dy + entry[0] * s, s, s),
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _GrassTuftsPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = const Color(0xFF32CD32);
    final s = 8.0;
    for (double x = 0; x < size.width; x += s * 3) {
      canvas.drawRect(Rect.fromLTWH(x, 10, s, s), paint);
      canvas.drawRect(Rect.fromLTWH(x + s, 5, s, s * 1.5), paint);
      canvas.drawRect(Rect.fromLTWH(x + s * 2, 10, s, s), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _MenuMarioPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    PixelPainter.drawMario(canvas, Offset.zero, size.width / 60, frame: 0);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
