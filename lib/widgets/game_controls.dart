import 'package:flutter/material.dart';

class QuitButton extends StatelessWidget {
  final VoidCallback onQuit;
  final String tooltip;

  const QuitButton({
    super.key,
    required this.onQuit,
    this.tooltip = 'Quit game',
  });

  @override
  Widget build(BuildContext context) {
    return Transform.scale(
      scale: 0.5,
      alignment: Alignment.bottomLeft,
      child: Tooltip(
        message: tooltip,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onQuit,
            borderRadius: BorderRadius.circular(8),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
              decoration: BoxDecoration(
                color: const Color(0xFFD32F2F).withValues(alpha: 0.94),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.white, width: 1.5),
                boxShadow: const [
                  BoxShadow(color: Colors.black45, offset: Offset(2, 2)),
                ],
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.exit_to_app, color: Colors.white, size: 18),
                  SizedBox(width: 6),
                  Text(
                    'QUIT',
                    style: TextStyle(
                      color: Colors.white,
                      fontFamily: 'monospace',
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.2,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class GamePauseButton extends StatelessWidget {
  final bool isPaused;
  final VoidCallback onToggle;

  const GamePauseButton({
    super.key,
    required this.isPaused,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final tooltip = isPaused ? 'Resume game' : 'Pause game';
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          onTap: onToggle,
          borderRadius: BorderRadius.circular(18),
          child: SizedBox(
            width: 36,
            height: 36,
            child: Icon(
              isPaused ? Icons.play_arrow : Icons.pause,
              semanticLabel: tooltip,
              color: Colors.white,
              size: 23,
            ),
          ),
        ),
      ),
    );
  }
}

class OnScreenKeyboard extends StatefulWidget {
  final void Function(String letter) onLetterPressed;
  final VoidCallback onSpacePressed;

  const OnScreenKeyboard({
    super.key,
    required this.onLetterPressed,
    required this.onSpacePressed,
  });

  @override
  State<OnScreenKeyboard> createState() => _OnScreenKeyboardState();
}

class _OnScreenKeyboardState extends State<OnScreenKeyboard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.sizeOf(context).width;
    final buttonHeight = (screenWidth / 34 * 0.72).clamp(28.0, 48.0);

    return Container(
      color: Colors.black.withValues(alpha: 0.45),
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          if (_expanded) ...[
            const Expanded(flex: 2, child: SizedBox.shrink()),
            ...'ABCDEFGHIJKLM'
                .split('')
                .map(
                  (letter) =>
                      Expanded(child: _letterButton(letter, buttonHeight)),
                ),
            Expanded(flex: 2, child: _spaceButton(buttonHeight)),
            ...'NOPQRSTUVWXYZ'
                .split('')
                .map(
                  (letter) =>
                      Expanded(child: _letterButton(letter, buttonHeight)),
                ),
          ] else
            const Spacer(),
          _toggleButton(buttonHeight),
        ],
      ),
    );
  }

  Widget _toggleButton(double height) {
    final tooltip = _expanded
        ? 'Collapse letter keyboard'
        : 'Expand letter keyboard';
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => setState(() => _expanded = !_expanded),
        child: Container(
          width: height * 1.25,
          height: height,
          margin: const EdgeInsets.only(left: 1, right: 3),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: Colors.blueGrey.shade800.withValues(alpha: 0.95),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: Colors.white70),
          ),
          child: Icon(
            _expanded ? Icons.keyboard_arrow_down : Icons.keyboard_arrow_up,
            color: Colors.white,
            semanticLabel: tooltip,
          ),
        ),
      ),
    );
  }

  Widget _letterButton(String letter, double height) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => widget.onLetterPressed(letter),
      child: Container(
        height: height,
        alignment: Alignment.center,
        margin: const EdgeInsets.symmetric(horizontal: 0.5),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.9),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: Colors.blueGrey),
        ),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            letter,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w900,
              color: Color(0xFF333333),
              fontFamily: 'monospace',
            ),
          ),
        ),
      ),
    );
  }

  Widget _spaceButton(double height) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onSpacePressed,
      child: Container(
        height: height,
        alignment: Alignment.center,
        margin: const EdgeInsets.symmetric(horizontal: 1),
        decoration: BoxDecoration(
          color: Colors.blue.shade600.withValues(alpha: 0.9),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: Colors.white, width: 1.5),
        ),
        child: const FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            'JUMP',
            style: TextStyle(
              fontSize: 14,
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
