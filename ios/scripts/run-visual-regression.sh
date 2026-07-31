#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_PATH="$ROOT_DIR/FiliusPad.xcodeproj"
SCHEME="${IOS_SCHEME:-FiliusPad}"
DESTINATION="${IOS_SIM_DESTINATION:-platform=iOS Simulator,name=iPad (A16)}"
RESULT_BUNDLE_PATH="${VISUAL_RESULT_BUNDLE_PATH:-$ROOT_DIR/build/visual-regression.xcresult}"
UPDATE_BASELINES=0

usage() {
  cat <<'USAGE'
Usage: ios/scripts/run-visual-regression.sh [--record]

Runs the canonical FiliusPad visual UI-test suite on the iPad (10th generation)
simulator. --record intentionally replaces reviewed Swift-to-Swift baselines in
FiliusPadUITests/ParityBaselines. Normal runs never modify baselines.
USAGE
}

case "${1:-}" in
  "") ;;
  --record) UPDATE_BASELINES=1 ;;
  -h|--help) usage; exit 0 ;;
  *) usage >&2; exit 64 ;;
esac

mkdir -p "$(dirname "$RESULT_BUNDLE_PATH")"
rm -rf "$RESULT_BUNDLE_PATH"

RECORDING_SENTINEL="$ROOT_DIR/FiliusPadUITests/ParityBaselines/.recording"
cleanup_recording_sentinel() {
  rm -f "$RECORDING_SENTINEL"
}
trap cleanup_recording_sentinel EXIT
if [[ "$UPDATE_BASELINES" == "1" ]]; then
  touch "$RECORDING_SENTINEL"
fi

xcodebuild \
  -project "$PROJECT_PATH" \
  -scheme "$SCHEME" \
  -destination "$DESTINATION" \
  -resultBundlePath "$RESULT_BUNDLE_PATH" \
  -parallel-testing-enabled NO \
  -maximum-parallel-testing-workers 1 \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  -only-testing:FiliusPadUITests/TopologyVisualRegressionUITests \
  test

if [[ "$UPDATE_BASELINES" == "1" ]]; then
  count="$(find "$ROOT_DIR/FiliusPadUITests/ParityBaselines" -maxdepth 1 -name '*.png' -type f | wc -l | tr -d ' ')"
  if [[ "$count" -lt 6 ]]; then
    echo "Expected at least six recorded baselines, found $count" >&2
    exit 8
  fi
  echo "Recorded $count visual baselines. Review every changed PNG before committing."
else
  echo "Visual regression suite passed against reviewed baselines."
fi
