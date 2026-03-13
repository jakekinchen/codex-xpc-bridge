#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
APP_NAME=${APP_NAME:-CodexXPCBridgeDemo}

"$ROOT/scripts/package_app.sh" "${1:-debug}"
open "$ROOT/${APP_NAME}.app"
