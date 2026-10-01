#!/bin/bash
# Holt den neuesten Stand von main, baut myClaude und installiert es nach ~/Applications.
# Läuft automatisch per launchd (tools/install-autoupdate.sh) oder von Hand.
#
#   tools/update.sh          nur bauen, wenn origin/main neuer ist als die installierte App
#   tools/update.sh --force  immer bauen (auch lokale, ungepushte Commits)
set -euo pipefail
export PATH="/usr/bin:/bin:/usr/sbin:/sbin:$PATH"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$SCRIPT_DIR/.." && pwd)"
APP="$HOME/Applications/myClaude.app"
STATE_DIR="$HOME/Library/Application Support/myClaude-update"
STAMP="$STATE_DIR/installed-commit"
LOCK="$STATE_DIR/lock"
FORCE=0; [ "${1:-}" = "--force" ] && FORCE=1

log() { echo "$(date '+%Y-%m-%d %H:%M:%S') $*"; }

mkdir -p "$STATE_DIR"
if ! mkdir "$LOCK" 2>/dev/null; then
    # Verwaister Lock (> 1 h) aus abgebrochenem Lauf wird übernommen.
    if [ -n "$(find "$LOCK" -maxdepth 0 -mmin +60 2>/dev/null)" ]; then rm -rf "$LOCK"; mkdir "$LOCK"
    else log "Läuft schon – Abbruch."; exit 0; fi
fi
trap 'rm -rf "$LOCK"' EXIT
trap 'log "❌ Abbruch in Zeile $LINENO"' ERR

cd "$REPO"
case "$REPO" in
    "$HOME/Documents"*|"$HOME/Desktop"*|*"Mobile Documents"*)
        log "⚠️  Repo liegt in iCloud ($REPO) – dort entstehen kaputte ' 2'-Dateien. Bitte nach ~/Developer klonen." ;;
esac

BUILDINFO="Sources/SKUMenuBar/BuildInfo.swift"
BRANCH="$(git rev-parse --abbrev-ref HEAD)"
# BuildInfo.swift schreibt jeder Build neu – zählt nicht als eigene Änderung. Ein abgebrochener
# Lauf hinterlässt sie geändert; ohne diese Ausnahme bliebe das Auto-Update dauerhaft stehen.
DIRTY="$(git status --porcelain --untracked-files=no -- . ":!$BUILDINFO")"
if [ "$BRANCH" = "main" ] && [ -z "$DIRTY" ]; then
    git checkout -- "$BUILDINFO"
    git fetch --quiet origin main
    git merge --ff-only --quiet origin/main || log "⚠️  main ist von origin/main abgewichen – baue lokalen Stand."
elif [ "$FORCE" = 0 ]; then
    log "Übersprungen: Branch '$BRANCH' oder ungesicherte Änderungen – Auto-Update fasst das nicht an."
    exit 0
fi

HEAD="$(git rev-parse --short HEAD)"
if [ "$FORCE" = 0 ] && [ -x "$APP/Contents/MacOS/myClaude" ] && [ "$(cat "$STAMP" 2>/dev/null)" = "$HEAD" ]; then
    exit 0   # schon aktuell
fi
log "Baue $HEAD …"

# Highlightr-Patch: Bundle unter Contents/Resources suchen (sonst fatalError im .app).
swift package resolve >/dev/null
HL="$REPO/.build/checkouts/Highlightr"
if ! grep -q "_bundleName" "$HL/src/classes/Highlightr.swift"; then
    git -C "$HL" apply "$SCRIPT_DIR/highlightr-bundle.patch"
    log "Highlightr-Patch angewendet."
fi

bash "$SCRIPT_DIR/gen-buildinfo.sh" >/dev/null
swift build -c release 2>&1 | tail -3
BIN="$(swift build -c release --show-bin-path)"
# BuildInfo.swift ist versioniert – zurücksetzen, damit der nächste Pull nicht blockiert.
[ -z "$DIRTY" ] && git checkout -- "$BUILDINFO"

# App-Paket frisch zusammensetzen – alles unter Contents/, sonst kann codesign nicht versiegeln.
STAGE="$(mktemp -d)/myClaude.app"
mkdir -p "$STAGE/Contents/MacOS" "$STAGE/Contents/Resources"
cp "$BIN/myClaude" "$STAGE/Contents/MacOS/myClaude"
cp "$SCRIPT_DIR/Info.plist" "$STAGE/Contents/Info.plist"
cp -R "$BIN/Highlightr_Highlightr.bundle" "$BIN/SKUMenuBar_myClaude.bundle" "$STAGE/Contents/Resources/"
ICONSET="$(dirname "$STAGE")/AppIcon.iconset"; mkdir -p "$ICONSET"
SRC_ICON="$REPO/Sources/SKUMenuBar/Assets.xcassets/AppIcon.appiconset/AppIcon_1024x1024.png"
for s in 16 32 128 256 512; do
    sips -z $s $s "$SRC_ICON" --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
    sips -z $((s*2)) $((s*2)) "$SRC_ICON" --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$STAGE/Contents/Resources/AppIcon.icns"
xattr -cr "$STAGE"
codesign --force --deep --sign - "$STAGE"
codesign --verify --deep --strict "$STAGE"

# Laufende App beenden (erst höflich, dann hart – Zombies überleben sonst SIGTERM).
osascript -e 'tell application id "com.sku.menubar.myClaude" to quit' >/dev/null 2>&1 || true
sleep 2
pkill -9 -f "$APP/Contents/MacOS/myClaude" 2>/dev/null || true
sleep 0.5

mkdir -p "$HOME/Applications"
rm -rf "$APP.old"; [ -d "$APP" ] && mv "$APP" "$APP.old"
mv "$STAGE" "$APP"
rm -rf "$APP.old" "$(dirname "$STAGE")"
echo "$HEAD" > "$STAMP"
open "$APP"
log "✅ myClaude $HEAD installiert."
