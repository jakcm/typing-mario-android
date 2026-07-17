#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
REPORT_DIR="${1:-$ROOT/reports/stress/$STAMP}"

if [[ -e "$REPORT_DIR" ]]; then
  rm -rf "$REPORT_DIR"
fi
mkdir -p "$REPORT_DIR"
REPORT_DIR="$(cd "$REPORT_DIR" && pwd)"
cd "$ROOT"

FLUTTER_BIN="$(command -v flutter || true)"
if [[ -z "$FLUTTER_BIN" ]]; then
  echo "[stress] INFRA_FAILURE: flutter not found" >&2
  exit 10
fi
GIT_SHA="$(git rev-parse --short HEAD 2>/dev/null || printf unknown)"
if [[ -n "$(git status --porcelain 2>/dev/null || true)" ]]; then GIT_DIRTY=true; else GIT_DIRTY=false; fi
FLUTTER_VERSION="$($FLUTTER_BIN --version 2>/dev/null | sed -n '1p')"
COMMAND="flutter test tool/stress_700.dart -- $REPORT_DIR"

printf '[stress] formal TypingMarioGame host stress; no Android device required\n'
printf '[stress] report=%s\n' "$REPORT_DIR"

# Compile and execute focused regression tests first.
if ! "$FLUTTER_BIN" test test/stress_harness_test.dart --reporter expanded >"$REPORT_DIR/test_build.log" 2>&1; then
  cp "$REPORT_DIR/test_build.log" "$REPORT_DIR/run.log"
  echo "[stress] TEST_BUILD_FAILURE: see $REPORT_DIR/run.log" >&2
  exit 20
fi

# Run the formal game harness in a Flutter test process. A standalone `dart run`
# cannot initialize Flutter services and may use a different Dart SDK.
set +e
STRESS_REPORT_DIR="$REPORT_DIR" \
STRESS_GIT_SHA="$GIT_SHA" \
STRESS_GIT_DIRTY="$GIT_DIRTY" \
STRESS_FLUTTER_VERSION="$FLUTTER_VERSION" \
STRESS_COMMAND="$COMMAND" \
  "$FLUTTER_BIN" test tool/stress_700.dart --reporter expanded \
  >"$REPORT_DIR/runner.log" 2>&1
STATUS=$?
set -e

if [[ $STATUS -ne 0 ]]; then
  if [[ -s "$REPORT_DIR/diagnostic.md" ]]; then
    echo "[stress] THRESHOLD_FAILURE: see $REPORT_DIR/diagnostic.md" >&2
    exit 30
  fi
  cp "$REPORT_DIR/runner.log" "$REPORT_DIR/run.log"
  echo "[stress] RUNTIME_FAILURE: see $REPORT_DIR/run.log" >&2
  exit 40
fi

for artifact in metrics.csv diagnostic.md memory_curve.svg run.log; do
  if [[ ! -s "$REPORT_DIR/$artifact" ]]; then
    echo "[stress] ARTIFACT_FAILURE: missing $artifact" >&2
    exit 50
  fi
done
cat "$REPORT_DIR/runner.log"
echo "[stress] PASS: $REPORT_DIR"
