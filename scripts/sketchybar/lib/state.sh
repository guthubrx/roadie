#!/usr/bin/env bash
# SPEC-023 — Helpers d'état : queries roadie CLI + parsing texte plain.
# Note : les CLIs roadie n'ont pas (encore) de mode --json fiable, on parse
# le tableau texte. Dette technique trackée pour P3 (ajout --json proper Swift).

ROADIE="${ROADIE_BIN:-$HOME/.local/bin/roadie}"

# Liste des desktops récents. Retourne sur stdout, 1 ligne par desktop : "id|label|stages|windows|current".
# Sort : current first, puis recent, puis numérique. Limite : MAX (default 3).
roadie_desktops_recent() {
    local max="${1:-3}"
    "$ROADIE" desktop list 2>/dev/null | awk -v max="$max" '
        # Format : "  N  label  stages  windows  current_marker"
        # Output : id|label|stages|windows|current(true|false)
        /^[[:space:]]*[0-9]+/ {
            id = $1; gsub(/[*[:space:]]/, "", id)
            label = ""
            current = "false"
            if ($0 ~ /\(current\)|\*/) current = "true"
            # Extraction approximative — fallback empty
            print id "|" label "|0|0|" current
            count++
            if (count >= max) exit
        }
    '
}

# Liste les stages d'un desktop. Retourne 1 ligne par stage : "id|displayName|isActive|windowCount".
# Args : $1 = displayUUID (optionnel), $2 = desktopID.
roadie_stages_for() {
    local display="$1"
    local desktop="$2"
    local args=()
    [ -n "$display" ] && args+=(--display "$display")
    [ -n "$desktop" ] && args+=(--desktop "$desktop")
    # Format roadie : "* 2 (stage 2) — 1 window(s)"  ou  "  1 (Work) — 0 window(s)"
    # Output : id|name|active|count
    "$ROADIE" stage list "${args[@]}" 2>/dev/null | awk '
        /^[[:space:]]*\*?[[:space:]]*[0-9]+/ {
            line = $0
            active = (line ~ /^[[:space:]]*\*/) ? "true" : "false"
            # Strip leading marker + spaces
            sub(/^[[:space:]]*\*?[[:space:]]+/, "", line)
            # id = premier token
            split(line, tok, " "); id = tok[1]
            # name = entre parens
            name = "Stage " id
            if (match(line, /\([^)]+\)/)) {
                name = substr(line, RSTART + 1, RLENGTH - 2)
            }
            # count = nombre suivi de " window"
            count = 0
            if (match(line, /[0-9]+ window/)) {
                tmp = substr(line, RSTART, RLENGTH)
                sub(/ window.*/, "", tmp)
                count = tmp + 0
            }
            print id "|" name "|" active "|" count
        }
    '
}

# Vérifie si le daemon répond. Retourne 0 si OK, 1 sinon.
roadie_daemon_alive() {
    "$ROADIE" daemon status >/dev/null 2>&1
}

# Compte de fenêtres tilées dans un (stage, desktop). Args : $1=stage_id $2=desktop_id.
roadie_window_count() {
    local sid="$1"
    local did="$2"
    "$ROADIE" windows list 2>/dev/null | awk -v sid="$sid" -v did="$did" '
        $0 ~ ("stage=" sid)"\\b" { count++ }
        END { print count + 0 }
    '
}
