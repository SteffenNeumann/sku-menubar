#!/bin/bash
# Build myClaude and deploy binary into ~/Applications/myClaude.app
# Usage: ./tools/deploy.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
APP_BUNDLE="$HOME/Applications/myClaude.app/Contents/MacOS/myClaude"
BINARY="$REPO_ROOT/.build/arm64-apple-macosx/debug/myClaude"

echo "🔨 Building..."
cd "$REPO_ROOT"
swift build

echo "🛑 Stopping running instance..."
kill -9 $(ps aux | grep myClaude | grep -v grep | awk '{print $2}') 2>/dev/null || true
sleep 1

if [ -f "$APP_BUNDLE" ]; then
    echo "📦 Deploying to $APP_BUNDLE..."
    cp "$BINARY" "$APP_BUNDLE"
    echo "🚀 Launching from Dock app..."
    open "$HOME/Applications/myClaude.app"
else
    echo "⚠️  App bundle not found at $APP_BUNDLE — launching dev binary directly..."
    open "$BINARY"
fi

echo "✅ Done: $(git -C "$REPO_ROOT" rev-parse --short HEAD) · $(date '+%Y-%m-%d %H:%M')"
