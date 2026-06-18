# myClaude

Ein natives **macOS-AI-Command-Center** (SwiftUI). myClaude bündelt die **Claude CLI** und mehrere
Integrationen — Multi-Agent-Orchestrierung, Linear, MCP-Server, Code-Review, Datei-Explorer,
Verlauf, Zeiterfassung (TMetric) und Mail-Automatisierung — in einer Sektions-/Tab-Oberfläche.

> Früherer Name: **SKUMenuBar**. Eine ausführliche Architektur-Übersicht steht in
> [`PROJECT_OVERVIEW.md`](PROJECT_OVERVIEW.md) (Single Point of Truth); verbindliche Arbeits-/
> Deploy-Regeln in [`CLAUDE.md`](CLAUDE.md).

## Features

- **Chat mit der Claude CLI** — Multi-Tab, pro Tab eigene Session, Datei-Kontext, Bild-Anhänge
- **Multi-Agent-Orchestrator** — verteilt komplexe Aufgaben auf spezialisierte Worker-Agents
  (Routing → Domain-Analyse → Master-Plan → Agent-Ausführung → Synthese) mit Plan-Freigabe
- **Agent-Fleet** — eigene Worker-Agents/Personas mit Persistent-Memory, Learning-Log und Skills
- **MCP-Server-Verwaltung** — lokale und Cloud-Server, Health-Checks, Per-Agent-Scoping
- **Linear-Integration** — Issues, Projekte, Sub-Tasks (3-Spalten-Ansicht)
- **Code Review** — Datei-Picker + Review-Config + Source-Viewer + Output
- **Files / Verlauf / Notizen & Aufgaben / Dashboard** — Datei-Explorer, Session-History,
  Token-Verbrauch-Kacheln
- **21 Themes**, Glassmorphism-UI, JetBrains-Mono-Schrift

## Voraussetzungen

- macOS 13 (Ventura) oder neuer
- Swift 6 Toolchain / Xcode Command Line Tools
- Installierte **Claude CLI** (`claude` im PATH)
- Optional: Tokens/Keys für Integrationen (Linear, TMetric, GitHub/Copilot-Modelle) — Credentials
  je Projekt in `zugang.md`

## Build & Deploy

```bash
git clone https://github.com/SteffenNeumann/sku-menubar.git
cd sku-menubar

bash tools/gen-buildinfo.sh          # BuildInfo.swift VOR dem Build generieren
swift build -c release               # NICHT --target myClaude (kompiliert nur, linkt nicht)

cp .build/arm64-apple-macosx/release/myClaude ~/Applications/myClaude.app/Contents/MacOS/myClaude
codesign --force --deep --sign - ~/Applications/myClaude.app   # macOS 26: Pflicht (sonst SIGKILL)
open ~/Applications/myClaude.app
```

Den vollständigen 6-Schritte-Deploy-Workflow inkl. Pflicht-Abschluss siehe [`CLAUDE.md`](CLAUDE.md).

## Tests

```bash
swift test        # u.a. OrchestratorLogicTests (Plan-Parsing, Agent-Resolve, Routing)
```

## Projektstruktur

- `Sources/SKUMenuBar/` — App-Quellcode (Executable-Target `myClaude`)
- `Tests/myClaudeTests/` — Unit-Tests (`myClaudeTests`)
- `PROJECT_OVERVIEW.md` — Architektur, Modul-Karte, Subsysteme, Konventionen
- `CLAUDE.md` — verbindliche Arbeits- und Deploy-Regeln
