#!/usr/bin/env bash
# Injiziert die verbindliche Pflicht-Arbeitsweise ("Grill-Protokoll") in alle Worker-Agent-Definitionen.
#
# Jeder Worker-Agent startet damit JEDE Aufgabe automatisch:
#   1. grill-me Skill (relentless Ein-Frage-Interview bis geteiltes Verständnis)
#   2. detaillierte Analyse
#   3. bei Bedarf auf geeignete Agenten aufteilen
#   4. Ergebnis unabhängig verifizieren lassen
#   5. Erkenntnisse/Empfehlungen ausgeben
#   6. auf das Go des Nutzers warten, bevor umgesetzt wird
#
# Warum in die .md und nicht nur app-seitig? Native Sub-Agenten (Agent-/Task-Tool) baut die
# Claude-CLI direkt aus diesen .md — ein app-seitiger Block erreicht sie strukturell NIE.
#
# Idempotent (BEGIN/END-Marker): ein vorhandener Block wird ersetzt, nicht dupliziert. Beliebig
# oft erneut ausführbar (auch für künftig neu angelegte / neu regenerierte Agents). Kein Drift.
#
# Personas (category: persona) werden übersprungen: sie SIND der interviewte Kunde, nicht der
# Interviewer — grillen bräche die naive Kundenperspektive.
#
# Usage: bash tools/apply-grill-protocol.sh [agent-dir]
set -euo pipefail

AGENT_DIR="${1:-$HOME/.claude/agents}"
BEGIN_MARK="<!-- BEGIN auto:grill-protokoll -->"
END_MARK="<!-- END auto:grill-protokoll -->"

read -r -d '' BLOCK <<'EOF' || true
<!-- BEGIN auto:grill-protokoll -->
## Pflicht-Arbeitsweise bei JEDER Aufgabe (verbindlich)

Diese Regel hat Vorrang vor allen Format-, Methodik- und Struktur-Hinweisen weiter oben. Sie läuft automatisch, ohne dass der Nutzer sie anfordert.

1. **Starte immer** mit dem Skill `~/.claude/skills/grill-me/SKILL.md` — ein relentless Ein-Frage-nach-der-anderen-Interview, bis ein geteiltes Verständnis erreicht ist. Fakten selbst im Umfeld (Dateien, Tools, Code) nachschlagen; nur echte Entscheidungen dem Nutzer vorlegen — je eine Frage mit deiner Empfehlung, dann auf die Antwort warten.
2. **Führe eine detaillierte Analyse durch.**
3. **Teile deine Aufgaben bei Bedarf auf geeignete Agenten auf.**
4. **Lasse das Ergebnis unabhängig verifizieren.**
5. **Gib deine Erkenntnisse/Empfehlungen hier aus** (verdichtet, gemäß Antwort-Stil).
6. **Warte auf mein Go**, bevor du umsetzt.
<!-- END auto:grill-protokoll -->
EOF

changed=0; skipped=0; personas=0

shopt -s nullglob
for file in "$AGENT_DIR"/*.md; do
    # Personas anhand der Frontmatter erkennen und auslassen
    category="$(awk '/^---/{n++; next} n==1 && /^category:/{print $2; exit}' "$file")"
    if [ "$category" = "persona" ]; then
        printf '  skip (persona)  %s\n' "$(basename "$file")"
        personas=$((personas + 1))
        continue
    fi

    before="$(cat "$file")"

    # Vorhandenen Block entfernen (inkl. Marker), damit ein Re-Run nicht dupliziert
    stripped="$(awk -v b="$BEGIN_MARK" -v e="$END_MARK" '
        index($0, b) { skip = 1 }
        !skip        { print }
        index($0, e) { skip = 0 }
    ' "$file")"

    # Nachlaufende Leerzeilen kappen, dann Block frisch anhängen
    stripped="${stripped%"${stripped##*[![:space:]]}"}"
    printf '%s\n\n%s\n' "$stripped" "$BLOCK" > "$file"

    if [ "$before" = "$(cat "$file")" ]; then
        printf '  unchanged       %s\n' "$(basename "$file")"
        skipped=$((skipped + 1))
    else
        printf '  ✅ updated      %s\n' "$(basename "$file")"
        changed=$((changed + 1))
    fi
done

printf '\nFertig: %d aktualisiert, %d unverändert, %d Personas übersprungen.\n' \
    "$changed" "$skipped" "$personas"
