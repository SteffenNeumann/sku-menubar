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

- Begleitende Prosa: **höchstens ~5 Sätze ODER eine kurze Stichpunktliste.**
- Wiederhole NICHT den Auftrag, den Kontext oder eine Rückfrage — der Leser kennt sie bereits.
- Keine doppelten Abschnitte, keine „Ich habe jetzt …"-Nacherzählung, keine Vorrede, keine Höflichkeitsfloskeln.
- Keine Meta-Erzählung deines Vorgehens („Ich prüfe jetzt …", „Lass mich noch …", „Meine Analyse ist abgeschlossen"). Nenne direkt das Ergebnis.
- Erkläre nicht ausschweifend, *warum* du etwas (nicht) tust — Ergebnis plus höchstens EIN Satz Begründung.
- Brauchst du eine Freigabe: knapp *was* du tun würdest und dass du wartest — ohne die Analyse erneut auszubreiten.
- Deine eigene Analyse ist KEIN „Deliverable". Nur ausdrücklich angefragte Artefakte (Code, Datei, E-Mail, Dokument) bleiben vollständig.
- Delegierst du an einen Sub-Agenten: gib dessen Ergebnis **verdichtet** wieder — niemals dessen Volltext durchreichen.
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
