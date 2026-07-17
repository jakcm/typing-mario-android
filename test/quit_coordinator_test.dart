import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:typing_mario_android/utils/quit_coordinator.dart';

void main() {
  test(
    'quit awaits cleanup before exiting and ignores repeated taps',
    () async {
      final events = <String>[];
      final cleanupGate = Completer<void>();
      final coordinator = QuitCoordinator();

      final first = coordinator.quit(
        cleanup: () async {
          events.add('cleanup-start');
          await cleanupGate.future;
          events.add('cleanup-done');
        },
        exit: () async => events.add('exit'),
      );
      final second = coordinator.quit(
        cleanup: () async => events.add('duplicate-cleanup'),
        exit: () async => events.add('duplicate-exit'),
      );

      expect(events, <String>['cleanup-start']);
      cleanupGate.complete();
      await Future.wait([first, second]);

      expect(events, <String>['cleanup-start', 'cleanup-done', 'exit']);
      expect(coordinator.isQuitting, isTrue);
    },
  );
}
