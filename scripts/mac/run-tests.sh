#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_NAME="$(basename "$0")"
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
ARTIFACTS_ROOT="~/FiliusTestArtifacts"
PROFILE="full"
BRANCH="main"
REVISION=""
SIMULATOR_UDID=""
SYNC_REPOSITORY=false
KEEP_SIMULATOR_RUNNING=false
INSTALL_RUNTIME=false
UI_TIMEOUT_MINUTES=120

ARTIFACTS_DIR=""
TEMP_ROOT=""
SELECTED_UDID=""
SELECTED_NAME=""
SELECTED_RUNTIME=""

log() {
  printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*"
}

fail() {
  log "ERROR: $*" >&2
  exit 1
}

usage() {
  cat <<EOF
Usage: $SCRIPT_NAME [options]

Run FiliusPad XCTest and XCUITest suites on a local iPad simulator.

Options:
  --repo PATH                 Repository checkout (default: checkout containing this script)
  --profile PROFILE           smoke, unit, ui, runtime-ui, desktop-ui,
                              service-ui, simulation-ui, or full (default: full)
  --sync                      Fetch and synchronize the Mac checkout before testing
  --branch NAME               Branch used by --sync when --revision is omitted
  --revision COMMIT           Exact commit used by --sync (detached checkout)
  --simulator-udid UDID       Use a specific available iPad simulator
  --artifacts-root PATH       Artifact parent directory
  --install-runtime           Download an iOS simulator runtime when none is available
  --keep-simulator-running    Do not shut down the selected simulator afterward
  --ui-timeout-minutes N      Maximum UI-test duration (default: 120)
  -h, --help                  Show this help

Examples:
  $SCRIPT_NAME --profile smoke
  $SCRIPT_NAME --profile full --sync --branch main
  $SCRIPT_NAME --profile unit --simulator-udid ABCD-1234
EOF
}

expand_path() {
  local value="$1"
  if [[ "$value" == "~" ]]; then
    printf '%s\n' "$HOME"
  elif [[ "$value" == "~/"* ]]; then
    printf '%s/%s\n' "$HOME" "${value:2}"
  elif [[ "$value" == /* ]]; then
    printf '%s\n' "$value"
  else
    printf '%s/%s\n' "$PWD" "$value"
  fi
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || fail "required command is unavailable: $1"
}

is_ui_profile() {
  case "$PROFILE" in
    smoke|ui|runtime-ui|desktop-ui|service-ui|simulation-ui|full) return 0 ;;
    *) return 1 ;;
  esac
}

synchronize_repository() {
  [[ -e "$REPO_ROOT/.git" ]] || fail "not a Git checkout: $REPO_ROOT"

  if [[ -n "$(git -C "$REPO_ROOT" status --porcelain)" ]]; then
    fail "Mac checkout is dirty; commit, stash, or use a separate checkout before --sync"
  fi

  log "Fetching origin"
  git -C "$REPO_ROOT" fetch --prune origin

  if [[ -n "$REVISION" ]]; then
    if ! git -C "$REPO_ROOT" cat-file -e "${REVISION}^{commit}" 2>/dev/null; then
      git -C "$REPO_ROOT" fetch origin "$REVISION"
    fi
    log "Checking out exact revision $REVISION"
    git -C "$REPO_ROOT" checkout --detach "$REVISION"
    return
  fi

  if git -C "$REPO_ROOT" show-ref --verify --quiet "refs/heads/$BRANCH"; then
    git -C "$REPO_ROOT" checkout "$BRANCH"
    git -C "$REPO_ROOT" merge --ff-only "origin/$BRANCH"
  else
    git -C "$REPO_ROOT" checkout --track -b "$BRANCH" "origin/$BRANCH"
  fi
}

prepare_artifacts() {
  local timestamp commit
  timestamp="$(date '+%Y-%m-%d-%H%M%S')"
  commit="$(git -C "$REPO_ROOT" rev-parse --short HEAD)"
  ARTIFACTS_DIR="$ARTIFACTS_ROOT/${timestamp}-${commit}-${PROFILE}"
  mkdir -p "$ARTIFACTS_DIR/logs" "$ARTIFACTS_DIR/results" "$ARTIFACTS_DIR/diagnostics"
  TEMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/filius-tests.XXXXXX")"
  trap 'rm -rf "$TEMP_ROOT"' EXIT

  git -C "$REPO_ROOT" status --short --branch > "$ARTIFACTS_DIR/logs/git-status.log"
  git -C "$REPO_ROOT" rev-parse HEAD > "$ARTIFACTS_DIR/logs/git-commit.log"
}

record_toolchain() {
  {
    echo '## macOS'
    sw_vers
    echo
    echo '## Xcode'
    xcodebuild -version
    echo
    echo '## Developer directory'
    xcode-select -p
    echo
    echo '## Host'
    uname -a
  } | tee "$ARTIFACTS_DIR/logs/toolchain.log"

  # Compact Xcode installations gate non-macOS destinations with this preference.
  defaults write com.apple.dt.Xcode IDEPlatformsFirstLaunchSelected-iphoneos -bool true

  xcodebuild \
    -project "$REPO_ROOT/ios/FiliusPad.xcodeproj" \
    -scheme FiliusPad \
    -showdestinations 2>&1 | tee "$ARTIFACTS_DIR/logs/xcode-destinations.log"
}

ensure_simulator_runtime() {
  xcrun simctl list devices available -j > "$ARTIFACTS_DIR/logs/simulators.json"

  if python3 "$REPO_ROOT/scripts/ci/select_ios_simulator.py" \
      --input "$ARTIFACTS_DIR/logs/simulators.json" >/dev/null 2>&1; then
    return
  fi

  if [[ "$INSTALL_RUNTIME" != true ]]; then
    fail "no available iPad simulator; rerun with --install-runtime"
  fi

  log "Downloading the matching iOS simulator runtime"
  caffeinate -dimsu xcodebuild -downloadPlatform iOS -architectureVariant arm64 \
    2>&1 | tee "$ARTIFACTS_DIR/logs/runtime-download.log"
  xcrun simctl list devices available -j > "$ARTIFACTS_DIR/logs/simulators.json"
}

select_simulator() {
  local selection

  if [[ -n "$SIMULATOR_UDID" ]]; then
    selection="$(python3 - "$ARTIFACTS_DIR/logs/simulators.json" "$SIMULATOR_UDID" <<'PY'
import json
import sys

payload = json.load(open(sys.argv[1], encoding="utf-8"))
wanted = sys.argv[2]
for runtime, devices in payload.get("devices", {}).items():
    for device in devices:
        if device.get("udid") == wanted and device.get("isAvailable", True):
            if "iPad" not in str(device.get("name", "")):
                raise SystemExit("the selected simulator is not an iPad")
            print(json.dumps({
                "name": device["name"],
                "udid": wanted,
                "runtime": runtime,
                "state": device.get("state", "Unknown"),
                "destination": f"platform=iOS Simulator,id={wanted}",
            }))
            raise SystemExit(0)
raise SystemExit(f"simulator is unavailable or unknown: {wanted}")
PY
)" || fail "unable to select simulator $SIMULATOR_UDID"
  else
    selection="$(python3 "$REPO_ROOT/scripts/ci/select_ios_simulator.py" \
      --input "$ARTIFACTS_DIR/logs/simulators.json")"
  fi

  printf '%s\n' "$selection" | python3 -m json.tool > "$ARTIFACTS_DIR/logs/selected-simulator.json"
  SELECTED_UDID="$(printf '%s' "$selection" | python3 -c 'import json,sys; print(json.load(sys.stdin)["udid"])')"
  SELECTED_NAME="$(printf '%s' "$selection" | python3 -c 'import json,sys; print(json.load(sys.stdin)["name"])')"
  SELECTED_RUNTIME="$(printf '%s' "$selection" | python3 -c 'import json,sys; print(json.load(sys.stdin)["runtime"])')"

  log "Selected $SELECTED_NAME ($SELECTED_UDID), runtime $SELECTED_RUNTIME"
}

require_aqua_session() {
  local uid session_file
  uid="$(id -u)"
  session_file="$TEMP_ROOT/aqua-session.txt"
  launchctl print "gui/$uid" > "$session_file" 2>/dev/null \
    || fail "UI tests require a logged-in macOS Aqua desktop session"
  grep -q 'session = Aqua' "$session_file" \
    || fail "UI tests require a logged-in macOS Aqua desktop session"
  osascript -e 'return "Aqua"' \
    > "$ARTIFACTS_DIR/logs/aqua-apple-event.log" 2>&1 \
    || fail "UI tests cannot execute AppleScript in the active desktop session"
}

boot_simulator() {
  xcrun simctl boot "$SELECTED_UDID" 2>/dev/null || true
  xcrun simctl bootstatus "$SELECTED_UDID" -b \
    2>&1 | tee "$ARTIFACTS_DIR/logs/simulator-boot.log"

  if is_ui_profile; then
    open -a Simulator
  fi
}

wait_for_simulator_cache() {
  local attempts=0
  local maximum=40

  while pgrep -f update_dyld_sim_shared_cache >/dev/null 2>&1; do
    attempts=$((attempts + 1))
    if (( attempts > maximum )); then
      fail "simulator cache initialization did not finish within 20 minutes"
    fi
    log "Waiting for one-time simulator cache initialization ($attempts/$maximum)"
    sleep 30
  done
}

result_summary() {
  local bundle="$1"
  local output="$2"
  if [[ -d "$bundle" ]]; then
    xcrun xcresulttool get test-results summary --path "$bundle" > "$output" 2>&1 || true
  fi
}

run_direct_phase() {
  local label="$1"
  shift
  local result="$ARTIFACTS_DIR/results/${label}.xcresult"
  local log_file="$ARTIFACTS_DIR/logs/${label}.log"
  local derived="$TEMP_ROOT/DerivedData-${label}"
  local status

  rm -rf "$result" "$derived"
  log "Running $label tests"

  set +e
  xcodebuild \
    -project "$REPO_ROOT/ios/FiliusPad.xcodeproj" \
    -scheme FiliusPad \
    -configuration Debug \
    -destination "platform=iOS Simulator,id=$SELECTED_UDID" \
    -destination-timeout 120 \
    -derivedDataPath "$derived" \
    -resultBundlePath "$result" \
    -parallel-testing-enabled NO \
    -maximum-concurrent-test-simulator-destinations 1 \
    "$@" \
    CODE_SIGNING_ALLOWED=NO \
    CODE_SIGNING_REQUIRED=NO \
    test 2>&1 | tee "$log_file"
  status="${PIPESTATUS[0]}"
  set -e

  result_summary "$result" "$ARTIFACTS_DIR/results/${label}-summary.json"
  return "$status"
}

run_aqua_ui_phase() {
  local label="$1"
  shift
  local result="$ARTIFACTS_DIR/results/${label}.xcresult"
  local log_file="$ARTIFACTS_DIR/logs/${label}.log"
  local summary="$ARTIFACTS_DIR/results/${label}-summary.json"
  local derived="$TEMP_ROOT/DerivedData-${label}"
  local inner_script="$TEMP_ROOT/run-${label}.sh"
  local status_file="$TEMP_ROOT/${label}.status"
  local tail_pid elapsed_limit elapsed status
  local -a command_args

  command_args=(
    xcodebuild
    -project "$REPO_ROOT/ios/FiliusPad.xcodeproj"
    -scheme FiliusPad
    -configuration Debug
    -destination "platform=iOS Simulator,id=$SELECTED_UDID"
    -destination-timeout 120
    -derivedDataPath "$derived"
    -resultBundlePath "$result"
    -parallel-testing-enabled NO
    -maximum-parallel-testing-workers 1
    -maximum-concurrent-test-simulator-destinations 1
  )
  command_args+=("$@")
  command_args+=(CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO test)

  rm -rf "$result" "$derived"
  rm -f "$status_file" "$log_file"
  touch "$log_file"

  {
    echo '#!/usr/bin/env bash'
    echo 'set -o pipefail'
    printf 'cd %q\n' "$REPO_ROOT"
    printf '%q ' "${command_args[@]}"
    printf '2>&1 | tee %q\n' "$log_file"
    echo 'status=${PIPESTATUS[0]}'
    printf 'printf "%%s\\n" "$status" > %q\n' "$status_file"
    echo 'exit "$status"'
  } > "$inner_script"
  chmod 700 "$inner_script"

  log "Running $label tests in the Aqua desktop session"
  tail -n +1 -F "$log_file" &
  tail_pid=$!

  osascript - "$inner_script" <<'APPLESCRIPT'
on run argv
    set scriptPath to item 1 of argv
    do shell script "/bin/bash " & quoted form of scriptPath & " >/dev/null 2>&1 &"
end run
APPLESCRIPT

  elapsed_limit=$((UI_TIMEOUT_MINUTES * 60))
  elapsed=0
  while [[ ! -f "$status_file" ]]; do
    if (( elapsed >= elapsed_limit )); then
      kill "$tail_pid" 2>/dev/null || true
      wait "$tail_pid" 2>/dev/null || true
      fail "$label tests exceeded ${UI_TIMEOUT_MINUTES} minutes"
    fi
    sleep 5
    elapsed=$((elapsed + 5))
  done

  kill "$tail_pid" 2>/dev/null || true
  wait "$tail_pid" 2>/dev/null || true
  status="$(cat "$status_file")"
  result_summary "$result" "$summary"
  return "$status"
}

collect_diagnostics() {
  if [[ -z "$SELECTED_UDID" ]]; then
    return
  fi

  xcrun simctl io "$SELECTED_UDID" screenshot \
    "$ARTIFACTS_DIR/diagnostics/simulator-final.png" >/dev/null 2>&1 || true
  xcrun simctl spawn "$SELECTED_UDID" log show \
    --style compact \
    --last 60m \
    --predicate 'process == "FiliusPad" OR process CONTAINS "FiliusPadUITests"' \
    > "$ARTIFACTS_DIR/diagnostics/simulator.log" 2>&1 || true
}

write_summary() {
  local outcome="$1"
  cat > "$ARTIFACTS_DIR/summary.txt" <<EOF
Outcome: $outcome
Profile: $PROFILE
Commit: $(git -C "$REPO_ROOT" rev-parse HEAD)
Simulator: $SELECTED_NAME
Simulator UDID: $SELECTED_UDID
Runtime: $SELECTED_RUNTIME
Xcode: $(xcodebuild -version | tr '\n' ' ')
Artifacts: $ARTIFACTS_DIR
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo) [[ $# -ge 2 ]] || fail '--repo requires a value'; REPO_ROOT="$2"; shift 2 ;;
    --profile) [[ $# -ge 2 ]] || fail '--profile requires a value'; PROFILE="$2"; shift 2 ;;
    --sync) SYNC_REPOSITORY=true; shift ;;
    --branch) [[ $# -ge 2 ]] || fail '--branch requires a value'; BRANCH="$2"; shift 2 ;;
    --revision) [[ $# -ge 2 ]] || fail '--revision requires a value'; REVISION="$2"; shift 2 ;;
    --simulator-udid) [[ $# -ge 2 ]] || fail '--simulator-udid requires a value'; SIMULATOR_UDID="$2"; shift 2 ;;
    --artifacts-root) [[ $# -ge 2 ]] || fail '--artifacts-root requires a value'; ARTIFACTS_ROOT="$2"; shift 2 ;;
    --install-runtime) INSTALL_RUNTIME=true; shift ;;
    --keep-simulator-running) KEEP_SIMULATOR_RUNNING=true; shift ;;
    --ui-timeout-minutes) [[ $# -ge 2 ]] || fail '--ui-timeout-minutes requires a value'; UI_TIMEOUT_MINUTES="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) fail "unknown argument: $1" ;;
  esac
done

case "$PROFILE" in
  smoke|unit|ui|runtime-ui|desktop-ui|service-ui|simulation-ui|full) ;;
  *) fail "unsupported profile: $PROFILE" ;;
esac
[[ "$UI_TIMEOUT_MINUTES" =~ ^[1-9][0-9]*$ ]] || fail '--ui-timeout-minutes must be a positive integer'

REPO_ROOT="$(expand_path "$REPO_ROOT")"
ARTIFACTS_ROOT="$(expand_path "$ARTIFACTS_ROOT")"

require_command git
require_command python3
require_command xcodebuild
require_command xcrun
require_command caffeinate
if is_ui_profile; then
  require_command osascript
fi

[[ -e "$REPO_ROOT/.git" ]] || fail "repository checkout not found: $REPO_ROOT"
if [[ "$SYNC_REPOSITORY" == true ]]; then
  synchronize_repository
fi
[[ -f "$REPO_ROOT/ios/FiliusPad.xcodeproj/project.pbxproj" ]] || fail 'FiliusPad.xcodeproj is missing'

prepare_artifacts
record_toolchain
ensure_simulator_runtime
xcrun simctl list devices available -j > "$ARTIFACTS_DIR/logs/simulators.json"
select_simulator
if is_ui_profile; then
  require_aqua_session
fi
boot_simulator
wait_for_simulator_cache

unit_status=0
ui_status=0

case "$PROFILE" in
  smoke)
    run_direct_phase unit-smoke -only-testing:FiliusPadTests/ViewportTransformTests || unit_status=$?
    run_aqua_ui_phase ui-smoke -only-testing:FiliusPadUITests/FiliusPadUITests/testLaunchesEditorScreen || ui_status=$?
    ;;
  unit)
    run_direct_phase unit -only-testing:FiliusPadTests || unit_status=$?
    ;;
  ui)
    run_aqua_ui_phase ui -only-testing:FiliusPadUITests || ui_status=$?
    ;;
  runtime-ui)
    run_aqua_ui_phase runtime-ui \
      -only-testing:FiliusPadUITests/TopologyRuntimeDesktopSuiteParityUITests \
      -only-testing:FiliusPadUITests/TopologyRuntimeServiceAppParityUITests \
      -only-testing:FiliusPadUITests/TopologySimulationRuntimeUITests || ui_status=$?
    ;;
  desktop-ui)
    run_aqua_ui_phase desktop-ui \
      -only-testing:FiliusPadUITests/TopologyRuntimeDesktopSuiteParityUITests || ui_status=$?
    ;;
  service-ui)
    run_aqua_ui_phase service-ui \
      -only-testing:FiliusPadUITests/TopologyRuntimeServiceAppParityUITests || ui_status=$?
    ;;
  simulation-ui)
    run_aqua_ui_phase simulation-ui \
      -only-testing:FiliusPadUITests/TopologySimulationRuntimeUITests || ui_status=$?
    ;;
  full)
    run_direct_phase unit -only-testing:FiliusPadTests || unit_status=$?
    run_aqua_ui_phase ui -only-testing:FiliusPadUITests || ui_status=$?
    ;;
esac

collect_diagnostics
if [[ "$KEEP_SIMULATOR_RUNNING" != true ]]; then
  xcrun simctl shutdown "$SELECTED_UDID" >/dev/null 2>&1 || true
fi

if (( unit_status == 0 && ui_status == 0 )); then
  write_summary PASSED
  log "All selected tests passed"
  printf 'ARTIFACTS_DIR=%s\n' "$ARTIFACTS_DIR"
  exit 0
fi

write_summary FAILED
log "Tests failed (unit status: $unit_status, UI status: $ui_status)"
printf 'ARTIFACTS_DIR=%s\n' "$ARTIFACTS_DIR"
exit 1
