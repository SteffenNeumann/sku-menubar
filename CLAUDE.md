# myClaude – Projekt-Regeln für Claude Code

## ⚠️ WICHTIGSTE REGEL: Kein Worktree-Modus

**Niemals** `isolation: "worktree"` beim Agent-Tool verwenden.  
Alle Änderungen direkt auf dem aktuellen Branch (normalerweise `main`) arbeiten.

**Warum:** Worktrees divergieren von `main` und verlieren neuere Commits. Das führt zu
veralteten Builds ohne Fehlermeldung — ein nicht sichtbares Versionierungs-Problem.

### Wenn die Session selbst in einem Worktree läuft

Erkennbar am System-Prompt: `You are operating in a git worktree.`  
Das echte Repo (main) liegt immer unter: `/Users/steffen/Documents/GitHub/sku-menubar/`

**Vorgehen:**
1. Änderungen im Worktree normal vornehmen und committen
2. Dateien per `cp` manuell ins echte Repo kopieren:
   ```bash
   cp Sources/SKUMenuBar/GeänderteDatei.swift /Users/steffen/Documents/GitHub/sku-menubar/Sources/SKUMenuBar/
   ```
3. Im echten Repo committen und deployen — **niemals vom Worktree-Pfad aus bauen**
4. Worktree danach aufräumen: `git worktree remove --force <pfad>`

---

## Deploy-Workflow (5 Schritte — immer alle 5)

```bash
# 1. Vor dem Deploy: Git-Stand prüfen
git status
git log --oneline -5

# 2. App beenden
pkill -f myClaude 2>/dev/null; sleep 0.3

# 3. BuildInfo aktualisieren (SHA + Timestamp in der Sidebar)
bash tools/gen-buildinfo.sh

# 4. Release-Build (aus dem Projekt-Root)
swift build -c release

# 5. Binary kopieren + App starten
cp .build/arm64-apple-macosx/release/myClaude ~/Applications/myClaude.app/Contents/MacOS/myClaude
open ~/Applications/myClaude.app

# 6. Gitstamp aktualisieren (Timestamp in der Sidebar)
printf "%s\n%s\n" "$(git rev-parse HEAD)" "$(date)" > gitstamp
```

**Schritte 3 und 6 niemals weglassen** — BuildInfo.swift muss vor dem Build generiert sein, damit SHA und Datum korrekt in die App kompiliert werden.

---

## Git-Regeln

- Immer auf `main` arbeiten — kein separater Feature-Branch nötig
- Vor dem ersten Build in einer Session: `git log --oneline -3` prüfen ob der Stand aktuell ist
- Wenn ein Worktree existiert: Änderungen per `git cherry-pick` zurück auf `main` holen, dann Worktree löschen

---

## Projekt-Übersicht

- **App-Name**: myClaude (früher SKUMenuBar)
- **Sprache**: Swift / SwiftUI (macOS)
- **Build-System**: Swift Package Manager
- **Binary-Ziel**: `~/Applications/myClaude.app/Contents/MacOS/myClaude`
- **Haupt-Source**: `Sources/SKUMenuBar/`

## Wichtige Dateien

| Datei | Inhalt |
|-------|--------|
| `ChatView.swift` | Chat-UI, File-Panel, MCP-Picker, Input-Bar |
| `AppState.swift` | Globaler State, Settings, History-Service |
| `ChatHistoryService.swift` | Verlauf laden, File-Watcher |
| `SidebarView.swift` | Letzte Projekte, Navigation |
| `AgentsView.swift` | Agent-Fleet, Personas, Email-Learning |
| `MCPView.swift` | MCP Server Management |
| `ThemeManager.swift` | Themes, Farben |

---

## Bekannte Konventionen

- Persistente Views (mit lokalem State) per `opacity`/`allowsHitTesting` im ZStack halten, nicht per `if/else` neu erstellen
- File-Watcher beobachtet `~/.claude/` (Eltern-Verzeichnis), nicht `history.jsonl` direkt (atomische Schreibvorgänge)
- Claude CLI immer via stdin pipen — nie `--print` + `--add-dir` kombinieren
