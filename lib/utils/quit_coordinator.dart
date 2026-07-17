import 'dart:async';

/// Runs the one-time shutdown barrier before asking the platform to exit.
class QuitCoordinator {
  bool _isQuitting = false;
  Future<void>? _quitFuture;

  bool get isQuitting => _isQuitting;

  Future<void> quit({
    required FutureOr<void> Function() cleanup,
    required FutureOr<void> Function() exit,
  }) {
    if (_quitFuture != null) return _quitFuture!;
    _isQuitting = true;
    return _quitFuture = Future<void>.sync(cleanup).then((_) => exit());
  }
}
