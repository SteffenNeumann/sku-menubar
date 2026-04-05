#!/bin/bash
# Build myClaude and deploy binary into ~/Applications/myClaude.app
# Usage: ./tools/deploy.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
APP_BUNDLE="$HOME/Applications/myClaude.app/Contents/MacOS/myClaude"
# NSBundle.module accessor searches Bundle.main.bundleURL (= app root, sibling to Contents/)
APP_BUNDLE_ROOT="$HOME/Applications/myClaude.app"
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
    # Copy Highlightr resource bundle to app root (NSBundle.module: Bundle.main.bundleURL/Highlightr_Highlightr.bundle)
    if [ -d "$BUNDLE" ]; then
        # Fix permissions on existing bundle before overwriting to avoid "Permission denied"
        [ -d "$APP_BUNDLE_ROOT/Highlightr_Highlightr.bundle" ] && chmod -R u+w "$APP_BUNDLE_ROOT/Highlightr_Highlightr.bundle"
        cp -R "$BUNDLE" "$APP_BUNDLE_ROOT/"
        echo "📦 Copied Highlightr_Highlightr.bundle → app root"
    else
        echo "⚠️  Highlightr bundle not found at $BUNDLE"
    fi
    # Remove stale copies from previous wrong locations
    rm -rf "$HOME/Applications/myClaude.app/Contents/MacOS/Highlightr_Highlightr.bundle"
    rm -rf "$HOME/Applications/myClaude.app/Contents/Resources/Highlightr_Highlightr.bundle"
    echo "🚀 Launching from Dock app..."
    open "$HOME/Applications/myClaude.app"
else
    echo "⚠️  App bundle not found at $APP_BUNDLE — launching dev binary directly..."
    open "$BINARY"
fi

echo "✅ Done: $(git -C "$REPO_ROOT" rev-parse --short HEAD) · $(date '+%Y-%m-%d %H:%M')"
