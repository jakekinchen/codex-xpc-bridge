#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
BUNDLE_PATH="${1:-}"

EXPECTED_DOCS=(
  "$ROOT_DIR/docs/locked-facts-mas-runtime.md"
  "$ROOT_DIR/docs/app-store/mas-xpc-to-codex-stdio-architecture.md"
  "$ROOT_DIR/docs/plans/active/2026-03-12-mas-xpc-stdio-bridge-implementation-plan.md"
  "$ROOT_DIR/docs/plans/active/mas-test-strategy.md"
  "$ROOT_DIR/docs/plans/active/mas-implementation-packets.md"
)

EXPECTED_BUNDLE_PATHS=(
  "Contents/XPCServices/CodexXPCBridgeService.xpc"
  "Contents/XPCServices/CodexXPCBridgeService.xpc/Contents/MacOS/CodexXPCBridgeService"
  "Contents/XPCServices/CodexXPCBridgeService.xpc/Contents/Resources/codex"
)

FORBIDDEN_BUNDLE_PATTERNS=(
  "node"
  "node_modules"
  "daemon/dist"
  "localhost"
  "127.0.0.1"
  "scripts/wgsl/convert-any-shader.mjs"
)

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

note() {
  printf 'INFO: %s\n' "$1"
}

pass() {
  printf 'PASS: %s\n' "$1"
}

require_file() {
  local path="$1"
  [[ -f "$path" ]] || fail "missing required file: $path"
}

check_docs() {
  local path
  for path in "${EXPECTED_DOCS[@]}"; do
    require_file "$path"
  done
  pass "required MAS planning docs are present"
}

check_repo_forbidden_markers() {
  if rg -n --hidden \
    --glob '!docs/**' \
    --glob '!prompt-seed.txt' \
    '127\.0\.0\.1|localhost|codex app-server|daemon/dist|node_modules' \
    "$ROOT_DIR" >/dev/null 2>&1; then
    fail "repository contains legacy topology markers outside docs"
  fi
  pass "no legacy topology markers detected outside documentation"
}

check_bundle_paths() {
  local rel
  for rel in "${EXPECTED_BUNDLE_PATHS[@]}"; do
    [[ -e "$BUNDLE_PATH/$rel" ]] || fail "bundle missing expected path: $rel"
  done
  pass "bundle contains expected XPC and Codex paths"
}

check_bundle_forbidden_paths() {
  local pattern
  for pattern in "${FORBIDDEN_BUNDLE_PATTERNS[@]}"; do
    if find "$BUNDLE_PATH" -print | rg -n "$pattern" >/dev/null 2>&1; then
      fail "bundle contains forbidden marker or path: $pattern"
    fi
  done
  pass "bundle contains no forbidden legacy payload markers"
}

check_bundle_text_markers() {
  if rg -n -a '127\.0\.0\.1|localhost' "$BUNDLE_PATH" >/dev/null 2>&1; then
    fail "bundle contains localhost transport markers"
  fi
  pass "bundle contains no localhost transport markers"
}

check_bundle_mode() {
  [[ -d "$BUNDLE_PATH" ]] || fail "bundle path does not exist: $BUNDLE_PATH"
  check_bundle_paths
  check_bundle_forbidden_paths
  check_bundle_text_markers
}

main() {
  note "running MAS readiness checks from $ROOT_DIR"
  check_docs
  check_repo_forbidden_markers

  if [[ -n "$BUNDLE_PATH" ]]; then
    note "bundle inspection enabled for $BUNDLE_PATH"
    check_bundle_mode
  else
    note "bundle path not provided; skipped bundle content inspection"
  fi

  pass "MAS readiness gate passed"
}

main "$@"
