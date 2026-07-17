#!/usr/bin/env python3
"""
Typing Mario — Letter Distribution Simulator
=============================================
Simulates the game's letter-pool logic to verify whether all 26 letters
appear with roughly equal probability over 1000+ spawns.

Reproduces the exact logic from typing_mario_game.dart:
  - _usedLetters set tracks locked letters
  - _pickAvailableLetter(): random from unlocked, then lock
  - _releaseLetter(): unlock
  - Obstacles: letter locked for 0.6s death animation before release (THE BUG)
  - Coins/Platforms/Gaps/PowerUps: letter released immediately when consumed
  - Spawn timers: obstacles 2s, coins 6s, platforms 10s, gaps 14s, powerups 18s
  - gameSpeed increases from 120 → 350 as score rises

Bug: _onTargetMatched() does NOT call _releaseLetter() immediately.
     For obstacles, the letter stays locked until the 0.6s death animation
     finishes AND _cleanupTargets runs again. At high scores, obstacles
     spawn fast → more letters locked simultaneously → pool shrinks →
     distribution skews toward whatever letters happen to be free.
"""

import random
from collections import Counter

ALL_LETTERS = list("ABCDEFGHIJKLMNOPQRSTUVWXYZ")


class Target:
    """Represents a spawned letter-bearing game object."""
    def __init__(self, letter: str, kind: str, spawn_tick: int, speed: float):
        self.letter = letter
        self.kind = kind  # 'obstacle' | 'coin' | 'platform' | 'gap' | 'powerup'
        self.consumed = False
        self.parent_alive = True  # still in component tree
        self.destroy_anim_timer = 0.0  # obstacle death animation (0.6s)
        self.speed = speed
        self.spawn_tick = spawn_tick
        self.consumed_tick = -1  # when player typed the letter
        self.x = 9999.0  # off-screen right, scrolls left over time

    def update(self, dt: float):
        """Scroll left; if obstacle destroyed, tick death animation."""
        if self.consumed and self.kind == "obstacle":
            self.destroy_anim_timer += dt
            if self.destroy_anim_timer >= 0.6:
                self.parent_alive = False
        else:
            self.x -= self.speed * dt

    def scrolled_off(self) -> bool:
        """Target scrolled past left edge → should be cleaned up."""
        return self.x + 52 < -100


class LetterPoolSimulator:
    """
    Faithful reproduction of typing_mario_game.dart letter logic.
    Simulates ticks at 60 FPS (dt=1/60).

    bug_fixed=False → original buggy behavior (no immediate release on match)
    bug_fixed=True  → fixed behavior (_releaseLetter called in _onTargetMatched)
    """

    def __init__(self, seed: int = 42, bug_fixed: bool = False):
        self.rng = random.Random(seed)
        self.used_letters: set[str] = set()
        self.active_targets: list[Target] = []
        self.score = 0
        self.game_speed = 120.0
        self.bug_fixed = bug_fixed

        # Spawn timers (matching game constants)
        self.obstacle_timer = 1.0
        self.coin_timer = 3.0
        self.platform_timer = 5.0
        self.gap_timer = 8.0
        self.powerup_timer = 12.0

        # Stats
        self.pick_history: list[str] = []
        self.tick = 0

    # ── Letter pool (exact copy of game logic) ──────────────────────────

    def _pick_available_letter(self) -> str:
        available = [l for l in ALL_LETTERS if l not in self.used_letters]
        if not available:
            return "X"  # fallback (should never happen in normal play)
        letter = self.rng.choice(available)
        self.used_letters.add(letter)
        return letter

    def _release_letter(self, letter: str):
        self.used_letters.discard(letter)

    def _effective_speed(self, base: float) -> float:
        return base  # skip slow effect for simplicity

    # ── Spawning ────────────────────────────────────────────────────────

    def _spawn_obstacle(self):
        letter = self._pick_available_letter()
        speed = self._effective_speed(self.game_speed)
        t = Target(letter, "obstacle", self.tick, speed)
        t.x = 400 + 20  # screenWidth + 20
        self.active_targets.append(t)

    def _spawn_coin(self):
        letter = self._pick_available_letter()
        speed = self._effective_speed(self.game_speed * 0.8)
        t = Target(letter, "coin", self.tick, speed)
        t.x = 400 + 20
        self.active_targets.append(t)

    def _spawn_platform(self):
        letter = self._pick_available_letter()
        speed = self._effective_speed(self.game_speed * 0.9)
        t = Target(letter, "platform", self.tick, speed)
        t.x = 400 + 20
        self.active_targets.append(t)

    def _spawn_gap(self):
        letter = self._pick_available_letter()
        speed = self._effective_speed(self.game_speed)
        t = Target(letter, "gap", self.tick, speed)
        t.x = 400 + 20
        self.active_targets.append(t)

    def _spawn_powerup(self):
        letter = self._pick_available_letter()
        speed = self._effective_speed(self.game_speed * 0.75)
        t = Target(letter, "powerup", self.tick, speed)
        t.x = 400 + 20
        self.active_targets.append(t)

    # ── Player typing (simulated: always types correct letter) ──────────

    def _player_types(self, target: Target):
        """Simulate player typing the correct letter for a target."""
        target.consumed = True
        target.consumed_tick = self.tick

        # Scoring (matching game)
        score_map = {
            "obstacle": 10,
            "coin": 15,
            "platform": 5,
            "gap": 5,
            "powerup": 20,
        }
        self.score += score_map.get(target.kind, 0)

        # ─── THE BUG / FIX ─────────────────────────────────────────────
        # Bug:    _onTargetMatched does NOT call _releaseLetter.
        #         Obstacles lock letters for 0.6s until cleanup releases them.
        # Fix:    _onTargetMatched calls _releaseLetter immediately.
        if self.bug_fixed:
            self._release_letter(target.letter)

        # Increase game speed (matching game)
        self.game_speed = min(self.game_speed + 2, 350)

        # If obstacle, start death animation timer
        if target.kind == "obstacle":
            target.destroy_anim_timer = 0.0
            # Game also sets _obstacleTimer = 0.5 to spawn next quickly
            self.obstacle_timer = 0.5
        elif target.kind == "powerup":
            self.score += 50  # coinRain bonus etc.

    # ── Cleanup (exact copy of _cleanupTargets logic) ───────────────────

    def _cleanup_targets(self):
        to_remove = []

        for target in self.active_targets:
            if target.consumed:
                # Letter was already released by the handler (typing or collision).
                if self.bug_fixed:
                    # Fixed: no re-release, just remove from active list
                    # once animation is done (for obstacles) or immediately (others)
                    if not target.parent_alive or target.kind != "obstacle":
                        to_remove.append(target)
                else:
                    # Buggy: original _cleanupTargets logic
                    if not target.parent_alive:
                        to_remove.append(target)
                        self._release_letter(target.letter)
                    elif target.kind == "obstacle" and target.consumed:
                        if not target.parent_alive:
                            to_remove.append(target)
                            self._release_letter(target.letter)
                        # ELSE: letter stays locked (BUG)
                    else:
                        to_remove.append(target)
                        self._release_letter(target.letter)
                continue

            # Scrolled off screen — unconsumed, release letter
            if target.scrolled_off():
                to_remove.append(target)
                self._release_letter(target.letter)

        for t in to_remove:
            self.active_targets.remove(t)

    # ── Main loop ───────────────────────────────────────────────────────

    def step(self, dt: float):
        """Simulate one game update tick."""

        # Update all targets (scroll, death animation)
        for t in self.active_targets:
            t.update(dt)

        # ── Spawn timers ─────────────────────────────────────────────────
        self.obstacle_timer -= dt
        # Obstacles: only spawn if none active (matching _countType == 0)
        has_obstacle = any(
            t.kind == "obstacle" and not t.consumed for t in self.active_targets
        )
        if self.obstacle_timer <= 0 and not has_obstacle:
            self._spawn_obstacle()
            self.obstacle_timer = 2.0

        self.coin_timer -= dt
        if self.coin_timer <= 0:
            self._spawn_coin()
            self.coin_timer = 6.0 + self.rng.random() * 3

        self.platform_timer -= dt
        if self.platform_timer <= 0:
            self._spawn_platform()
            self.platform_timer = 10.0 + self.rng.random() * 4

        self.gap_timer -= dt
        if self.gap_timer <= 0:
            self._spawn_gap()
            self.gap_timer = 14.0 + self.rng.random() * 5

        self.powerup_timer -= dt
        if self.powerup_timer <= 0:
            # Max 1 powerup on screen
            has_powerup = any(
                t.kind == "powerup" and not t.consumed
                for t in self.active_targets
            )
            if not has_powerup:
                self._spawn_powerup()
            self.powerup_timer = 18.0 + self.rng.random() * 10

        # ── Simulate player typing: type correct letter for newest target ─
        # Player types the letter of any unconsumed target (perfect play)
        for t in self.active_targets:
            if not t.consumed:
                self._player_types(t)
                break  # type one per tick

        # ── Cleanup ──────────────────────────────────────────────────────
        self._cleanup_targets()

        self.tick += 1

    def run(self, num_picks: int = 1000):
        """Run simulation until we've picked num_picks letters."""
        dt = 1 / 60  # 60 FPS
        max_ticks = num_picks * 500  # safety limit

        while len(self.pick_history) < num_picks and self.tick < max_ticks:
            picks_before = len(
                [
                    t
                    for t in self.active_targets
                    if not t.consumed and t.letter != "X"
                ]
            )
            self.step(dt)

        return self.pick_history


def run_simulation(num_picks: int = 1000, seed: int = 42, bug_fixed: bool = False) -> tuple[Counter, LetterPoolSimulator]:
    """
    Run the simulation and return letter frequency.
    """
    sim = LetterPoolSimulator(seed=seed, bug_fixed=bug_fixed)

    # Monkey-patch _pick_available_letter to record picks
    original_pick = sim._pick_available_letter
    pick_log: list[str] = []

    def logging_pick():
        letter = original_pick()
        pick_log.append(letter)
        return letter

    sim._pick_available_letter = logging_pick

    # Run until we have enough picks
    dt = 1 / 60
    max_ticks = 500000

    while len(pick_log) < num_picks and sim.tick < max_ticks:
        sim.step(dt)

    return Counter(pick_log), sim


def analyze_distribution(counter: Counter, total: int, sim: LetterPoolSimulator):
    """Print analysis of letter distribution."""
    print(f"\n{'='*60}")
    print(f"LETTER DISTRIBUTION ANALYSIS — {total} picks")
    print(f"{'='*60}")
    print(f"Final score: {sim.score}  |  gameSpeed: {sim.game_speed:.0f}")
    print(f"Ticks simulated: {sim.tick}  (~{sim.tick/60:.1f}s game time)")
    print(f"Active targets at end: {len(sim.active_targets)}")
    print(f"Locked letters at end: {sorted(sim.used_letters)}")
    print()

    # Expected average
    expected = total / 26

    print(f"Expected avg per letter: {expected:.1f}")
    print(f"{'Letter':<8} {'Count':>7} {'Pct':>7} {'Deviation':>10} {'Bar'}")
    print(f"{'-'*50}")

    max_count = max(counter.values()) if counter else 1
    deviations = []

    for letter in ALL_LETTERS:
        count = counter.get(letter, 0)
        pct = count / total * 100
        dev = count - expected
        deviations.append((letter, count, dev))
        bar_len = int(count / max_count * 40) if max_count > 0 else 0
        bar = "█" * bar_len
        sign = "+" if dev >= 0 else ""
        print(f"  {letter:<6} {count:>7} {pct:>6.1f}% {sign}{dev:>8.1f}  {bar}")

    # Statistics
    counts = [counter.get(l, 0) for l in ALL_LETTERS]
    avg = sum(counts) / 26
    variance = sum((c - avg) ** 2 for c in counts) / 26
    std_dev = variance ** 0.5

    # Chi-square test (goodness of fit)
    chi_sq = sum((c - expected) ** 2 / expected for c in counts)

    print(f"\n{'─'*50}")
    print(f"STATISTICS")
    print(f"{'─'*50}")
    print(f"  Mean:     {avg:.1f}")
    print(f"  Std Dev:  {std_dev:.1f}")
    print(f"  Min:      {min(counts)} ({ALL_LETTERS[counts.index(min(counts))]})")
    print(f"  Max:      {max(counts)} ({ALL_LETTERS[counts.index(max(counts))]})")
    print(f"  Range:    {max(counts) - min(counts)}")
    print(f"  Chi-Sq:   {chi_sq:.1f}  (df=25, critical@0.05=37.7)")
    if chi_sq > 37.7:
        print(f"  ⚠️  DISTRIBUTION IS NOT UNIFORM (chi-sq > 37.7)")
    else:
        print(f"  ✓  Distribution appears uniform (chi-sq ≤ 37.7)")

    # Show worst offenders
    deviations.sort(key=lambda x: abs(x[2]), reverse=True)
    print(f"\n{'─'*50}")
    print(f"WORST DEVIATIONS (|dev| > 20% of expected)")
    print(f"{'─'*50}")
    for letter, count, dev in deviations[:10]:
        pct_dev = abs(dev) / expected * 100
        if pct_dev > 20:
            flag = "⚠️ "
        else:
            flag = "  "
        print(f"  {flag}{letter}: {count} picks (dev={dev:+.1f}, {pct_dev:.0f}% off)")

    # Check for letter starvation
    starved = [(l, c) for l, c in zip(ALL_LETTERS, counts) if c < expected * 0.5]
    if starved:
        print(f"\n{'─'*50}")
        print(f"🚨 LETTER STARVATION (count < 50% of expected)")
        print(f"{'─'*50}")
        for letter, count in starved:
            print(f"  {letter}: {count} picks (expected ~{expected:.0f})")

    return chi_sq > 37.7


if __name__ == "__main__":
    NUM_RUNS = 5
    NUM_PICKS = 1000

    for label, bug_fixed in [("BUG (original)", False), ("FIX (patched)", True)]:
        print(f"\n{'='*60}")
        print(f"  {label}  —  {NUM_PICKS} picks × {NUM_RUNS} runs")
        print(f"{'='*60}")

        all_results = []
        for seed in range(NUM_RUNS):
            counter, sim = run_simulation(num_picks=NUM_PICKS, seed=seed, bug_fixed=bug_fixed)
            print(f"\n{'#'*60}")
            print(f"# RUN {seed + 1}/{NUM_RUNS} (seed={seed})")
            print(f"{'#'*60}")
            is_bad = analyze_distribution(counter, NUM_PICKS, sim)
            all_results.append((seed, is_bad, sim.score))

        print(f"\n\n{'='*60}")
        print(f"SUMMARY — {label}")
        print(f"{'='*60}")
        for seed, is_bad, score in all_results:
            status = "⚠️  BIASED" if is_bad else "✓  OK"
            print(f"  Run {seed + 1}: score={score:>5}  {status}")

        biased_count = sum(1 for _, bad, _ in all_results if bad)
        if biased_count > 0:
            print(f"\n🚨 {biased_count}/{NUM_RUNS} runs showed non-uniform distribution!")
        else:
            print(f"\n✅ All {NUM_RUNS} runs showed uniform distribution.")

    print(f"\n\n{'='*60}")
    print(f"COMPARISON")
    print(f"{'='*60}")
    print(f"  Bug:   some letters locked 0.6s after obstacle destroyed by typing")
    print(f"  Fix:   _releaseLetter() called immediately in _onTargetMatched()")
    print(f"  Result: fixed version should show uniform distribution")
