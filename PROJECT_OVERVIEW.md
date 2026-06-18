# myClaude — Projekt-Übersicht (Single Point of Truth)

> **Zweck:** Diese Datei ist die zentrale Wahrheitsquelle für Architektur, Aufbau und
> Konventionen des Projekts. Sie verweist auf die Detail-Dokumente, statt sie zu duplizieren.
> Bei Architektur-Änderungen **hier zuerst** aktualisieren.
>
> **Stand:** 2026-06-18 · Branch `main` · letzter relevanter Commit `6f06178`

## Dokument-Landkarte (wer ist wofür Wahrheit?)

| Datei | Inhalt / Autorität |
|-------|--------------------|
| **`PROJECT_OVERVIEW.md`** (diese Datei) | Architektur, Modul-Karte, Subsysteme, Konventionen |
| **`CLAUDE.md`** | **Verbindliche Arbeitsregeln**: Deploy-Workflow (6 Schritte), Worktree-Verbot, Git-/Abschluss-Pflichten. Bei Konflikt gewinnt CLAUDE.md |
| `~/.claude/projects/-Users-steffen-…-sku-menubar/memory/` | Tiefendokus pro Feature/Fix (Index: `MEMORY.md`). Point-in-time, vor Nutzung gegen Code prüfen |
| `README.md` | ⚠️ **VERALTET** — beschreibt die alte „SKU Budget"-Billing-App, nicht das heutige myClaude. Nicht als Quelle nutzen |
| `memory.md` (Repo-Root, klein geschrieben) | ⚠️ Alte, knappe Notiz — durch diese Übersicht abgelöst |

---

## Was ist myClaude?

Eine **native macOS-SwiftUI-App** (früher „SKUMenuBar") — ein **AI Command Center**, das die
**Claude CLI** (`claude`, via stdin gepiped) sowie diverse Integrationen (Linear, MCP-Server,
TMetric, GitHub/Copilot-Modelle, Mail.app) in einer Tab-/Sektions-Oberfläche bündelt. Kernstück
ist ein **Multi-Agent-Orchestrator**, der lange/komplexe Anfragen auf spezialisierte Worker-Agents
verteilt.

- **Sprache/Stack:** Swift / SwiftUI (macOS 13+), Swift Package Manager
- **Executable-Target:** `myClaude` · **Test-Target:** `myClaudeTests` (`Package.swift`)
- **Entry:** `App.swift` → `SKUMenuBarApp` (`WindowGroup`) → `ContentView` → `MainWindowView`
- **Repo (echtes main):** `/Users/steffen/Documents/GitHub/sku-menubar/`
- **Binary-Ziel:** `~/Applications/myClaude.app/Contents/MacOS/myClaude`

---

## Build & Deploy (Kurzfassung — Details + Pflichten in `CLAUDE.md`)

```bash
pkill -9 -f myClaude; sleep 0.3
bash tools/gen-buildinfo.sh                 # BuildInfo.swift VOR dem Build generieren
swift build -c release                      # NICHT --target myClaude (kompiliert nur, linkt nicht)
cp .build/arm64-apple-macosx/release/myClaude ~/Applications/myClaude.app/Contents/MacOS/myClaude
codesign --force --deep --sign - ~/Applications/myClaude.app   # macOS 26 Pflicht (sonst SIGKILL)
open ~/Applications/myClaude.app
printf "%s\n%s\n" "$(git rev-parse HEAD)" "$(date)" > gitstamp
```

Verifikation nach Deploy: Binary-`mtime` vorher/nachher prüfen + laufende Instanz (`ps`) — „App
hängt trotz Fix" ist oft eine veraltete Zombie-Instanz (überlebt `pkill` SIGTERM).

---

## Sektionen (UI-Navigation · `AppSection` in `CLIModels.swift`)

`Home` · `Dashboard` · `Chat` · `Verlauf` · `Agents` · `MCP Server` · `Code Review` · `Files` ·
`Notizen` · `Aufgaben` · `Linear` · `Einstellungen`

---

## Modul-Karte (Hauptdateien `Sources/SKUMenuBar/`)

| Datei | Verantwortung |
|-------|---------------|
| `App.swift` / `ContentView.swift` / `MainWindowView.swift` | App-Entry, Fenster, Sidebar + Detail-Split |
| `AppState.swift` | **Globaler State**, Settings, hält alle Services (`cliService`, `agentService`, `mcpService`, `historyService`, `linearService`, `emailPollingService`, …) |
| `ChatView.swift` (~8,6k Z., größte Datei) | Chat-UI, **Multi-Agent-Orchestrator**, File-Panel, MCP-Picker, Input-Bar, Permission-/Plan-Modus |
| `OrchestratorLogic.swift` | **Reine, testbare Orchestrator-Logik** (Parsing, Routing-Heuristik, `OrchestratorLimits`) — kein View-/State-Zugriff |
| `OrchestratorView.swift` / `ConvergenceView.swift` / `ConvergenceRunner.swift` | Manueller Orchestrator-/Co-Design-Loop-UI + Runner |
| `ClaudeCLIService.swift` | **Claude-CLI-Prozess-Wrapper** (`send()` baut Args, streamt `stream-json`), Fehler-/Stale-Session-Recovery |
| `AgentService.swift` | Worker-Agent-Fleet (Laden aus `~/.claude/agents/`), `fullSystemPrompt()`, Memory/Learning-Log, Skills |
| `CLIModels.swift` | Geteilte Modelle: `ChatMessage`, `StreamEvent`, `AppSection`, `ToolCall`, … |
| `AgentsView.swift` | Agent-Fleet-UI (Baseball-Cards), Personas, Editor, Skills, Email-Learning |
| `MCPView.swift` / `MCPService.swift` / `MCPClientService.swift` | MCP-Server-Verwaltung (lokal/cloud), Health-Checks |
| `LinearView.swift` / `LinearService.swift` | Linear-Integration (3-Spalten, GraphQL direkt — MCP-Delete kaputt) |
| `CodeReviewView.swift` | Datei-Picker + Review-Config + Source-Viewer + Output (3-Spalten) |
| `FileExplorerView.swift` | Datei-Baum, Sort/Group, Office-/HTML-Preview |
| `HistoryView.swift` / `ChatHistoryService.swift` | Verlauf laden, File-Watcher auf `~/.claude/` |
| `HomeView.swift` / `Dashboard*Card.swift` / `StatisticsView.swift` | Home/Dashboard-Kacheln (Token-Verbrauch, Sessions, Drilldown) |
| `NotesView.swift` | Notizen & Aufgaben (TaskLines-Editor) |
| `SettingsFormView.swift` / `Models.swift` (`GitHubSettings`) | Einstellungs-UI (Cluster) + persistierte Settings-Struktur |
| `ThemeManager.swift` | 21 Themes, `AppTheme` via `@Environment(\.appTheme)`, status-aware Farben |
| `GitHubModelsService.swift` | Copilot-/GitHub-Modelle als Fallback-Pfad |
| `TMetricService.swift` / `EmailPollingService.swift` / `CustomerInquiryWorkflow.swift` | Zeiterfassung, Mail-Polling → Triage → Linear-Workflow |
| `MarkdownTextView.swift` / `HighlightedCodeView.swift` | Markdown-/Code-Rendering (Highlightr), Font-Handling |

---

## Subsystem: Multi-Agent-Orchestrator (das komplexeste Stück)

**Zweck:** komplexe Anfragen auf bis zu 4 spezialisierte Worker-Agents verteilen, Ergebnisse
synthetisieren. Lebt in `ChatView.swift` (`SingleChatSessionView`); reine Logik in
`OrchestratorLogic.swift`.

**Ablauf (Auto-Orchestrierung):**
```
User-Nachricht
  → isComplexTask() (Wortzahl-Heuristik) + autoOrchestrationEnabled
  → selectRelevantAgents() [Haiku 4.5, OHNE MCP-Tools]   ← Routing
      ├ ≥2 Agents → Bestätigungs-Banner → startConfirmedOrchestration()
      └ 0–1 Agent → Einzel-Agent via performSend()
  → Phase 0  Domain-Analyse   [Haiku, 1 Bulk-Call, kein MCP]
  → Phase 1  Master-Plan JSON [Haiku, kein MCP] — One-Shot-Retry + result-Fallback
             parsePlanJSON → parseMasterPlan(Text) → parseOrchestratorPlan(Legacy) → Fallback
  → (manueller Modus: Plan-Freigabe-Banner ▶/✕)
  → Phase 2  Agents nacheinander [je eigener Prozess + Modell + per-Agent-MCP-Scoping + Idle-Watchdog]
  → Phase 3  Synthese [selectedModel] (nur bei >1 erfolgreichem Agent; sonst Solo-Output)
  → Follow-ups: classifyFollowUp → .chat (Direktantwort) / .fast / .full
```

**Wichtige Eigenheiten / Invarianten:**
- Jede Phase + jeder Agent = **eigener `claude`-Subprozess** (kein geteiltes Session-Sharing).
  Eine 3-Agenten-Runde ≈ 7 Prozess-Starts. Der erste Subprozess einer Session ist am anfälligsten
  (Cold-Start) → Phase 0/1 haben One-Shot-Retry + `result`-Event-Fallback.
- **Token-Disziplin:** Reasoning-Phasen (0/1/3) + Routing senden **keine** MCP-Tools (`noMCPJson` +
  `--strict-mcp-config` + `--tools ""`). „Leer = alle MCP" ist im Orchestrator unterbunden
  (→ `__none__`). Bilder nur in Phase 2. Kontext-Caps in `OrchestratorLimits`.
- **`OrchestratorLimits`** (zentral in `OrchestratorLogic.swift`): `maxAgents=4`,
  `defaultMaxTurns=20`, `minAgentTurns=20`, `historyWindow=6`, `foreignOutputCap=1500`,
  `zugangCap=4000`, `memoryCapOrchestrator=1500`, `defaultIdleTimeoutSec=120`.
- **`zugang.md`** im Projektverzeichnis = Credentials/Kontext; wird Agents injiziert (gekappt).
- **Bekannte strukturelle Schwäche (offen, F+G):** In-Flight-State (`orchestratorHistory`,
  `activePlan`, `pendingPhase2`, …) liegt nur im View-`@State`, nicht in `ChatTab` → kann bei
  Tab-Teardown verloren gehen. Stale-Session-Recovery fehlt in den Phasen-Calls (nur in
  `performSend`). Siehe Memory `project_orchestrator_open_FG`.

**Orchestrator-Historie (Memory-Tiefendokus):** `project_orchestrator_v1_v6_improvements` →
`hardening` → `token_optimization` → `smart_routing` → `plan_assignment_fix` →
`auto_orch_toggle_plan_mode` → `robustness_AE` (zuletzt) → `open_FG` (offen).

---

## Zentrale Konventionen & Stolpersteine

- **Kein Worktree-Modus** (`CLAUDE.md`): nie `isolation: "worktree"`; immer auf `main` arbeiten,
  immer aus dem echten Repo bauen — Worktrees divergieren und verlieren Commits unbemerkt.
- **Persistente Views** mit lokalem State per `opacity`/`allowsHitTesting` im ZStack halten
  (nicht per `if/else` neu erstellen) — sonst Verlust von `@State`/Auswahl.
- **`guard isActive`** in jedem `onChange` auf globalem `AppState` (feuert für ALLE Tabs).
- **File-Watcher** beobachtet `~/.claude/` (Eltern-Verzeichnis), nicht `history.jsonl` direkt
  (atomische Schreibvorgänge).
- **Claude CLI** immer via stdin pipen — nie `--print` + `--add-dir` kombinieren.
- **MCP/OAuth:** claude.ai-MCPs sind mit `--strict-mcp-config` inkompatibel; `buildMCPConfigJSON`
  gibt `(json, strict)` zurück. linear/make/figma **nie** lokal entfernen.
- **codesign nach jedem `cp`** (macOS 26 Pflicht). **`gen-buildinfo.sh` VOR dem Build.**
- **Themes:** nie `.green/.orange/.red` hardcodieren — `theme.statusGreen/Orange/Red` nutzen.
- **Performance (lange Chats):** Message-Liste auf max. 75 sichtbare gecappt, `VStack` statt
  `LazyVStack` in der Liste, `scrollToBottom` ohne Animation während Streaming, `FrozenSectionLayout`
  pro Tab. Hintergründe in Memory `feedback_app_hang_fixes` / `feedback_chat_hang_investigation`.
- **Nested `async func`** in einem `@MainActor`-Task-Closure muss selbst `@MainActor` sein, sonst
  „expression is async but not marked with await".

---

## Tests

`swift test` — u.a. `OrchestratorLogicTests` (Plan-Parsing, Agent-Resolve, Routing-Heuristik).
Aktuell **37 Tests grün**. Neue Orchestrator-Logik immer als reine Funktion in
`OrchestratorLogic.swift` + Test ergänzen.
