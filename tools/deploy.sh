#!/bin/bash
# Build myClaude and deploy binary into ~/Applications/myClaude.app
# Usage: ./tools/deploy.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
APP_BUNDLE="$HOME/Applications/myClaude.app/Contents/MacOS/myClaude"
APP_RESOURCES_DIR="$HOME/Applications/myClaude.app/Contents/Resources"
BINARY="$REPO_ROOT/.build/arm64-apple-macosx/debug/myClaude"
BUNDLE="$REPO_ROOT/.build/arm64-apple-macosx/debug/Highlightr_Highlightr.bundle"

echo "🔨 Building..."
cd "$REPO_ROOT"
swift build

echo "🛑 Stopping running instance..."
kill -9 $(ps aux | grep myClaude | grep -v grep | awk '{print $2}') 2>/dev/null || true
sleep 1

if [ -f "$APP_BUNDLE" ]; then
    echo "📦 Deploying to $APP_BUNDLE..."
    cp "$BINARY" "$APP_BUNDLE"
    # Copy Highlightr resource bundle into Resources/ (NSBundle.module searches there)
    if [ -d "$BUNDLE" ]; then
        mkdir -p "$APP_RESOURCES_DIR"
        cp -R "$BUNDLE" "$APP_RESOURCES_DIR/"
        echo "📦 Copied Highlightr_Highlightr.bundle → Resources/"
    else
        echo "⚠️  Highlightr bundle not found at $BUNDLE"
    fi
    # Remove stale copy from MacOS/ if present (from previous broken deploy)
    rm -rf "$HOME/Applications/myClaude.app/Contents/MacOS/Highlightr_Highlightr.bundle"
    echo "🚀 Launching from Dock app..."
    open "$HOME/Applications/myClaude.app"
else
    echo "⚠️  App bundle not found at $APP_BUNDLE — launching dev binary directly..."
    open "$BINARY"
fi

echo "✅ Done: $(git -C "$REPO_ROOT" rev-parse --short HEAD) · $(date '+%Y-%m-%d %H:%M')"
