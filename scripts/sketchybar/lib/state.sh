#!/usr/bin/env bash
# SPEC-023 — Helpers d'état : queries roadie CLI + parsing texte plain.
# Note : les CLIs roadie n'ont pas (encore) de mode --json fiable, on parse
# le tableau texte. Dette technique trackée pour P3 (ajout --json proper Swift).

ROADIE="${ROADIE_BIN:-$HOME/.local/bin/roadie}"

# Liste des desktops récents. Retourne sur stdout, 1 ligne par desktop : "id|label|stages|windows|current".
# Sort : current first, puis recent, puis numérique. Limite : MAX (default 3).
roadie_desktops_recent() {
    local max="${1:-3}"
    # SPEC-023 — extraction du label : `roadie desktop list` output approximatif :
    # "  N: label" ou "* N: label" ou simplement "  N" (label vide). Fix audit-F3 :
    # capture le label après le ':' s'il existe, sinon laisse vide (le caller
    # fallback sur "Bureau N" via `[ -z "$label" ] && label="Bureau $did"`).
    # Format `roadie desktop list` (table colonnes) :
    # "ID   LABEL     CURRENT  RECENT  WINDOWS  STAGES"
    # "1    (none)    *                1        2"
    # "2    Work                       0        1"
    "$ROADIE" desktop list 2>/dev/null | awk -v max="$max" '
        # Skip header (commence par "ID")
        /^ID[[:space:]]+LABEL/ { next }
        # Match data rows (ligne commence par un nombre)
        /^[[:space:]]*[0-9]+/ {
            id = $1
            label = $2
            # Normaliser label "(none)" en chaîne vide pour fallback "Bureau N"
            if (label == "(none)") label = ""
            # CURRENT = colonne 3 si marker, sinon shift les autres colonnes.
            # Heuristique : si la 3e colonne est "*", current=true.
            current = "false"
            if ($3 == "*") current = "true"
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

# SPEC-023 — `roadie_window_count` retiré (audit-F2) : code mort, pattern awk
# bugué (`\b` non-standard, matchait stage=10/11 quand sid=1). Le panneau utilise
# directement `wcount` retourné par `roadie_stages_for` (parse "N window(s)").
# Si un futur call-site a besoin de cette fonction, la réimplémenter avec un
# pattern exact : `$0 ~ "[[:space:]]stage=" sid "($|[[:space:]])"`.
