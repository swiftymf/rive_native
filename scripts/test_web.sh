#!/usr/bin/env bash
# Run the rive_native unit test suite in Chrome against the local debug wasm.
#
# Usage:
#   ./scripts/test_web.sh                     # build debug wasm + run all tests
#   ./scripts/test_web.sh no-build            # skip the wasm build
#   ./scripts/test_web.sh test/hit_test.dart  # run specific files (build first)
#
# Ports can be overridden with WASM_PORT / ASSET_PORT. If a server already
# responds on a port it is reused (and left running); otherwise one is
# started and torn down on exit.
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR/.."

WASM_PORT="${WASM_PORT:-8484}"
ASSET_PORT="${ASSET_PORT:-8283}"

if [[ "$1" == "no-build" ]]; then
  shift
else
  echo "Building debug wasm (flutter-runtime, single-threaded)..."
  (cd native && ./build.sh wasm single-threaded flutter-runtime)
fi

if [[ ! -f native/out/debug/wasm/rive_native.js ]]; then
  echo "native/out/debug/wasm/rive_native.js not found — build the debug" \
    "wasm first: cd native && ./build.sh wasm single-threaded flutter-runtime" >&2
  exit 1
fi

WASM_PID=""
ASSET_PID=""
cleanup() {
  [[ -n "$WASM_PID" ]] && kill "$WASM_PID" 2>/dev/null || true
  [[ -n "$ASSET_PID" ]] && kill "$ASSET_PID" 2>/dev/null || true
}
trap cleanup EXIT

if ! curl -sf "http://localhost:$WASM_PORT/debug/wasm/rive_native.js" -o /dev/null; then
  echo "Starting wasm server on port $WASM_PORT..."
  npx --yes http-server native/out -p "$WASM_PORT" --cors --silent &
  WASM_PID=$!
fi

if ! curl -sf "http://localhost:$ASSET_PORT/test/assets/rating.riv" -o /dev/null; then
  echo "Starting test asset server on port $ASSET_PORT..."
  npx --yes http-server . -p "$ASSET_PORT" --cors --silent &
  ASSET_PID=$!
fi

for url in \
  "http://localhost:$WASM_PORT/debug/wasm/rive_native.js" \
  "http://localhost:$ASSET_PORT/test/assets/rating.riv"; do
  elapsed=0
  until curl -sf "$url" -o /dev/null; do
    if [[ $elapsed -ge 15 ]]; then
      echo "Server for $url failed to start within 15 seconds" >&2
      exit 1
    fi
    sleep 1
    elapsed=$((elapsed + 1))
  done
done

flutter test --platform chrome \
  --dart-define=RIVE_NATIVE_WASM_HOST="http://localhost:$WASM_PORT/debug/" \
  --dart-define=RIVE_TEST_ASSET_HOST="http://localhost:$ASSET_PORT" \
  "$@"
