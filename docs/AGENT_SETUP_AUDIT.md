# Agent-Setup Audit (04.09.2026)

**Status: analysiert, NICHT umgesetzt.** Vollständige Doku für eine spätere Umsetzungs-Session.
Steffen wollte zunächst nur analysieren ("warte auf mein go"). Orchestrator-Pfad bewusst
ausgeklammert (User-Wunsch mitten in der Analyse).

Alle Zahlen aus lokalen Dateien/Transcripts gemessen und unabhängig von einem
qa-test-engineer-Subagent gegengeprüft: 100 eigene Messungen, 27 von 29 Punkten exakt
bestätigt, 2 mit kleiner Zähl-Drift durch neue Sessions zwischen den beiden Läufen — keine
Kernaussage widerlegt.

## Kostenbild (gemessen, seit 01.08.2026)

| Baustein | Takt | Kosten/Monat | Kernbefund |
|---|---|---|---|
| Researcher-Lauf | täglich 15:04, Ø 6 min, 66 Turns | ≈ $115 | Median 2 von 13 Agents bekommen pro Lauf ein Update |
| Dream (Memory-Verdichtung) | 11 Agents, jede Nacht ~22–00 Uhr | ≈ $70 | 7 von 11 Agents: 0 neue Log-Einträge seit Juli, trotzdem jede Nacht neu geschrieben |
| **Summe** | | **≈ $185/Monat** | größtenteils Harness-Overhead, nicht Inhalt |

Quellen: `~/.claude/agent-logs/researcher forweb and ui  design trends.json` (Lauf-Protokoll,
100 Einträge seit 14.06.), Transcripts `~/.claude/projects/*/*.jsonl` (Token-Zählung über
`message.usage`), Sonnet-Preise $3/$15/$0,30/$3,75 pro MTok für input/output/cache-read/cache-write.

## 1) Researcher — informiert er sich effektiv?

**Stärkster Teil des Setups.** Kuratierte Quellenliste je Domäne in
`~/.claude/agent-memory/researcher/MEMORY.md` (Positive Sources + Avoid-Liste mit
Paywall/403/404-Einträgen), 334 Zeilen Learning-Log mit konkreten Lehren (z. B. "WebFetch der
exakten Artikel-URL, nicht der Index-Seite vertrauen"). 73 % der 100 protokollierten Läufe
erfolgreich; 27 Fehlschläge fast ausschließlich Netzwerk (16×, davon 10× im Copilot-Fallback),
2× Turn-Limit 30, 2× Timeout 60 min. Median-Dauer 6 min, p90 10 min.

**Schwäche:** `## Recommendation Adoption` — 30 von 33 geprüften Reports enthalten die Sektion
"Adoption of earlier recommendations", Inhalt praktisch immer *unknown*/"no quotable evidence".
Kostet Schritt-1b-Turns, liefert keinen verwertbaren Rückkanal.

## 2) Weitergabe an die Agents — Kernproblem des Setups

Weitergabe = reines **Anhängen** an `## 🔬 Research Updates` in der jeweiligen `agents/<name>.md`.
Der Researcher-Prompt verbietet explizit das Löschen bestehender Sektionen ("NEVER delete any
existing sections — only add/replace Research Updates") — es gibt **keine Prune-Regel** für
diesen Block (nur für den MCP-Block: max. 4 Bullets; und für `shared/MEMORY.md`: 90 Tage).

Folge — der Block ist zur Hauptlast des System-Prompts geworden, bei **jedem** Aufruf:

| Agent | Research-Anteil am Gesamt-Prompt | Bullets | davon >30 Tage alt |
|---|---|---|---|
| security-auditor | 87–88 % (≈ 58 KB / 66,8 KB ≈ 14,5k Tokens) | 95–96 | ~90 % |
| devops-engineer | 78–79 % (≈ 34 KB ≈ 8,5k Tokens) | 69–70 | ~90 % |
| seo-specialist | 68 % | 30–31 | |
| code-reviewer | 65–66 % | 38–39 | |
| data-analyst | 64–65 % | 33–34 | |

Kein einziger Worker-Prompt enthält eine Anweisung, **wie** der Block zu nutzen ist — reine
Datenliste ohne Nutzungsregel (0 Treffer bei gezielter Suche über alle Worker-Dateien).

`shared/MEMORY.md` (wird laut `AgentService.swift:579` in **jeden** Agent-Preamble injiziert):
nur 2 Einträge, beide vom 04.08.2026, beide vom Researcher über sich selbst
(Tilde-Expansion-Falle, Read-before-Edit-Guard).

**Stichprobe (Verifizierer, unabhängig):** 3 zufällige CVE-Bullets aus security-auditor.md über
alle Transcripts seit 01.08. gesucht → **0 echte Nutzungen**; die einzigen Treffer waren die
Selbstmeldungen des Researchers beim Eintragen des Bullets.

**Doppelarbeit belegt:** frontend-webdesigner loggte den `inert`-statt-`aria-hidden`-Fix am
31.08. 19:45 Uhr selbst in sein eigenes `learning_log.txt`. Der Researcher lieferte denselben
Fix am 01.09. als "direct answer to the Aug 31 pain point" — der Pain-Point-Scanner (Step 1b)
erkennt nicht, dass der geloggte Eintrag den Fix bereits enthält.

## 3) Setzen die Agents das Wissen um?

Nicht direkt messbar, aber Indizien sind eindeutig negativ. Learning-Logs von 6 Workern sind
faktisch tot: devops-engineer 1 Zeile (Juli), report-writer 1 (Juni), security-auditor 3 (Juni),
data-analyst 2 (Juli), seo-specialist 0 seit August. Aktiv sind nur backend-developer (16
Einträge Aug+Sep), code-reviewer (12), frontend-webdesigner (3).

Nutzung als Sub-Agent über das Agent-Tool seit 01.08.: code-reviewer ~47, general-purpose 46,
Explore ~35, frontend-webdesigner ~24, qa-test-engineer ~21, project-manager 5, backend 2,
researcher 2 — **devops-engineer, security-auditor, report-writer, excel-vba-developer: 0**.

Direkte Starts mit Pflicht-Skill-Hinweis (seit 28.08., = direkt in myClaude als dieser Agent
gestartet): backend-developer ~30–33, frontend-webdesigner ~14–16, code-reviewer ~4–5 Sessions.

→ **Für mindestens 5 Agents (devops, security-auditor, report-writer, excel-vba, data-analyst)
laufen Researcher UND Dream täglich für nachweisbar null Nutzung im Beobachtungszeitraum.**

## 3b) Dream — funktioniert technisch, wirtschaftlich fragwürdig

333 Läufe seit 01.08. (30 Nächte × 11,1 Agents Ø), keine technischen Fehler, alle 11
`MEMORY.md` werden nächtlich komplett neu geschrieben (Zeitfenster ~00:01–00:03 Uhr).

Code geprüft (`AgentService.swift`, `dreamAgent()` ~Z.480–546, `checkSchedules()` ~Z.854–873):
**kein Skip vorhanden**, wenn `learning_log.txt` seit dem letzten Dream unverändert ist —
`isDue()` prüft ausschließlich den Zeitstempel, nie den Inhalt. `learning_log.txt` wird nie
gekürzt/archiviert → Dream-Input wächst mit der Zeit (backend-developer Ø 84k Input-Tokens/Nacht
bei 115 Log-Zeilen). Minimal-Kosten fallen auch bei praktisch leerer Memory an
(seo-specialist: `MEMORY.md` 123 Bytes, trotzdem Ø 32.795 Input-Tokens/Nacht, Output nur 44–65
Tokens — der Input ist reiner Harness-Overhead).

## 3c) Trigger (Auto-Agent per Stichwort) — echter Bug gefunden

`autoTriggerAgent()` (ChatView.swift:388) nimmt den ersten Agenten aus
`state.agentService.agents`, dessen Trigger matcht. Sortierung (`AgentService.swift:75`):
**alphabetisch nach `name:`-Feld** (nicht Dateiname). Matching
(`OrchestratorLogic.inputMatchesTrigger`): reiner **Substring**, case-insensitiv, plus
bidirektionales Präfix-Matching — **keine Wortgrenze**.

Leere/fehlende `triggers:` im Frontmatter werden automatisch durch
`AgentDefinition.extractKeywords(limit: 6)` aus dem Fließtext gefüllt (erste 6 Wörter ≥4
Zeichen, ohne Stopwords) — das trifft die drei Kunden-Personas und den Researcher:

- **Testkunde**: Trigger `Inhaber, Lenen, Softwarefirma, Bist, Technisch, Sehr` — UND
  `name: ""` (leerer String) im Frontmatter. Ein leerer String sortiert alphabetisch ganz
  vorne → Testkunde wird bei **jeder** Chat-Nachricht als allererstes gegen seine Trigger
  geprüft, noch vor allen echten Worker-Agents.
- **Karim**: Trigger u. a. `Mitte, Kaum, Digitales`
- **researcher forweb and ui design trends**: Trigger `Search, Trends, Accessable, Aother,
  Researcher, Design`

Verifizierer-Simulation (unabhängig, mit dem echten Matching-Code): Nachricht
*"Das ist kaum ein Problem, der Test läuft"* triggert **Karim (Persona)**, nicht
qa-test-engineer — weil `Kaum` als Substring in "kaum" matcht und Karim alphabetisch vor
qa-test-engineer liegt. Jedes Vorkommen von "sehr" oder "bist du" im Chat kann analog
Testkunde auslösen.

## 4) Skills — funktioniert seit dem 29.08.-Fix gut

225 Skill-Aufrufe seit 01.08. (Feld-Basisrate vorher: 4 von 586, siehe
`~/.claude/projects/-Users-steffen-Documents-GitHub-sku-menubar/memory/project_skill_keyword_activation.md`).
Pflicht-Skill-Mechanismus (siehe
`~/.claude/projects/-Users-steffen-Documents-GitHub-sku-menubar/memory/project_agent_mandatory_skills.md`):
57 Hinweise in 46 Sessions, **98 %** davon mit mindestens einem folgenden Skill-Aufruf.

Offener Nebenbefund: Der ⭐-Block in `researcher forweb and ui  design trends.md` ist
fehlerhaft (Fließtext statt Skill-Namen in Backticks) — nicht kritisch, weil der
Installed-Filter den Müll herausfiltert. Würde `mainSkills()` (SkillKeywords.swift) direkt
darauf laufen, würde der Backtick-Parser Fragmente wie `## Active Skills` als vermeintliche
Skill-Namen extrahieren.

## Priorisierte Empfehlungen für die Umsetzung (noch KEIN Go)

Reihenfolge = Nutzen/Aufwand, vom Verifizierer nicht widersprochen:

1. **Trigger-Bug beheben** (~1 h, kein Kostenhebel, aber Fehlrouting):
   - Personas (Karim, Susanne, Testkunde) und den Researcher vom Auto-Trigger-Pfad ausnehmen
     (z. B. `category:persona`/`isMaintainer`-Check in `autoTriggerAgent()`)
   - `Testkunde.md`: `name: ""` reparieren (leerer Name sortiert fälschlich zuerst)
   - Wortgrenzen-Matching statt Substring — Vorbild existiert bereits: `mcpKeywordMatches()`
     in ChatView.swift hat schon strenges Wortgrenzen-Matching für MCP-Trigger

2. **Dream-Skip einbauen** (~1 h, spart ≈ $50/Monat):
   - Nur träumen, wenn `learning_log.txt`-mtime > `last_dream.txt`-Datum
   - Danach verarbeitete Log-Zeilen archivieren/kürzen, damit der Input nicht unbegrenzt wächst

3. **Research-Updates deckeln** (~1 h, spart 5–14k Tokens pro Agent-Aufruf bei den größten
   Dateien):
   - Regel im Researcher-Prompt: max. ~12 Bullets / 45 Tage in `## 🔬 Research Updates`,
     ältere Einträge nach `agent-memory/<agent>/research-archive.md` auslagern statt im
     Prompt zu behalten
   - Ein Satz im Worker-Prompt ergänzen, der sagt, wie/wann der Block zu nutzen ist

4. **Researcher-Takt reduzieren** (~30 min, spart ≈ $70/Monat):
   - 2×/Woche (z. B. Mo/Do) statt täglich
   - Nur Agents recherchieren, die in den letzten 14 Tagen echte Log-Aktivität hatten
     (deckt sich mit dem Befund unter Punkt 3: 5 Agents mit 0 Nutzung)

5. **Adoption-Sektion ersetzen**:
   - `## Recommendation Adoption` streichen (liefert seit Monaten nur "unknown")
   - Stattdessen eine echte Messung wie die Stichprobe oben: Kernbegriff des Research-Bullets
     (CVE-Nummer, API-Name) gegen Assistant-Antworten in Transcripts grep(1)en
   - Pain-Point-Scan (Step 1b) soll erst prüfen, ob der Log-Eintrag den Fix schon selbst
     enthält, bevor recherchiert wird (verhindert Doppelarbeit wie beim `inert`-Fall)

6. **Klein/optional:**
   - Researcher-⭐-Block reparieren (Fließtext → echte Skill-Namen in Backticks)
   - Copilot-Fallback-Netzwerkfehler beobachten (10 von 27 Researcher-Fehlschlägen laufen
     darüber)

Steffens Tendenz aus dem Gespräch: Pakete 1–3 zuerst (≈ 3 h, ≈ −$50/Monat, behebt
Fehlrouting + schlankere Prompts), 4–5 danach separat freigeben lassen, weil Punkt 4 die
Aktualität des Researchers sichtbar reduziert — bewusster Trade-off, kein Automatismus.

## Methodik-Hinweis für die Umsetzungs-Session

Alle Zahlen sind Stichtags-Messungen vom 04.09.2026 aus:
- `~/.claude/agents/*.md` (Agent-Definitionen, Frontmatter, `## 🔬 Research Updates`-Blöcke)
- `~/.claude/agent-memory/<agent>/{MEMORY.md,learning_log.txt}` (Worker-Memory)
- `~/.claude/agent-memory/researcher/{MEMORY.md,learning_log.txt,*_daily_report.txt}` (105
  Reports, 06.04.–04.09.)
- `~/.claude/agent-memory/shared/MEMORY.md` (cross-agent, nur Researcher schreibt)
- `~/.claude/agent-logs/researcher forweb and ui  design trends.json` (Lauf-Protokoll:
  startedAt/finishedAt/status/error, Apple-Epoch-Sekunden in älteren Einträgen, ISO-Strings
  in neueren — beim Nachmessen beide Formate behandeln)
- `~/.claude/projects/*/*.jsonl` (Transcripts; `type` user/assistant, `message.content`,
  `message.usage.{input_tokens,output_tokens,cache_read_input_tokens,cache_creation_input_tokens}`,
  `tool_use`-Blöcke mit `name`/`input`)
- App-Code: `Sources/SKUMenuBar/{AgentService.swift,ChatView.swift,CLIModels.swift,
  OrchestratorLogic.swift,SkillKeywords.swift}`

Vor jeder Umsetzung neu messen — das System ist lebend (Transcript-Zahlen zwischen den beiden
Läufen dieser Session schon leicht gedriftet, z. B. 697→689 Sessions).
