#!/usr/bin/env bash
set -euo pipefail

CONF=${1:-release}
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"

if [[ -f "$ROOT/version.env" ]]; then
  # shellcheck disable=SC1090
  source "$ROOT/version.env"
fi

APP_TARGET=${APP_TARGET:-CodexXPCBridgeDemo}
APP_NAME=${APP_NAME:-CodexXPCBridgeDemo}
APP_BUNDLE_ID=${APP_BUNDLE_ID:-dev.codex.xpcbridge.demo}
SERVICE_TARGET=${SERVICE_TARGET:-CodexXPCBridgeService}
SERVICE_NAME=${SERVICE_NAME:-CodexXPCBridgeService}
SERVICE_BUNDLE_ID=${SERVICE_BUNDLE_ID:-${APP_BUNDLE_ID}.CodexXPCBridgeService}
CODEX_TARGET=${CODEX_TARGET:-codex}
CODEX_RESOURCE_NAME=${CODEX_RESOURCE_NAME:-codex}
MACOS_MIN_VERSION=${MACOS_MIN_VERSION:-14.0}
SIGNING_MODE=${SIGNING_MODE:-adhoc}
APP_IDENTITY=${APP_IDENTITY:-}
APP_ENTITLEMENTS=${APP_ENTITLEMENTS:-$ROOT/Config/CodexXPCBridgeDemo.entitlements}
SERVICE_ENTITLEMENTS=${SERVICE_ENTITLEMENTS:-$ROOT/Config/CodexXPCBridgeService.entitlements}
APP_TEMPLATE=${APP_TEMPLATE:-$ROOT/Config/CodexXPCBridgeDemo-Info.plist.template}
SERVICE_TEMPLATE=${SERVICE_TEMPLATE:-$ROOT/Config/CodexXPCBridgeService-Info.plist.template}
MARKETING_VERSION=${MARKETING_VERSION:-0.1.0}
BUILD_NUMBER=${BUILD_NUMBER:-1}

ARCH_LIST=( ${ARCHES:-} )
if [[ ${#ARCH_LIST[@]} -eq 0 ]]; then
  ARCH_LIST=("$(uname -m)")
fi

build_product_path() {
  local name="$1"
  local arch="$2"
  case "$arch" in
    arm64|x86_64) echo ".build/${arch}-apple-macosx/$CONF/$name" ;;
    *) echo ".build/$CONF/$name" ;;
  esac
}

for arch in "${ARCH_LIST[@]}"; do
  swift build -c "$CONF" --arch "$arch" --product "$APP_TARGET"
  swift build -c "$CONF" --arch "$arch" --product "$SERVICE_TARGET"
  swift build -c "$CONF" --arch "$arch" --product "$CODEX_TARGET"
done

install_universal_binary() {
  local product="$1"
  local destination="$2"
  local binaries=()
  for arch in "${ARCH_LIST[@]}"; do
    local source_path
    source_path=$(build_product_path "$product" "$arch")
    [[ -f "$source_path" ]] || { echo "Missing build product: $source_path" >&2; exit 1; }
    binaries+=("$source_path")
  done
  if [[ ${#binaries[@]} -gt 1 ]]; then
    lipo -create "${binaries[@]}" -output "$destination"
  else
    cp "${binaries[0]}" "$destination"
  fi
  chmod +x "$destination"
}

render_template() {
  local template="$1"
  local destination="$2"
  sed \
    -e "s|__APP_NAME__|$APP_NAME|g" \
    -e "s|__APP_BUNDLE_ID__|$APP_BUNDLE_ID|g" \
    -e "s|__APP_EXECUTABLE__|$APP_TARGET|g" \
    -e "s|__SERVICE_NAME__|$SERVICE_NAME|g" \
    -e "s|__SERVICE_BUNDLE_ID__|$SERVICE_BUNDLE_ID|g" \
    -e "s|__SERVICE_EXECUTABLE__|$SERVICE_TARGET|g" \
    -e "s|__MARKETING_VERSION__|$MARKETING_VERSION|g" \
    -e "s|__BUILD_NUMBER__|$BUILD_NUMBER|g" \
    -e "s|__MACOS_MIN_VERSION__|$MACOS_MIN_VERSION|g" \
    "$template" > "$destination"
}

if [[ "$SIGNING_MODE" == "adhoc" || -z "$APP_IDENTITY" ]]; then
  CODESIGN_ARGS=(--force --sign "-")
else
  CODESIGN_ARGS=(--force --timestamp --options runtime --sign "$APP_IDENTITY")
fi

APP_BUNDLE="$ROOT/${APP_NAME}.app"
SERVICE_BUNDLE="$APP_BUNDLE/Contents/XPCServices/${SERVICE_NAME}.xpc"
rm -rf "$APP_BUNDLE"
mkdir -p \
  "$APP_BUNDLE/Contents/MacOS" \
  "$APP_BUNDLE/Contents/Resources" \
  "$APP_BUNDLE/Contents/XPCServices" \
  "$SERVICE_BUNDLE/Contents/MacOS" \
  "$SERVICE_BUNDLE/Contents/Resources"

render_template "$APP_TEMPLATE" "$APP_BUNDLE/Contents/Info.plist"
render_template "$SERVICE_TEMPLATE" "$SERVICE_BUNDLE/Contents/Info.plist"

install_universal_binary "$APP_TARGET" "$APP_BUNDLE/Contents/MacOS/$APP_TARGET"
install_universal_binary "$SERVICE_TARGET" "$SERVICE_BUNDLE/Contents/MacOS/$SERVICE_TARGET"
install_universal_binary "$CODEX_TARGET" "$SERVICE_BUNDLE/Contents/Resources/$CODEX_RESOURCE_NAME"

chmod -R u+w "$APP_BUNDLE"
xattr -cr "$APP_BUNDLE"
find "$APP_BUNDLE" -name '._*' -delete

codesign "${CODESIGN_ARGS[@]}" "$SERVICE_BUNDLE/Contents/Resources/$CODEX_RESOURCE_NAME"
codesign "${CODESIGN_ARGS[@]}" --entitlements "$SERVICE_ENTITLEMENTS" "$SERVICE_BUNDLE/Contents/MacOS/$SERVICE_TARGET"
codesign "${CODESIGN_ARGS[@]}" --entitlements "$SERVICE_ENTITLEMENTS" "$SERVICE_BUNDLE"
codesign "${CODESIGN_ARGS[@]}" --entitlements "$APP_ENTITLEMENTS" "$APP_BUNDLE"

echo "Created $APP_BUNDLE"
echo "Nested XPC service: $SERVICE_BUNDLE"
