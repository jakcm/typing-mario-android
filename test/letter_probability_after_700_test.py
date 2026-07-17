#!/usr/bin/env python3
"""
Typing Mario letter probability test after score >= 700.

Purpose
-------
The player reported that after the game reaches ~700 score, letters appear
concentrated on a subset of letters. This script tests the actual game letter
pool algorithm, not UI rendering:

  _pickAvailableLetter(): choose random letter from A-Z minus _usedLetters
  _releaseLetter(): remove letter from _usedLetters

The test simulates game progression, starts collecting samples after score >= 700,
and records 1000 generated letters. It checks:

  1. Overall distribution across A-Z
  2. Distribution after score >= 700 only
  3. Sliding-window concentration (short-term clustering)
  4. Consecutive repeats and same-letter recurrence gap
  5. Whether letters remain locked unexpectedly

Why this matters
----------------
A purely uniform random picker can still create visible clusters in short windows.
For a typing-learning game, perceived fairness often needs a "bag"/shuffle system,
not independent random selection. This script distinguishes:

  - true lock/release bug: letters stuck in _usedLetters
  - random clustering: statistically valid globally, bad UX locally
"""

from __future__ import annotations

import argparse
import math
import random
from collections import Counter, defaultdict, deque
from dataclasses import dataclass
from typing import Iterable

LETTERS = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
EXPECTED_1000 = 1000 / 26
CHI_SQUARE_CRITICAL_DF25_P005 = 37.652  # alpha=0.05


@dataclass
class Target:
    kind: str
    letter: str
    x: float
    speed: float
    consumed: bool = False
    visible_letter: bool = True
    release_at: float | None = None
    remove_at: float | None = None
    parent_alive: bool = True


class CurrentGameLetterLogicSimulator:
    """
    Simulates the current game logic relevant to letter generation.

    Modes:
      - current: current patched code where typed matches release immediately.
      - old_delayed_obstacle_release: previous bug, obstacles release after 0.6s.

    Player model:
      - typed_target_delay controls how fast the player types visible letters.
      - default 0.18s approximates quick correct play without making _usedLetters
        empty every frame.

    Extra mode:
      - detached_leak reproduces the real Flame bug: ignored sprites detach at
        x < -50 and then stop updating, so cleanup's x < -100 release never runs.
    """

    def __init__(
        self,
        seed: int,
        mode: str = "current",
        typed_target_delay: float = 0.18,
        screen_width: float = 400.0,
        playstyle: str = "all_targets",
    ):
        self.rng = random.Random(seed)
        self.mode = mode
        self.typed_target_delay = typed_target_delay
        self.screen_width = screen_width
        self.playstyle = playstyle

        self.time = 0.0
        self.score = 0
        self.game_speed = 120.0
        self.used_letters: set[str] = set()
        self.targets: list[Target] = []
        self.letter_bags: dict[str, list[str]] = {}
        self.recent_by_pool: dict[str, list[str]] = defaultdict(list)
        self.recent_cooldown = 5

        self.obstacle_timer = 1.0
        self.coin_timer = 3.0
        self.platform_timer = 5.0
        self.gap_timer = 8.0
        self.powerup_timer = 12.0

        self.slow_timer = 0.0
        self.next_type_time = 0.0

        self.generated: list[tuple[float, int, str, str, int, tuple[str, ...]]] = []
        self.duplicate_visible_events: list[tuple[float, str, list[str]]] = []
        self.empty_pool_events: list[float] = []

    def available_letters(self) -> list[str]:
        return [c for c in LETTERS if c not in self.used_letters]

    def pick_available_letter(self, kind: str) -> str:
        if self.mode == "bag":
            letter = self.pick_from_bag(kind)
        else:
            available = self.available_letters()
            if not available:
                # Mirrors game fallback. If this happens, it is a serious issue.
                self.empty_pool_events.append(self.time)
                letter = "X"
            else:
                letter = self.rng.choice(available)
                self.used_letters.add(letter)

        self.generated.append(
            (self.time, self.score, letter, kind, len(self.used_letters), tuple(sorted(self.used_letters)))
        )
        return letter

    def pick_from_bag(self, kind: str) -> str:
        bag = self.letter_bags.setdefault(kind, self.new_shuffled_bag())
        recent = self.recent_by_pool[kind]

        index = next(
            (i for i, letter in enumerate(bag)
             if letter not in self.used_letters and letter not in recent),
            -1,
        )
        if index == -1:
            index = next(
                (i for i, letter in enumerate(bag) if letter not in self.used_letters),
                -1,
            )
        if index == -1:
            bag = self.available_letters()
            self.rng.shuffle(bag)
            self.letter_bags[kind] = bag
            if not bag:
                self.empty_pool_events.append(self.time)
                return "X"
            index = next((i for i, letter in enumerate(bag) if letter not in recent), 0)

        letter = bag.pop(index)
        self.used_letters.add(letter)
        recent.append(letter)
        if len(recent) > self.recent_cooldown:
            recent.pop(0)
        return letter

    def new_shuffled_bag(self) -> list[str]:
        bag = list(LETTERS)
        self.rng.shuffle(bag)
        return bag

    def release_letter(self, letter: str):
        self.used_letters.discard(letter)

    def effective_speed(self, base: float) -> float:
        return base * 0.5 if self.slow_timer > 0 else base

    def count_active_unconsumed(self, kind: str) -> int:
        return sum(1 for t in self.targets if t.kind == kind and not t.consumed)

    def spawn(self, kind: str):
        letter = self.pick_available_letter(kind)
        base_speed = {
            "obstacle": self.game_speed,
            "coin": self.game_speed * 0.8,
            "platform": self.game_speed * 0.9,
            "gap": self.game_speed,
            "powerup": self.game_speed * 0.75,
        }[kind]
        self.targets.append(
            Target(
                kind=kind,
                letter=letter,
                x=self.screen_width + 20,
                speed=self.effective_speed(base_speed),
            )
        )
        self.check_visible_duplicates()

    def check_visible_duplicates(self):
        visible = [t.letter for t in self.targets if not t.consumed and t.visible_letter]
        dupes = [letter for letter, count in Counter(visible).items() if count > 1]
        for letter in dupes:
            self.duplicate_visible_events.append((self.time, letter, visible.copy()))

    def consume_target(self, t: Target):
        if t.consumed:
            return
        t.consumed = True
        t.visible_letter = False

        if t.kind == "obstacle":
            self.score += 10
            self.obstacle_timer = 0.5
            t.remove_at = self.time + 0.6
            if self.mode == "old_delayed_obstacle_release":
                t.release_at = self.time + 0.6
            else:
                self.release_letter(t.letter)
        elif t.kind == "coin":
            self.score += 15
            t.remove_at = self.time + 0.35
            self.release_letter(t.letter)
        elif t.kind == "platform":
            self.score += 5
            # Platform remains visible, but its letter is hidden/used.
            # Current patched code releases immediately.
            t.remove_at = None
            self.release_letter(t.letter)
        elif t.kind == "gap":
            self.score += 5
            t.remove_at = None
            self.release_letter(t.letter)
        elif t.kind == "powerup":
            self.score += 20
            # Some powerups can add score; this does not affect letters.
            if self.rng.random() < 0.25:
                self.score += 50
            t.remove_at = self.time + 0.35
            self.release_letter(t.letter)

        self.game_speed = min(self.game_speed + 2, 350)

    def update_targets(self, dt: float):
        for t in list(self.targets):
            # Reproduce the real Flame bug: ignored sprites detach themselves at
            # x < -50 and then stop updating. Buggy cleanup only checks x < -100,
            # so these letters leak forever.
            if self.mode == "detached_leak" and not t.parent_alive:
                continue

            if t.release_at is not None and self.time >= t.release_at:
                self.release_letter(t.letter)
                t.release_at = None

            if not t.consumed or t.kind in {"platform", "gap"}:
                t.x -= t.speed * dt

            if self.mode == "detached_leak" and not t.consumed and t.x + 52 < -50:
                t.parent_alive = False
                # No release here: this is the bug being reproduced.
                continue

            # Fixed behavior: detached/off-screen unconsumed target releases letter.
            if not t.consumed and t.x + 52 < -100:
                t.consumed = True
                t.visible_letter = False
                self.release_letter(t.letter)
                t.remove_at = self.time

            if t.remove_at is not None and self.time >= t.remove_at:
                self.targets.remove(t)
            elif t.kind in {"platform", "gap"} and t.x + 160 < -100:
                # Platform/gap can remain consumed but visible until off screen.
                if not t.consumed:
                    self.release_letter(t.letter)
                self.targets.remove(t)

    def player_step(self):
        if self.time < self.next_type_time:
            return

        if self.playstyle == "obstacles_only":
            # User-reported playstyle: only type monster letters; ignore coins,
            # platforms, gaps and powerups. Those ignored targets keep their
            # letters locked until they scroll off screen / miss cleanup.
            candidates = [
                t for t in self.targets
                if t.kind == "obstacle" and not t.consumed and t.visible_letter
            ]
        else:
            # Priority mirrors onLetterTyped matching priority: obstacle > powerup > other.
            priority = {"obstacle": 0, "powerup": 1, "coin": 2, "platform": 3, "gap": 4}
            candidates = [t for t in self.targets if not t.consumed and t.visible_letter]
            candidates.sort(key=lambda t: (priority[t.kind], t.x))

        if not candidates:
            return
        self.consume_target(candidates[0])
        self.next_type_time = self.time + self.typed_target_delay

    def update_spawns(self, dt: float):
        self.obstacle_timer -= dt
        if self.obstacle_timer <= 0 and self.count_active_unconsumed("obstacle") == 0:
            self.spawn("obstacle")
            self.obstacle_timer = 2.0

        self.coin_timer -= dt
        if self.coin_timer <= 0:
            self.spawn("coin")
            self.coin_timer = 6.0 + self.rng.random() * 3

        self.platform_timer -= dt
        if self.platform_timer <= 0:
            self.spawn("platform")
            self.platform_timer = 10.0 + self.rng.random() * 4

        self.gap_timer -= dt
        if self.gap_timer <= 0:
            self.spawn("gap")
            self.gap_timer = 14.0 + self.rng.random() * 5

        self.powerup_timer -= dt
        if self.powerup_timer <= 0:
            if self.count_active_unconsumed("powerup") < 1:
                self.spawn("powerup")
            self.powerup_timer = 18.0 + self.rng.random() * 10

    def step(self, dt: float):
        self.time += dt
        if self.slow_timer > 0:
            self.slow_timer = max(0.0, self.slow_timer - dt)
        self.update_targets(dt)
        self.update_spawns(dt)
        self.player_step()

    def run_until_samples_after_score(
        self,
        start_score: int,
        samples: int,
        sample_kind: str = "obstacle",
        max_seconds: float = 4000,
    ):
        dt = 1 / 60
        collecting = False
        records = []
        while self.time < max_seconds:
            before = len(self.generated)
            self.step(dt)

            if not collecting and self.score >= start_score:
                collecting = True

            if collecting and len(self.generated) > before:
                new_records = self.generated[before:]
                for record in new_records:
                    _time, _score, _letter, kind, _locked, _used = record
                    if sample_kind == "all" or kind == sample_kind:
                        records.append(record)
                        if len(records) >= samples:
                            return records

        raise RuntimeError(
            f"only collected {len(records)}/{samples} {sample_kind} samples after "
            f"score>={start_score}; final score={self.score}, time={self.time:.1f}s"
        )


def chi_square(counts: Counter, n: int) -> float:
    expected = n / 26
    return sum((counts.get(c, 0) - expected) ** 2 / expected for c in LETTERS)


def max_window_concentration(letters: list[str], window: int) -> tuple[int, str, int, dict[str, int]]:
    if len(letters) < window:
        window = len(letters)
    best_start = 0
    best_letter = ""
    best_count = -1
    best_counts: Counter[str] = Counter()
    q: deque[str] = deque()
    counts: Counter[str] = Counter()
    for i, letter in enumerate(letters):
        q.append(letter)
        counts[letter] += 1
        if len(q) > window:
            old = q.popleft()
            counts[old] -= 1
            if counts[old] == 0:
                del counts[old]
        if len(q) == window:
            letter_i, count_i = counts.most_common(1)[0]
            if count_i > best_count:
                best_count = count_i
                best_letter = letter_i
                best_start = i - window + 1
                best_counts = Counter(counts)
    return best_start, best_letter, best_count, dict(best_counts)


def recurrence_stats(letters: list[str]) -> dict[str, float | int]:
    repeats_adjacent = sum(1 for a, b in zip(letters, letters[1:]) if a == b)
    last_seen: dict[str, int] = {}
    gaps: list[int] = []
    short_gap_count = 0
    for i, letter in enumerate(letters):
        if letter in last_seen:
            gap = i - last_seen[letter]
            gaps.append(gap)
            if gap <= 3:
                short_gap_count += 1
        last_seen[letter] = i
    return {
        "adjacent_repeats": repeats_adjacent,
        "min_recurrence_gap": min(gaps) if gaps else -1,
        "avg_recurrence_gap": sum(gaps) / len(gaps) if gaps else -1,
        "short_gap_<=3": short_gap_count,
    }


def print_distribution(title: str, records: list[tuple[float, int, str, str, int, tuple[str, ...]]]):
    letters = [r[2] for r in records]
    n = len(letters)
    counts = Counter(letters)
    chi = chi_square(counts, n)
    expected = n / 26
    print("\n" + "=" * 78)
    print(title)
    print("=" * 78)
    print(f"samples={n}, expected_each={expected:.2f}, chi_square={chi:.2f}, critical_0.05={CHI_SQUARE_CRITICAL_DF25_P005:.2f}")
    print(f"global_uniform={'PASS' if chi <= CHI_SQUARE_CRITICAL_DF25_P005 else 'FAIL'}")
    print("\nLetter  Count   Pct    Dev    Bar")
    max_count = max(counts.values()) if counts else 1
    for c in LETTERS:
        count = counts.get(c, 0)
        pct = count / n * 100
        dev = count - expected
        bar = "█" * round(count / max_count * 36)
        print(f"  {c}    {count:5d}  {pct:5.1f}%  {dev:+6.1f}  {bar}")

    for window in (25, 50, 100):
        start, letter, count, wc = max_window_concentration(letters, window)
        expected_w = window / 26
        print(
            f"\nwindow={window}: most concentrated window starts at sample {start}, "
            f"letter {letter} appears {count}/{window} ({count / window * 100:.1f}%), "
            f"expected≈{expected_w:.1f}"
        )
        top = Counter(wc).most_common(8)
        print("  top letters:", ", ".join(f"{k}:{v}" for k, v in top))

    rec = recurrence_stats(letters)
    print("\nRecurrence:")
    for k, v in rec.items():
        print(f"  {k}: {v}")

    kind_counts = Counter(r[3] for r in records)
    print("\nGenerated target kinds:", dict(kind_counts))
    max_locked = max(r[4] for r in records) if records else 0
    avg_locked = sum(r[4] for r in records) / n if records else 0
    print(f"Locked letters during generation: avg={avg_locked:.2f}, max={max_locked}")

    return chi


def run(
    seed: int,
    mode: str,
    start_score: int,
    samples: int,
    delay: float,
    playstyle: str,
    sample_kind: str,
):
    sim = CurrentGameLetterLogicSimulator(
        seed=seed,
        mode=mode,
        typed_target_delay=delay,
        playstyle=playstyle,
    )
    records = sim.run_until_samples_after_score(
        start_score=start_score,
        samples=samples,
        sample_kind=sample_kind,
    )
    title = (
        f"mode={mode}, playstyle={playstyle}, sample_kind={sample_kind}, seed={seed}, "
        f"start_score>={start_score}, typed_delay={delay}s, "
        f"final_score={sim.score}, final_time={sim.time:.1f}s"
    )
    chi = print_distribution(title, records)
    print(f"\nEmpty pool events: {len(sim.empty_pool_events)}")
    print(f"Visible duplicate-letter events: {len(sim.duplicate_visible_events)}")
    if sim.duplicate_visible_events[:5]:
        for event in sim.duplicate_visible_events[:5]:
            t, letter, visible = event
            print(f"  duplicate at t={t:.2f}s letter={letter} visible={visible}")
    return chi, sim, records


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--samples", type=int, default=1000)
    parser.add_argument("--start-score", type=int, default=700)
    parser.add_argument("--seeds", type=int, default=10)
    parser.add_argument("--mode", choices=["current", "bag", "detached_leak", "old_delayed_obstacle_release", "both"], default="bag")
    parser.add_argument(
        "--playstyle",
        choices=["all_targets", "obstacles_only"],
        default="obstacles_only",
        help="obstacles_only matches the user's reported gameplay: only type monster letters",
    )
    parser.add_argument(
        "--sample-kind",
        choices=["obstacle", "all", "coin", "platform", "gap", "powerup"],
        default="obstacle",
        help="which generated target letters to count after start-score",
    )
    parser.add_argument("--typed-delay", type=float, default=0.18)
    args = parser.parse_args()

    modes = ["current", "bag"] if args.mode == "both" else [args.mode]
    summary = []
    for mode in modes:
        fails = 0
        duplicate_runs = 0
        print("\n\n" + "#" * 78)
        print(f"RUNNING MODE: {mode}")
        print("#" * 78)
        for seed in range(args.seeds):
            chi, sim, _records = run(
                seed,
                mode,
                args.start_score,
                args.samples,
                args.typed_delay,
                args.playstyle,
                args.sample_kind,
            )
            fail = chi > CHI_SQUARE_CRITICAL_DF25_P005
            fails += int(fail)
            duplicate_runs += int(bool(sim.duplicate_visible_events))
            summary.append((mode, seed, chi, fail, len(sim.duplicate_visible_events), len(sim.empty_pool_events)))

        print("\n" + "-" * 78)
        print(f"MODE SUMMARY: {mode}")
        print(f"  chi-square failures: {fails}/{args.seeds}")
        print(f"  runs with visible duplicate events: {duplicate_runs}/{args.seeds}")

    print("\n\n" + "=" * 78)
    print("FINAL SUMMARY")
    print("=" * 78)
    print("mode,seed,chi_square,uniform_fail,visible_duplicate_events,empty_pool_events")
    for row in summary:
        print(f"{row[0]},{row[1]},{row[2]:.2f},{row[3]},{row[4]},{row[5]}")

    print("\nInterpretation:")
    print("  - If global chi-square usually passes but sliding windows show high concentration,")
    print("    the issue is UX clustering from independent random selection.")
    print("  - If visible duplicate events occur in current mode, release timing allows the same")
    print("    letter to be reassigned while still visible elsewhere.")
    print("  - If empty pool events occur, _usedLetters is leaking/locking letters.")


if __name__ == "__main__":
    main()
