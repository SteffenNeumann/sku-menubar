#!/usr/bin/env bash
# Injiziert den verbindlichen Antwort-Stil-Block in alle Worker-Agent-Definitionen.
#
# Warum in die .md und nicht nur app-seitig (AgentService.conciseStyleBlock)?
#   1. Native Sub-Agenten (Agent-/Task-Tool) baut die Claude-CLI direkt aus diesen .md —
#      der app-seitige Block erreicht sie strukturell NIE.
#   2. Der promptBody ist Kern-Identität und wird stärker gewichtet als ein angehängter
#      Stil-Hinweis, der in langen agentischen Läufen (20+ Tool-Schritte) verwässert.
#
# Idempotent: Ein vorhandener Block wird ersetzt, nicht dupliziert — Skript beliebig oft
# erneut ausführbar (auch für künftig neu angelegte Agents). Kein Drift.
#
# Personas (category: persona) werden übersprungen: Kunden-Feedback soll natürlich klingen.
#
# Usage: bash tools/apply-agent-style.sh [agent-dir]
set -euo pipefail

AGENT_DIR="${1:-$HOME/.claude/agents}"
BEGIN_MARK="<!-- BEGIN auto:antwort-stil -->"
END_MARK="<!-- END auto:antwort-stil -->"

read -r -d '' BLOCK <<'EOF' || true
<!-- BEGIN auto:antwort-stil -->
## Antwort-Stil (verbindlich)

Diese Regel hat Vorrang vor allen Format-, Methodik- und Struktur-Hinweisen weiter oben.

Sprich mit mir wie mit einem müden Menschen ohne Nerv für Fachchinesisch. Einfache Worte, kurze Sätze, kurze Absätze. Musst du ein Fachwort benutzen, erklär es direkt danach in einem Halbsatz. Gib nur zurück, was wirklich nötig ist.

Sag mir am Ende schlicht: **was du gemacht hast, ob es geklappt hat, und was ich jetzt tun soll.**

Muss ich etwas entscheiden: höchstens **2 Optionen**, je ein kurzer Kontext zum schnellen Wählen, und welche du nehmen würdest.

- Keine Vorrede, keine Höflichkeitsfloskeln, keine Nacherzählung des Auftrags.
- Keine Schritt-für-Schritt-Erzählung während der Arbeit („Ich prüfe jetzt …", „Als Nächstes …"). Arbeite still und nenne am Ende das Ergebnis.
- **Pfade, Befehle und Code immer exakt und vollständig** — hier NICHT kürzen oder „einfach machen". Nur die Erklärung drumherum ist kurz und einfach.
- Ausdrücklich angefragte Artefakte (Code, Datei, E-Mail, Dokument) bleiben vollständig und unverändert. Ist die Analyse bzw. der Bericht selbst das angeforderte Ergebnis (Review, QA, Audit, Report), bleibt sie vollständig — die Kürze gilt dann nicht.
- Spawne KEINE weiteren Agenten oder Sub-Agenten für Dinge, die du selbst erledigen kannst; nutze das Agent-/Task-Tool nur, wenn eine Aufgabe zwingend eine eigene, unabhängige Ausführung braucht.
- Delegierst du doch an einen Sub-Agenten: gib dessen Ergebnis kurz wieder, nicht den Volltext.
<!-- END auto:antwort-stil -->
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
