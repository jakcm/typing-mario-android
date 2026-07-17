import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flame/game.dart';
import '../game/typing_mario_game.dart';
import '../widgets/game_controls.dart';
import '../utils/quit_coordinator.dart';

class GameScreen extends StatefulWidget {
  const GameScreen({super.key, this.game});

  @visibleForTesting
  final TypingMarioGame? game;

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> with WidgetsBindingObserver {
  TypingMarioGame? _game;
  bool _gameCreated = false;
  final QuitCoordinator _quitCoordinator = QuitCoordinator();

  Future<void> _quit() => _quitCoordinator.quit(
    cleanup: () => _game?.prepareToQuit(),
    exit: SystemNavigator.pop,
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_gameCreated) return;
    _gameCreated = true;

    _game =
        widget.game ??
        TypingMarioGame(
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
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _game?.pauseGame();
      if (mounted) setState(() {});
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    // GameWidget owns Flame's component lifecycle; do not invoke onRemove()
    // manually or audio cleanup can run twice during route transitions.
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
          GameWidget<TypingMarioGame>(game: game),
          Positioned(
            top: 8,
            right: 8,
            child: SafeArea(
              left: false,
              bottom: false,
              child: GamePauseButton(
                isPaused: game.isPaused,
                onToggle: () {
                  setState(game.togglePause);
                },
              ),
            ),
          ),
          // The letter bar starts collapsed so it does not cover the game.
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: OnScreenKeyboard(
              onLetterPressed: game.onLetterTyped,
              onSpacePressed: game.onSpacePressed,
            ),
          ),
          // Draw this last, above both the Flame game and the bottom keyboard.
          Positioned(
            left: 8,
            bottom: 8,
            child: SafeArea(
              top: false,
              right: false,
              child: QuitButton(onQuit: _quit),
            ),
          ),
        ],
      ),
    );
  }
}
