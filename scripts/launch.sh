#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
APP_NAME=${APP_NAME:-CodexXPCBridgeDemo}
open "$ROOT/${APP_NAME}.app"
