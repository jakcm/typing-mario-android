import 'dart:async';

enum EffectPriority { expendable, important, reward }

enum EffectKind { coin, stomp, powerUp, oneUp, damage, jump, bump, gameOver }

extension EffectKindPolicy on EffectKind {
  EffectPriority get priority => switch (this) {
    EffectKind.jump || EffectKind.bump => EffectPriority.expendable,
    EffectKind.damage => EffectPriority.important,
    _ => EffectPriority.reward,
  };
}

/// The complete native SFX allocation. There are twelve players for the whole
/// process, not `logical capacity * asset count` players.
const List<EffectKind> defaultEffectSlotKinds = <EffectKind>[
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
];

class AudioDiagnostics {
  const AudioDiagnostics({
    required this.active,
    required this.pending,
    required this.dropped,
    required this.preemptions,
    required this.accepted,
    this.workers = 0,
    this.gameOverActive = false,
    this.accepting = true,
  });
  final int active;
  final int pending;
  final int dropped;
  final int preemptions;
  final int accepted;
  final int workers;
  final bool gameOverActive;
  final bool accepting;
}

class AudioSlotToken {
  const AudioSlotToken({
    required this.slot,
    required this.kind,
    required this.sessionGeneration,
    required this.slotGeneration,
    this.displacedSlot,
  });
  final int slot;
  final EffectKind kind;
  final int sessionGeneration;
  final int slotGeneration;
  final int? displacedSlot;
}

class _SlotState {
  int generation = 0;
  int sequence = 0;
  bool active = false;
}

/// Fixed-layout, no-backlog admission policy. A request can only occupy a
/// physical player already preloaded for its asset.
class BoundedPriorityAudioScheduler {
  BoundedPriorityAudioScheduler({
    List<EffectKind> slotKinds = defaultEffectSlotKinds,
    this.gameplayCapacity = 6,
  }) : slotKinds = List.unmodifiable(slotKinds),
       _slots = List.generate(slotKinds.length, (_) => _SlotState());

  final List<EffectKind> slotKinds;
  final int gameplayCapacity;
  final List<_SlotState> _slots;
  int _session = 0;
  int _sequence = 0;
  int _dropped = 0;
  int _preemptions = 0;
  int _accepted = 0;

  int get _active => _slots.where((slot) => slot.active).length;
  AudioDiagnostics get diagnostics => AudioDiagnostics(
    active: _active,
    pending: 0,
    dropped: _dropped,
    preemptions: _preemptions,
    accepted: _accepted,
  );

  EffectKind? activeKind(int slot) =>
      _slots[slot].active ? slotKinds[slot] : null;

  AudioSlotToken? request(EffectKind kind) {
    if (kind == EffectKind.gameOver) {
      _dropped++;
      return null;
    }
    final candidates = <int>[
      for (var i = 0; i < slotKinds.length; i++)
        if (slotKinds[i] == kind) i,
    ];
    if (candidates.isEmpty) {
      _dropped++;
      return null;
    }
    var index = candidates.where((i) => !_slots[i].active).firstOrNull ?? -1;
    int? displacedSlot;
    if (index >= 0 && _active >= gameplayCapacity) {
      displacedSlot = _oldestLowerPriority(kind);
      if (displacedSlot == null) index = -1;
    }
    // Asset-specific pools can replace only their oldest same-kind instance.
    if (index < 0) {
      final active = candidates.where((i) => _slots[i].active).toList();
      if (active.isNotEmpty) {
        active.sort((a, b) => _slots[a].sequence.compareTo(_slots[b].sequence));
        index = active.first;
        _preemptions++;
      }
    }
    if (index < 0) {
      _dropped++;
      return null;
    }
    final state = _slots[index];
    if (displacedSlot != null) {
      _slots[displacedSlot].active = false;
      _slots[displacedSlot].generation++;
      _preemptions++;
    }
    state.active = true;
    state.generation++;
    state.sequence = ++_sequence;
    _accepted++;
    return AudioSlotToken(
      slot: index,
      kind: kind,
      sessionGeneration: _session,
      slotGeneration: state.generation,
      displacedSlot: displacedSlot,
    );
  }

  int? _oldestLowerPriority(EffectKind incoming) {
    final candidates = <int>[
      for (var i = 0; i < _slots.length; i++)
        if (_slots[i].active &&
            slotKinds[i].priority.index < incoming.priority.index)
          i,
    ];
    if (candidates.isEmpty) return null;
    candidates.sort((a, b) => _slots[a].sequence.compareTo(_slots[b].sequence));
    return candidates.first;
  }

  bool isCurrent(AudioSlotToken token) =>
      token.sessionGeneration == _session &&
      token.slot >= 0 &&
      token.slot < _slots.length &&
      slotKinds[token.slot] == token.kind &&
      _slots[token.slot].active &&
      _slots[token.slot].generation == token.slotGeneration;

  bool complete(AudioSlotToken token) {
    if (!isCurrent(token)) return false;
    _slots[token.slot].active = false;
    return true;
  }

  void resetSession() {
    _session++;
    for (final slot in _slots) {
      slot.active = false;
      slot.generation++;
    }
  }
}

abstract interface class EffectPlayerAdapter {
  Future<void> stop(int slot, EffectKind kind);
  Future<void> resume(int slot, EffectKind kind, double volume);
}

class _EffectCommand {
  const _EffectCommand(this.token, this.volume);
  final AudioSlotToken token;
  final double volume;
}

class BoundedEffectEngine {
  BoundedEffectEngine({
    required this.adapter,
    List<EffectKind> slotKinds = defaultEffectSlotKinds,
    int gameplayCapacity = 6,
    this.gameOverDuration = const Duration(milliseconds: 2350),
  }) : slotKinds = List.unmodifiable(slotKinds),
       scheduler = BoundedPriorityAudioScheduler(
         slotKinds: slotKinds,
         gameplayCapacity: gameplayCapacity,
       ),
       _desired = List.filled(slotKinds.length, null),
       _workers = List.filled(slotKinds.length, null),
       _timers = List.filled(slotKinds.length, null);

  final EffectPlayerAdapter adapter;
  final List<EffectKind> slotKinds;
  final BoundedPriorityAudioScheduler scheduler;
  final Duration gameOverDuration;
  final List<_EffectCommand?> _desired;
  final List<Future<void>?> _workers;
  final List<Timer?> _timers;
  bool _accepting = true;
  bool _gameOverExclusive = false;
  int _generation = 0;
  int _rejected = 0;
  Future<void>? _gameOverWorker;
  Timer? _gameOverTimer;
  bool _gameOverActive = false;
  Future<void>? _shutdownFuture;

  int get _gameOverSlot => slotKinds.indexOf(EffectKind.gameOver);

  AudioDiagnostics get diagnostics {
    final base = scheduler.diagnostics;
    final gameover = _gameOverActive;
    return AudioDiagnostics(
      active: base.active + (gameover ? 1 : 0),
      pending: _desired.whereType<_EffectCommand>().length,
      dropped: base.dropped + _rejected,
      preemptions: base.preemptions,
      accepted: base.accepted,
      workers:
          _workers.whereType<Future<void>>().length +
          (_gameOverWorker != null ? 1 : 0),
      gameOverActive: gameover,
      accepting: _accepting,
    );
  }

  void play(EffectKind kind, {double volume = 1}) {
    if (!_accepting || _gameOverExclusive || kind == EffectKind.gameOver) {
      _rejected++;
      return;
    }
    final token = scheduler.request(kind);
    if (token == null) return;
    if (token.displacedSlot case final displaced?) {
      _timers[displaced]?.cancel();
      _timers[displaced] = null;
      _desired[displaced] = null;
      unawaited(adapter.stop(displaced, slotKinds[displaced]));
    }
    _timers[token.slot]?.cancel();
    _timers[token.slot] = null;
    _desired[token.slot] = _EffectCommand(token, volume);
    _ensureWorker(token.slot);
  }

  void _ensureWorker(int slot) {
    if (_workers[slot] != null) return;
    final worker = _runSlot(slot);
    _workers[slot] = worker;
    unawaited(
      worker.whenComplete(() {
        if (!identical(_workers[slot], worker)) return;
        _workers[slot] = null;
        if (_desired[slot] != null && _accepting) _ensureWorker(slot);
      }),
    );
  }

  Future<void> _runSlot(int slot) async {
    while (_desired[slot] != null) {
      final command = _desired[slot]!;
      _desired[slot] = null;
      final generation = _generation;
      await adapter.stop(slot, slotKinds[slot]);
      if (!_valid(command, generation)) continue;
      await adapter.resume(slot, command.token.kind, command.volume);
      if (!_valid(command, generation)) {
        await adapter.stop(slot, slotKinds[slot]);
        continue;
      }
      _timers[slot]?.cancel();
      late final Timer timer;
      timer = Timer(_duration(command.token.kind), () {
        if (identical(_timers[slot], timer)) _timers[slot] = null;
        scheduler.complete(command.token);
      });
      _timers[slot] = timer;
    }
  }

  bool _valid(_EffectCommand command, int generation) =>
      _accepting &&
      !_gameOverExclusive &&
      generation == _generation &&
      scheduler.isCurrent(command.token) &&
      (_desired[command.token.slot] == null ||
          _desired[command.token.slot]!.token.slotGeneration <=
              command.token.slotGeneration);

  void playGameOver({double volume = 1}) {
    if (!_accepting || _gameOverExclusive || _gameOverSlot < 0) return;
    _gameOverExclusive = true;
    _gameOverActive = true;
    _generation++;
    scheduler.resetSession();
    _clearDesiredAndTimers();
    final generation = _generation;
    final worker = _runGameOver(generation, volume);
    _gameOverWorker = worker;
    unawaited(
      worker.whenComplete(() {
        if (identical(_gameOverWorker, worker)) _gameOverWorker = null;
      }),
    );
  }

  Future<void> _runGameOver(int generation, double volume) async {
    await Future.wait(_stopEveryPlayer());
    await Future.wait(_workers.whereType<Future<void>>());
    if (!_accepting || generation != _generation) return;
    await adapter.resume(_gameOverSlot, EffectKind.gameOver, volume);
    if (!_accepting || generation != _generation) {
      await adapter.stop(_gameOverSlot, EffectKind.gameOver);
      return;
    }
    _gameOverTimer?.cancel();
    late final Timer timer;
    timer = Timer(gameOverDuration, () {
      if (!identical(_gameOverTimer, timer) || generation != _generation) {
        return;
      }
      _gameOverTimer = null;
      _gameOverActive = false;
    });
    _gameOverTimer = timer;
  }

  void _clearDesiredAndTimers() {
    for (var i = 0; i < slotKinds.length; i++) {
      _desired[i] = null;
      _timers[i]?.cancel();
      _timers[i] = null;
    }
  }

  List<Future<void>> _stopEveryPlayer() => [
    for (var slot = 0; slot < slotKinds.length; slot++)
      adapter.stop(slot, slotKinds[slot]),
  ];

  Future<void> get idle async {
    while (true) {
      final snapshot = <Future<void>>[
        ..._workers.whereType<Future<void>>(),
        // ignore: use_null_aware_elements -- keep compatibility with project SDK.
        if (_gameOverWorker case final worker?) worker,
      ];
      if (snapshot.isEmpty) return;
      await Future.wait(snapshot);
      final current = <Future<void>>[
        ..._workers.whereType<Future<void>>(),
        // ignore: use_null_aware_elements -- keep compatibility with project SDK.
        if (_gameOverWorker case final worker?) worker,
      ];
      if (current.isEmpty) return;
    }
  }

  Future<void> shutdown() => _shutdownFuture ??= _doShutdown();

  Future<void> _doShutdown() async {
    _accepting = false;
    _generation++;
    _gameOverTimer?.cancel();
    _gameOverTimer = null;
    _gameOverActive = false;
    scheduler.resetSession();
    _clearDesiredAndTimers();
    final firstStops = _stopEveryPlayer();
    final historical = <Future<void>>[
      ..._workers.whereType<Future<void>>(),
      // ignore: use_null_aware_elements -- keep compatibility with project SDK.
      if (_gameOverWorker case final worker?) worker,
    ];
    await Future.wait([...firstStops, ...historical]);
    await Future.wait(_stopEveryPlayer());
  }

  // Measured WAV lengths plus ~100-130ms of SoundPool scheduling margin.
  static Duration _duration(EffectKind kind) => switch (kind) {
    EffectKind.coin => const Duration(milliseconds: 520), // WAV 420ms
    EffectKind.stomp => const Duration(milliseconds: 250), // WAV 150ms
    EffectKind.powerUp => const Duration(milliseconds: 700), // WAV 595ms
    EffectKind.oneUp => const Duration(milliseconds: 800), // WAV 690ms
    EffectKind.damage => const Duration(milliseconds: 220), // bump WAV 120ms
    EffectKind.jump => const Duration(milliseconds: 320), // WAV 220ms
    EffectKind.bump => const Duration(milliseconds: 220), // WAV 120ms
    EffectKind.gameOver => const Duration(milliseconds: 2350), // WAV 2220ms
  };
}

typedef MonotonicNow = Duration Function();

/// Pure circuit breaker for periodic BGM recovery. Explicit user/lifecycle
/// starts re-arm it; watchdog calls are admitted only a finite number of times.
class BgmRecoveryGate {
  BgmRecoveryGate({
    MonotonicNow? now,
    List<Duration> retryDelays = const [
      Duration.zero,
      Duration(seconds: 1),
      Duration(seconds: 3),
    ],
  }) : _now = now ?? _stopwatchNow,
       _retryDelays = List.unmodifiable(retryDelays);

  static final Stopwatch _clock = Stopwatch()..start();
  static Duration _stopwatchNow() => _clock.elapsed;

  final MonotonicNow _now;
  final List<Duration> _retryDelays;
  int _nextRetry = 0;
  Duration _notBefore = Duration.zero;

  void beginExplicitAttempt() {
    _nextRetry = 0;
    _notBefore = _now();
  }

  bool tryWatchdogRecovery() {
    if (_nextRetry >= _retryDelays.length || _now() < _notBefore) return false;
    _nextRetry++;
    if (_nextRetry < _retryDelays.length) {
      _notBefore = _now() + _retryDelays[_nextRetry];
    }
    return true;
  }

  void recordPlaying() => beginExplicitAttempt();
}

/// Small plugin-independent single-flight primitive used by AudioManager's
/// terminal barrier. The operation is invoked exactly once and all callers join.
class TerminalAudioLifecycleCoordinator {
  Future<void>? _shutdownFuture;

  Future<void> shutdown(Future<void> Function() operation) =>
      _shutdownFuture ??= operation();
}

abstract interface class DesiredPlaybackAdapter {
  Future<void> play();
  Future<void> stop();
}

/// Serializes BGM operations and coalesces rapid requests to the latest desired
/// state. A failed operation is considered attempted and is never self-retried.
class DesiredPlaybackController {
  DesiredPlaybackController(this.adapter);
  final DesiredPlaybackAdapter adapter;
  bool _desired = false;
  bool? _applied;
  int _revision = 0;
  int _processed = 0;
  bool _terminal = false;
  Future<void>? _worker;
  Future<void>? _shutdownFuture;

  bool get desiredPlaying => _desired;

  void setDesired(bool playing) {
    if (_terminal) return;
    _desired = playing;
    _revision++;
    _ensureWorker();
  }

  /// Explicit lifecycle/user start. Unlike a state assignment, every call is
  /// allowed one native play attempt.
  void requestPlaying() {
    if (_terminal) return;
    _desired = true;
    _applied = null;
    _revision++;
    _ensureWorker();
  }

  /// Requests one externally budgeted recovery attempt even if the last play
  /// succeeded. This is used only after native state reports an interruption.
  void retryPlaying() {
    if (_terminal || !_desired) return;
    _applied = null;
    _revision++;
    _ensureWorker();
  }

  void _ensureWorker() {
    if (_worker != null) return;
    final worker = _run();
    _worker = worker;
    unawaited(
      worker.whenComplete(() {
        if (!identical(_worker, worker)) return;
        _worker = null;
        if (!_terminal && _processed != _revision) _ensureWorker();
      }),
    );
  }

  Future<void> _run() async {
    while (_processed != _revision && !_terminal) {
      final revision = _revision;
      final desired = _desired;
      if (_applied != desired) {
        try {
          if (desired) {
            await adapter.play();
          } else {
            await adapter.stop();
          }
          _applied = desired;
        } catch (_) {
          // Wait for an explicit later request; never spin on persistent errors.
        }
      }
      _processed = revision;
    }
  }

  Future<void> get idle async {
    while (_worker != null) {
      await _worker!;
    }
  }

  Future<void> shutdown() => _shutdownFuture ??= _doShutdown();
  Future<void> _doShutdown() async {
    _terminal = true;
    _desired = false;
    if (_worker case final worker?) await worker;
    await adapter.stop();
    _applied = false;
  }
}
