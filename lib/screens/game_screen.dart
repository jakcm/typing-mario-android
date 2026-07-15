import 'package:flutter/material.dart';
import 'package:flame/game.dart';
import '../game/typing_mario_game.dart';

class GameScreen extends StatefulWidget {
  const GameScreen({super.key});

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> {
  TypingMarioGame? _game;

  @override
  void initState() {
    super.initState();
    _game = TypingMarioGame(
      onGameOver: (int finalScore) {
        if (mounted) {
          Navigator.pushReplacementNamed(
            context,
            '/gameover',
            arguments: finalScore,
          );
        }
      },
    );
  }

  @override
  void dispose() {
    _game?.onRemove();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final game = _game;
    if (game == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return Scaffold(
      body: Stack(
        children: [
          // Flame game widget
          GameWidget<TypingMarioGame>(
            game: game,
          ),
          // On-screen keyboard fallback at the bottom
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: _OnScreenKeyboard(
              onKeyPressed: (String letter) {
                game.onLetterTyped(letter);
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// Compact two-row keyboard: A-M (row 1), N-Z (row 2).
/// All 26 letters visible on screen, no scrolling needed.
class _OnScreenKeyboard extends StatelessWidget {
  final void Function(String letter) onKeyPressed;

  const _OnScreenKeyboard({required this.onKeyPressed});

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    const row1 = 'ABCDEFGHIJKLM'; // 13 letters
    const row2 = 'NOPQRSTUVWXYZ'; // 13 letters

    return Container(
      color: Colors.black.withValues(alpha: 0.45),
      padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildRow(row1.split(''), screenWidth),
          const SizedBox(height: 1),
          _buildRow(row2.split(''), screenWidth),
        ],
      ),
    );
  }

  Widget _buildRow(List<String> letters, double screenWidth) {
    final availableWidth = screenWidth - 20;
    final btnW = (availableWidth / 13).clamp(20.0, 36.0);
    final btnH = btnW * 0.72;

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: letters.map((letter) {
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 0.5),
          child: GestureDetector(
            onTap: () => onKeyPressed(letter),
            child: Container(
              width: btnW,
              height: btnH,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.9),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: Colors.blueGrey, width: 1),
              ),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  letter,
                  style: TextStyle(
                    fontSize: btnW * 0.5,
                    fontWeight: FontWeight.w900,
                    color: const Color(0xFF333333),
                    fontFamily: 'monospace',
                  ),
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}
