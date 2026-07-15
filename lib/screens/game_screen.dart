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
          // On-screen keyboard: single row A-M + SPACE + N-Z
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: _OnScreenKeyboard(
              onLetterPressed: (String letter) {
                game.onLetterTyped(letter);
              },
              onSpacePressed: () {
                game.onSpacePressed();
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// Single-row keyboard: A B C D E F G H I J K L M [SPACE] N O P Q R S T U V W X Y Z
/// Layout: [1-letter margin] 26 letters + space bar [1-letter margin]
/// Space bar is 2× letter width, centered between M and N.
class _OnScreenKeyboard extends StatelessWidget {
  final void Function(String letter) onLetterPressed;
  final VoidCallback onSpacePressed;

  const _OnScreenKeyboard({
    required this.onLetterPressed,
    required this.onSpacePressed,
  });

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    const marginUnits = 3.0;
    const spaceUnits = 2.0;
    const letterCount = 26;
    // left margin(3) + 13 + space(2) + 13 + right margin(3) = 34 units
    const totalLayoutUnits = marginUnits * 2 + letterCount + spaceUnits; // 34

    final unitWidth = screenWidth / totalLayoutUnits;
    final btnHeight = unitWidth * 0.72;

    final leftLetters = 'ABCDEFGHIJKLM'.split('');
    final rightLetters = 'NOPQRSTUVWXYZ'.split('');

    return Container(
      color: Colors.black.withValues(alpha: 0.45),
      padding: EdgeInsets.symmetric(vertical: 2, horizontal: unitWidth * marginUnits),
      child: Row(
        children: [
          // A-M
          ...leftLetters.map((l) => _buildLetterBtn(l, unitWidth, btnHeight)),
          // SPACE bar
          _buildSpaceBtn(unitWidth * spaceUnits, btnHeight),
          // N-Z
          ...rightLetters.map((l) => _buildLetterBtn(l, unitWidth, btnHeight)),
        ],
      ),
    );
  }

  Widget _buildLetterBtn(String letter, double width, double height) {
    return GestureDetector(
      onTap: () => onLetterPressed(letter),
      child: Container(
        width: width,
        height: height,
        alignment: Alignment.center,
        margin: const EdgeInsets.symmetric(horizontal: 0.5),
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
              fontSize: width * 0.5,
              fontWeight: FontWeight.w900,
              color: const Color(0xFF333333),
              fontFamily: 'monospace',
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSpaceBtn(double width, double height) {
    return GestureDetector(
      onTap: onSpacePressed,
      child: Container(
        width: width,
        height: height,
        alignment: Alignment.center,
        margin: const EdgeInsets.symmetric(horizontal: 1),
        decoration: BoxDecoration(
          color: Colors.blue.shade600.withValues(alpha: 0.9),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: Colors.white, width: 1.5),
        ),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            'JUMP',
            style: TextStyle(
              fontSize: width * 0.2,
              fontWeight: FontWeight.w900,
              color: Colors.white,
              fontFamily: 'monospace',
            ),
          ),
        ),
      ),
    );
  }
}
