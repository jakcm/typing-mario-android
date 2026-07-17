import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:typing_mario_android/utils/critical_audio_queue.dart';

void main() {
  group('fixed bounded scheduler', () {
    test('layout is exactly 12 with the reviewed per-kind bound', () {
      expect(defaultEffectSlotKinds, <EffectKind>[
        EffectKind.coin,
        EffectKind.coin,
        EffectKind.stomp,
        EffectKind.stomp,
        EffectKind.powerUp,
        EffectKind.powerUp,
        EffectKind.oneUp,
        EffectKind.damage,
        EffectKind.jump,
        EffectKind.jump,
        EffectKind.bump,
        EffectKind.gameOver,
      ]);
    });

    test(
      'only admits into a physical slot for that kind and caps gameplay at 6',
      () {
        final scheduler = BoundedPriorityAudioScheduler();
        for (var i = 0; i < 10000; i++) {
          final kind = EffectKind.values[i % 7];
          final token = scheduler.request(kind);
          if (token != null) expect(defaultEffectSlotKinds[token.slot], kind);
          expect(scheduler.diagnostics.active, lessThanOrEqualTo(6));
          expect(scheduler.diagnostics.pending, 0);
        }
      },
    );

    test(
      'priority policy preempts lower priority and stale token cannot complete',
      () {
        final scheduler = BoundedPriorityAudioScheduler(
          slotKinds: const [EffectKind.jump, EffectKind.coin],
          gameplayCapacity: 2,
        );
        final jump = scheduler.request(EffectKind.jump)!;
        final coin = scheduler.request(EffectKind.coin)!;
        final newerJump = scheduler.request(EffectKind.jump)!;
        expect(newerJump.slot, jump.slot);
        expect(scheduler.complete(jump), isFalse);
        expect(scheduler.complete(coin), isTrue);
      },
    );

    test('reward with a matching player displaces expendable at cap', () {
      final scheduler = BoundedPriorityAudioScheduler(
        slotKinds: const [EffectKind.jump, EffectKind.coin],
        gameplayCapacity: 1,
      );
      final jump = scheduler.request(EffectKind.jump)!;
      final coin = scheduler.request(EffectKind.coin)!;
      expect(coin.displacedSlot, jump.slot);
      expect(scheduler.activeKind(jump.slot), isNull);
      expect(scheduler.activeKind(coin.slot), EffectKind.coin);
    });
  });

  group('bounded effect engine races', () {
    test(
      'gameover remains logically active for its configured duration',
      () async {
        final fake = FakeEffectPlayerAdapter()..blockStops = false;
        final engine = BoundedEffectEngine(
          adapter: fake,
          gameOverDuration: const Duration(milliseconds: 30),
        );
        engine.playGameOver();
        await engine.idle;
        expect(engine.diagnostics.workers, 0);
        expect(engine.diagnostics.gameOverActive, isTrue);
        await Future<void>.delayed(const Duration(milliseconds: 40));
        expect(engine.diagnostics.gameOverActive, isFalse);
        await engine.shutdown();
      },
    );

    test('shutdown cancels gameover logical activity immediately', () async {
      final fake = FakeEffectPlayerAdapter()..blockStops = false;
      final engine = BoundedEffectEngine(
        adapter: fake,
        gameOverDuration: const Duration(seconds: 1),
      );
      engine.playGameOver();
      await engine.idle;
      expect(engine.diagnostics.gameOverActive, isTrue);
      await engine.shutdown();
      expect(engine.diagnostics.gameOverActive, isFalse);
    });

    test('latest pending wins and stale await cannot resume', () async {
      final fake = FakeEffectPlayerAdapter();
      final engine = BoundedEffectEngine(
        adapter: fake,
        slotKinds: const [EffectKind.coin, EffectKind.gameOver],
        gameplayCapacity: 1,
      );
      engine.play(EffectKind.coin);
      await fake.waitForStopCall();
      engine.play(EffectKind.coin);
      engine.play(EffectKind.coin);
      expect(engine.diagnostics.pending, 1);
      fake.releaseStops();
      await engine.idle;
      expect(fake.resumedKinds, [EffectKind.coin]);
      await engine.shutdown();
    });

    test('concurrent shutdown returns and joins identical future', () async {
      final fake = FakeEffectPlayerAdapter();
      final engine = BoundedEffectEngine(adapter: fake);
      engine.play(EffectKind.coin);
      await fake.waitForStopCall();
      final first = engine.shutdown();
      final second = engine.shutdown();
      expect(identical(first, second), isTrue);
      var completed = false;
      second.then((_) => completed = true);
      await Future<void>.delayed(Duration.zero);
      expect(completed, isFalse);
      fake.releaseStops();
      await first;
    });

    test(
      'gameover has one tracked worker; stale slot cannot erase it; idle waits',
      () async {
        final fake = FakeEffectPlayerAdapter();
        final engine = BoundedEffectEngine(adapter: fake);
        engine.play(EffectKind.coin);
        await fake.waitForStopCall();
        engine.playGameOver();
        engine.playGameOver();
        expect(engine.diagnostics.gameOverActive, isTrue);
        expect(engine.diagnostics.workers, greaterThanOrEqualTo(1));
        final idle = engine.idle;
        var completed = false;
        idle.then((_) => completed = true);
        await Future<void>.delayed(Duration.zero);
        expect(completed, isFalse);
        fake.releaseStops();
        await idle;
        expect(
          fake.resumedKinds.where((k) => k == EffectKind.gameOver),
          hasLength(1),
        );
      },
    );

    test(
      'shutdown stops each unique physical player exactly once per pass',
      () async {
        final fake = FakeEffectPlayerAdapter()..blockStops = false;
        final engine = BoundedEffectEngine(adapter: fake);
        await engine.shutdown();
        expect(fake.stopSlots, hasLength(24));
        expect(fake.stopSlots.take(12).toSet(), hasLength(12));
        expect(fake.stopSlots.skip(12).toSet(), hasLength(12));
      },
    );
  });

  group('serialized latest desired playback', () {
    test('fast pause/resume deterministically converges to play', () async {
      final fake = FakeDesiredPlayback();
      final controller = DesiredPlaybackController(fake);
      controller.setDesired(true);
      await fake.started.future;
      controller.setDesired(false);
      controller.setDesired(true);
      fake.release.complete();
      await controller.idle;
      expect(fake.operations.last, 'play');
    });

    test(
      'persistent failure does not retry without explicit request',
      () async {
        final fake = FakeDesiredPlayback(blockFirst: false);
        fake.failPlay = true;
        final controller = DesiredPlaybackController(fake);
        controller.setDesired(true);
        await controller.idle;
        await Future<void>.delayed(Duration.zero);
        expect(fake.operations, ['play']);
      },
    );

    test(
      'explicit recovery retries even when desired state was applied',
      () async {
        final fake = FakeDesiredPlayback(blockFirst: false);
        final controller = DesiredPlaybackController(fake);
        controller.setDesired(true);
        await controller.idle;
        controller.retryPlaying();
        await controller.idle;
        expect(fake.operations, ['play', 'play']);
      },
    );

    test('explicit start always gets one attempt', () async {
      final fake = FakeDesiredPlayback(blockFirst: false);
      final controller = DesiredPlaybackController(fake);
      controller.requestPlaying();
      await controller.idle;
      controller.requestPlaying();
      await controller.idle;
      expect(fake.operations, ['play', 'play']);
    });

    test('shutdown joins in-flight operation then final-stops', () async {
      final fake = FakeDesiredPlayback();
      final controller = DesiredPlaybackController(fake);
      controller.setDesired(true);
      await fake.started.future;
      final shutdown = controller.shutdown();
      var completed = false;
      shutdown.then((_) => completed = true);
      await Future<void>.delayed(Duration.zero);
      expect(completed, isFalse);
      fake.release.complete();
      await shutdown;
      expect(fake.operations.last, 'stop');
    });
  });

  group('bounded BGM watchdog recovery', () {
    test('persistent failure exhausts a finite backoff budget', () {
      var now = Duration.zero;
      final gate = BgmRecoveryGate(
        now: () => now,
        retryDelays: const [
          Duration.zero,
          Duration(seconds: 1),
          Duration(seconds: 2),
        ],
      );
      gate.beginExplicitAttempt();
      expect(gate.tryWatchdogRecovery(), isTrue);
      expect(gate.tryWatchdogRecovery(), isFalse);
      now = const Duration(seconds: 1);
      expect(gate.tryWatchdogRecovery(), isTrue);
      now = const Duration(seconds: 3);
      expect(gate.tryWatchdogRecovery(), isTrue);
      now = const Duration(days: 365);
      expect(gate.tryWatchdogRecovery(), isFalse);
    });

    test('successful playback resets budget for a later interruption', () {
      final gate = BgmRecoveryGate(now: () => Duration.zero);
      gate.beginExplicitAttempt();
      while (gate.tryWatchdogRecovery()) {}
      expect(gate.tryWatchdogRecovery(), isFalse);
      gate.recordPlaying();
      expect(gate.tryWatchdogRecovery(), isTrue);
    });

    test('explicit resume re-arms an exhausted circuit', () {
      final gate = BgmRecoveryGate(now: () => Duration.zero);
      gate.beginExplicitAttempt();
      while (gate.tryWatchdogRecovery()) {}
      gate.beginExplicitAttempt();
      expect(gate.tryWatchdogRecovery(), isTrue);
    });
  });

  test('terminal lifecycle is manager-level single-flight', () async {
    final coordinator = TerminalAudioLifecycleCoordinator();
    final blocker = Completer<void>();
    var operations = 0;
    Future<void> shutdown() async {
      operations++;
      await blocker.future;
    }

    final first = coordinator.shutdown(shutdown);
    final second = coordinator.shutdown(shutdown);
    expect(identical(first, second), isTrue);
    expect(operations, 1);
    blocker.complete();
    await Future.wait([first, second]);
    expect(operations, 1);
  });
}

class FakeEffectPlayerAdapter implements EffectPlayerAdapter {
  bool blockStops = true;
  int stopCalls = 0;
  final List<int> stopSlots = [];
  final List<EffectKind> resumedKinds = [];
  final List<Completer<void>> _gates = [];
  Completer<void>? _seen;

  @override
  Future<void> stop(int slot, EffectKind kind) async {
    stopCalls++;
    stopSlots.add(slot);
    _seen?.complete();
    _seen = null;
    if (blockStops) {
      final gate = Completer<void>();
      _gates.add(gate);
      await gate.future;
    }
  }

  @override
  Future<void> resume(int slot, EffectKind kind, double volume) async {
    resumedKinds.add(kind);
  }

  Future<void> waitForStopCall() {
    if (stopCalls > 0) return Future.value();
    _seen = Completer<void>();
    return _seen!.future;
  }

  void releaseStops() {
    blockStops = false;
    for (final gate in _gates) {
      if (!gate.isCompleted) gate.complete();
    }
  }
}

class FakeDesiredPlayback implements DesiredPlaybackAdapter {
  FakeDesiredPlayback({this.blockFirst = true});
  final bool blockFirst;
  final operations = <String>[];
  final started = Completer<void>();
  final release = Completer<void>();
  bool failPlay = false;
  bool _first = true;

  Future<void> _record(String operation) async {
    operations.add(operation);
    if (_first) {
      _first = false;
      started.complete();
      if (blockFirst) await release.future;
    }
    if (operation == 'play' && failPlay) throw StateError('failure');
  }

  @override
  Future<void> play() => _record('play');
  @override
  Future<void> stop() => _record('stop');
}
