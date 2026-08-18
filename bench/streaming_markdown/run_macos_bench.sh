#!/usr/bin/env bash
# Runs the benchmark on macOS under conditions where the numbers mean something.
#
# macOS suspends frame production for occluded windows and coalesces timers for
# background apps. Either one turns this benchmark into a measurement of App Nap
# rather than of rendering, so the run must be frontmost and the machine awake.
# The harness flags runs that were throttled anyway — see RunResult.valid.
set -euo pipefail

cd "$(dirname "$0")"
APP_NAME="streaming_markdown_bench"
OUT="${1:-bench_macos.json}"
LOG="$(mktemp)"

echo "==> keeping display awake for the duration"
caffeinate -disu -w $$ &
CAFFEINATE_PID=$!
trap 'kill "$CAFFEINATE_PID" 2>/dev/null || true' EXIT

echo "==> launching profile build (this rebuilds on first run)"
flutter run --profile -d macos --dart-define=AUTORUN=true >"$LOG" 2>&1 &
FLUTTER_PID=$!

echo "==> holding the window frontmost"
while kill -0 "$FLUTTER_PID" 2>/dev/null; do
  osascript -e "tell application \"$APP_NAME\" to activate" >/dev/null 2>&1 || true
  sleep 3
done

wait "$FLUTTER_PID" || true

sed -n '/===BENCH_JSON_START===/,/===BENCH_JSON_END===/p' "$LOG" \
  | sed '1d;$d' >"$OUT"

echo "==> results written to $OUT"
if grep -q '"valid": false' "$OUT"; then
  echo "!! at least one run was throttled and is NOT a valid measurement:"
  grep -A1 '"valid": false' "$OUT" | grep invalidReason || true
  exit 1
fi
echo "==> all runs valid"
