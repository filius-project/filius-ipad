#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_PATH="$ROOT_DIR/FiliusPad.xcodeproj"
SCHEME="${FILIUSPAD_SCHEME:-FiliusPad}"
CONFIGURATION="${FILIUSPAD_CONFIGURATION:-Release}"
ARCHIVE_PATH="${FILIUSPAD_ARCHIVE_PATH-$ROOT_DIR/build/archive/FiliusPad.xcarchive}"
EXPORT_DIR="${FILIUSPAD_EXPORT_DIR-$ROOT_DIR/build/ipa}"
IPA_OUTPUT_PATH="${FILIUSPAD_IPA_OUTPUT_PATH-$EXPORT_DIR/FiliusPad.ipa}"
EXPORT_OPTIONS_PLIST="${FILIUSPAD_EXPORT_OPTIONS_PLIST-$EXPORT_DIR/ExportOptions.plist}"
DERIVED_DATA_PATH="${FILIUSPAD_DERIVED_DATA_PATH-$ROOT_DIR/build/derived-data}"
UNSIGNED_APP_PATH="${FILIUSPAD_UNSIGNED_APP_PATH-$DERIVED_DATA_PATH/Build/Products/${CONFIGURATION}-iphoneos/${SCHEME}.app}"
DEVELOPMENT_TEAM="${FILIUSPAD_DEVELOPMENT_TEAM:-}"
EXPORT_METHOD="${FILIUSPAD_EXPORT_METHOD:-}"
CODE_SIGN_STYLE="${FILIUSPAD_CODE_SIGN_STYLE:-automatic}"
BUNDLE_IDENTIFIER="${FILIUSPAD_BUNDLE_IDENTIFIER:-}"
PROVISIONING_PROFILE_SPECIFIER="${FILIUSPAD_PROVISIONING_PROFILE_SPECIFIER:-}"
PACKAGE_DRY_RUN="${FILIUSPAD_PACKAGE_DRY_RUN:-0}"
UNSIGNED_MODE="${FILIUSPAD_UNSIGNED:-0}"
ARCHIVE_TIMEOUT_SECONDS="${FILIUSPAD_ARCHIVE_TIMEOUT_SECONDS:-}"
EXPORT_TIMEOUT_SECONDS="${FILIUSPAD_EXPORT_TIMEOUT_SECONDS:-}"

log() {
  printf '[package-ipa] %s\n' "$1"
}

fail_config() {
  log "✗ $1"
  exit "$2"
}

validate_timeout() {
  local label="$1"
  local value="$2"
  local code="$3"

  if [[ -n "$value" ]] && [[ ! "$value" =~ ^[0-9]+$ ]]; then
    fail_config "Invalid ${label}='${value}' (expected integer seconds)" "$code"
  fi
}

validate_configuration() {
  case "$PACKAGE_DRY_RUN" in
    0|1)
      ;;
    *)
      fail_config "Invalid FILIUSPAD_PACKAGE_DRY_RUN='${PACKAGE_DRY_RUN}' (expected 0 or 1)" 90
      ;;
  esac

  case "$UNSIGNED_MODE" in
    0|1)
      ;;
    *)
      fail_config "Invalid FILIUSPAD_UNSIGNED='${UNSIGNED_MODE}' (expected 0 or 1)" 89
      ;;
  esac

  validate_timeout "FILIUSPAD_ARCHIVE_TIMEOUT_SECONDS" "$ARCHIVE_TIMEOUT_SECONDS" 91
  validate_timeout "FILIUSPAD_EXPORT_TIMEOUT_SECONDS" "$EXPORT_TIMEOUT_SECONDS" 92

  if [[ "$UNSIGNED_MODE" == "0" ]]; then
    if [[ -z "$DEVELOPMENT_TEAM" ]]; then
      fail_config "Missing required FILIUSPAD_DEVELOPMENT_TEAM" 93
    fi

    if [[ -z "$EXPORT_METHOD" ]]; then
      fail_config "Missing required FILIUSPAD_EXPORT_METHOD" 94
    fi

    case "$EXPORT_METHOD" in
      app-store|app-store-connect|ad-hoc|enterprise|development)
        ;;
      *)
        fail_config "Invalid FILIUSPAD_EXPORT_METHOD='${EXPORT_METHOD}' (allowed: app-store, app-store-connect, ad-hoc, enterprise, development)" 95
        ;;
    esac

    case "$CODE_SIGN_STYLE" in
      automatic|manual)
        ;;
      *)
        fail_config "Invalid FILIUSPAD_CODE_SIGN_STYLE='${CODE_SIGN_STYLE}' (expected automatic or manual)" 96
        ;;
    esac

    if [[ "$CODE_SIGN_STYLE" == "manual" ]]; then
      if [[ -z "$PROVISIONING_PROFILE_SPECIFIER" ]]; then
        fail_config "FILIUSPAD_PROVISIONING_PROFILE_SPECIFIER is required when FILIUSPAD_CODE_SIGN_STYLE=manual" 102
      fi

      if [[ -z "$BUNDLE_IDENTIFIER" ]]; then
        fail_config "FILIUSPAD_BUNDLE_IDENTIFIER is required when FILIUSPAD_CODE_SIGN_STYLE=manual" 103
      fi
    fi
  fi

  if [[ -z "$PROJECT_PATH" ]] || [[ ! -f "$PROJECT_PATH/project.pbxproj" ]]; then
    fail_config "Xcode project not found at ${PROJECT_PATH}" 97
  fi

  if [[ -z "$ARCHIVE_PATH" ]]; then
    fail_config "FILIUSPAD_ARCHIVE_PATH must not be empty" 98
  fi

  if [[ -z "$EXPORT_DIR" ]]; then
    fail_config "FILIUSPAD_EXPORT_DIR must not be empty" 99
  fi

  if [[ -z "$IPA_OUTPUT_PATH" ]]; then
    fail_config "FILIUSPAD_IPA_OUTPUT_PATH must not be empty" 100
  fi

  if [[ "$IPA_OUTPUT_PATH" != *.ipa ]]; then
    fail_config "FILIUSPAD_IPA_OUTPUT_PATH must end with .ipa" 101
  fi
}

run_with_optional_timeout() {
  local timeout_seconds="$1"
  shift

  if [[ -n "$timeout_seconds" ]]; then
    if command -v timeout >/dev/null 2>&1; then
      timeout "$timeout_seconds" "$@"
      return
    fi

    log "timeout requested (${timeout_seconds}s) but 'timeout' command is unavailable; running without timeout wrapper"
  fi

  "$@"
}

run_phase() {
  local phase="$1"
  local timeout_seconds="$2"
  shift 2

  local started_at
  started_at="$(date +%s)"

  log "▶ ${phase}"

  set +e
  run_with_optional_timeout "$timeout_seconds" "$@"
  local status=$?
  set -e

  local finished_at
  finished_at="$(date +%s)"
  local duration=$((finished_at - started_at))

  if [[ $status -ne 0 ]]; then
    if [[ $status -eq 124 ]]; then
      log "✗ ${phase} timed out after ${duration}s"
    else
      log "✗ ${phase} failed after ${duration}s"
    fi

    log "  command: $*"
    exit "$status"
  fi

  log "✓ ${phase} passed in ${duration}s"
}

effective_export_method() {
  if [[ "$EXPORT_METHOD" == "app-store-connect" ]]; then
    printf 'app-store\n'
    return
  fi

  printf '%s\n' "$EXPORT_METHOD"
}

write_export_options_plist() {
  mkdir -p "$EXPORT_DIR"

  local method
  method="$(effective_export_method)"

  local signing_style
  signing_style="Automatic"
  if [[ "$CODE_SIGN_STYLE" == "manual" ]]; then
    signing_style="Manual"
  fi

  {
    printf '%s\n' '<?xml version="1.0" encoding="UTF-8"?>'
    printf '%s\n' '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">'
    printf '%s\n' '<plist version="1.0">'
    printf '%s\n' '<dict>'
    printf '  <key>method</key><string>%s</string>\n' "$method"
    printf '  <key>teamID</key><string>%s</string>\n' "$DEVELOPMENT_TEAM"
    printf '  <key>signingStyle</key><string>%s</string>\n' "$signing_style"

    if [[ "$CODE_SIGN_STYLE" == "manual" ]]; then
      printf '%s\n' '  <key>provisioningProfiles</key>'
      printf '%s\n' '  <dict>'
      printf '    <key>%s</key><string>%s</string>\n' "$BUNDLE_IDENTIFIER" "$PROVISIONING_PROFILE_SPECIFIER"
      printf '%s\n' '  </dict>'
    fi

    printf '%s\n' '</dict>'
    printf '%s\n' '</plist>'
  } > "$EXPORT_OPTIONS_PLIST"
}

ensure_ipa_exists() {
  if [[ -f "$IPA_OUTPUT_PATH" ]]; then
    return 0
  fi

  log "✗ Expected IPA artifact not found at ${IPA_OUTPUT_PATH}"

  local discovered
  discovered="$(find "$EXPORT_DIR" -maxdepth 2 -type f -name '*.ipa' -print 2>/dev/null | head -n 1 || true)"
  if [[ -n "$discovered" ]]; then
    log "  discovered ipa candidate: ${discovered}"
  fi

  return 104
}

assemble_unsigned_ipa() {
  rm -rf "$EXPORT_DIR/Payload"
  mkdir -p "$EXPORT_DIR/Payload"
  cp -R "$UNSIGNED_APP_PATH" "$EXPORT_DIR/Payload/"

  (
    cd "$EXPORT_DIR"
    zip -qry "$(basename "$IPA_OUTPUT_PATH")" Payload
  )
}

build_unsigned_ipa() {
  if ! command -v zip >/dev/null 2>&1; then
    fail_config "zip command is required for unsigned IPA packaging" 106
  fi

  mkdir -p "$DERIVED_DATA_PATH" "$EXPORT_DIR"
  rm -rf "$UNSIGNED_APP_PATH"
  rm -f "$IPA_OUTPUT_PATH"

  run_phase \
    "Build (xcodebuild unsigned app)" \
    "$ARCHIVE_TIMEOUT_SECONDS" \
    xcodebuild \
    -project "$PROJECT_PATH" \
    -scheme "$SCHEME" \
    -configuration "$CONFIGURATION" \
    -destination "generic/platform=iOS" \
    -derivedDataPath "$DERIVED_DATA_PATH" \
    CODE_SIGNING_ALLOWED=NO \
    CODE_SIGNING_REQUIRED=NO \
    CODE_SIGN_IDENTITY="" \
    build

  if [[ ! -d "$UNSIGNED_APP_PATH" ]]; then
    log "✗ Unsigned app artifact missing at ${UNSIGNED_APP_PATH}"
    exit 107
  fi

  run_phase "Assemble unsigned IPA (Payload zip)" "$EXPORT_TIMEOUT_SECONDS" assemble_unsigned_ipa

  if ! ensure_ipa_exists; then
    exit $?
  fi
}

run_dry_run() {
  log "▶ Dry run: validate package contract"
  log "  project: ${PROJECT_PATH}"
  log "  scheme: ${SCHEME}"
  log "  configuration: ${CONFIGURATION}"
  log "  export dir: ${EXPORT_DIR}"
  log "  ipa path: ${IPA_OUTPUT_PATH}"

  if [[ "$UNSIGNED_MODE" == "1" ]]; then
    log "  mode: unsigned"
    log "  derived data path: ${DERIVED_DATA_PATH}"
    log "  unsigned app path: ${UNSIGNED_APP_PATH}"
    log "  build command: xcodebuild -project \"${PROJECT_PATH}\" -scheme \"${SCHEME}\" -configuration \"${CONFIGURATION}\" -destination \"generic/platform=iOS\" -derivedDataPath \"${DERIVED_DATA_PATH}\" CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY=\"\" build"
    log "  package command: (cd \"${EXPORT_DIR}\" && zip -qry \"$(basename "$IPA_OUTPUT_PATH")\" Payload)"
    log "✓ Dry run complete"
    return
  fi

  local method
  method="$(effective_export_method)"

  log "  archive path: ${ARCHIVE_PATH}"
  log "  export method: ${method}"
  log "  code sign style: ${CODE_SIGN_STYLE}"

  if [[ -n "$PROVISIONING_PROFILE_SPECIFIER" ]]; then
    log "  provisioning profile specifier: [provided]"
  else
    log "  provisioning profile specifier: [not provided]"
  fi

  log "  archive command: xcodebuild -project \"${PROJECT_PATH}\" -scheme \"${SCHEME}\" -configuration \"${CONFIGURATION}\" -archivePath \"${ARCHIVE_PATH}\" DEVELOPMENT_TEAM=\"${DEVELOPMENT_TEAM}\" CODE_SIGN_STYLE=\"${CODE_SIGN_STYLE}\" archive"
  log "  export command: xcodebuild -exportArchive -archivePath \"${ARCHIVE_PATH}\" -exportPath \"${EXPORT_DIR}\" -exportOptionsPlist \"${EXPORT_OPTIONS_PLIST}\""
  log "✓ Dry run complete"
}

validate_configuration

if [[ "$PACKAGE_DRY_RUN" == "1" ]]; then
  run_dry_run
  exit 0
fi

if [[ "$(uname -s)" != "Darwin" ]]; then
  fail_config "IPA packaging requires macOS xcodebuild; set FILIUSPAD_PACKAGE_DRY_RUN=1 for non-mac contract checks" 127
fi

if ! command -v xcodebuild >/dev/null 2>&1; then
  fail_config "xcodebuild is required for archive/export packaging" 126
fi

if [[ "$UNSIGNED_MODE" == "1" ]]; then
  build_unsigned_ipa
  log "✓ IPA packaging completed (unsigned): ${IPA_OUTPUT_PATH}"
  exit 0
fi

mkdir -p "$(dirname "$ARCHIVE_PATH")" "$EXPORT_DIR"
rm -rf "$ARCHIVE_PATH"
rm -f "$IPA_OUTPUT_PATH"

run_phase "Export options generation" "" write_export_options_plist

run_phase \
  "Archive (xcodebuild archive)" \
  "$ARCHIVE_TIMEOUT_SECONDS" \
  xcodebuild \
  -project "$PROJECT_PATH" \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -archivePath "$ARCHIVE_PATH" \
  DEVELOPMENT_TEAM="$DEVELOPMENT_TEAM" \
  CODE_SIGN_STYLE="$CODE_SIGN_STYLE" \
  archive

if [[ ! -d "$ARCHIVE_PATH" ]]; then
  log "✗ Archive artifact missing at ${ARCHIVE_PATH}"
  exit 105
fi

run_phase \
  "Export (xcodebuild -exportArchive)" \
  "$EXPORT_TIMEOUT_SECONDS" \
  xcodebuild \
  -exportArchive \
  -archivePath "$ARCHIVE_PATH" \
  -exportPath "$EXPORT_DIR" \
  -exportOptionsPlist "$EXPORT_OPTIONS_PLIST"

if ! ensure_ipa_exists; then
  exit $?
fi

log "✓ IPA packaging completed: ${IPA_OUTPUT_PATH}"
