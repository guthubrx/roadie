#!/usr/bin/env bash
# SPEC-023 — Installation du plugin SketchyBar roadie.
# Symlinke les fichiers de scripts/sketchybar/{items,plugins,lib} vers
# ~/.config/sketchybar/sketchybar/{items,plugins,lib}.
# Backup les fichiers existants (suffix .bak.<timestamp>).
#
# Usage : ./scripts/sketchybar/install.sh [--dry-run] [--uninstall]

set -euo pipefail

DRY_RUN=0
UNINSTALL=0
for arg in "$@"; do
    case "$arg" in
        --dry-run) DRY_RUN=1 ;;
        --uninstall) UNINSTALL=1 ;;
        -h|--help) sed -n '2,8p' "$0" | sed 's/^# *//'; exit 0 ;;
    esac
done

REPO_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
SRC_DIR="$REPO_DIR/scripts/sketchybar"
DST_DIR="$HOME/.config/sketchybar/sketchybar"
SKETCHYBARRC="$HOME/.config/sketchybar/sketchybarrc"
TS="$(date +%s)"

# Pré-requis : check toutes les dépendances en un seul passage.
MISSING=()
check_dep() {
    local cmd="$1" hint="$2"
    if ! command -v "$cmd" >/dev/null; then
        MISSING+=("  - $cmd : $hint")
    fi
}
check_dep sketchybar         "brew install FelixKratz/formulae/sketchybar"
check_dep jq                 "brew install jq"
check_dep terminal-notifier  "brew install terminal-notifier (notification cliquable quand TCC drop)"
check_dep awk                "préinstallé sur macOS — anomalie si absent"
check_dep codesign           "préinstallé sur macOS via Xcode CLI tools"

if [ ${#MISSING[@]} -gt 0 ]; then
    echo "ERROR: dépendances manquantes :"
    printf '%s\n' "${MISSING[@]}"
    echo
    echo "Installe-les puis relance ce script."
    exit 1
fi
if [ ! -d "$DST_DIR" ]; then
    echo "ERROR: $DST_DIR n'existe pas. Démarre d'abord SketchyBar (sketchybar -d) ou crée le dir."
    exit 1
fi

run() {
    if [ "$DRY_RUN" = "1" ]; then
        echo "[dry-run] $*"
    else
        eval "$@"
    fi
}

uninstall_one() {
    local target="$1"
    if [ -L "$target" ]; then
        run "rm '$target'"
        echo "removed symlink $target"
        # Restore le .bak le plus récent si présent.
        local bak
        bak=$(ls -t "$target".bak.* 2>/dev/null | head -1)
        [ -n "$bak" ] && run "mv '$bak' '$target'" && echo "restored $bak → $target"
    fi
}

install_one() {
    local src="$1"
    local target="$2"
    if [ -L "$target" ]; then
        # Si le symlink pointe déjà vers la même cible, no-op.
        local current
        current=$(readlink "$target")
        if [ "$current" = "$src" ]; then
            echo "ok    $target → $src (already symlinked)"
            return
        fi
        run "rm '$target'"
    elif [ -e "$target" ]; then
        run "mv '$target' '$target.bak.$TS'"
        echo "backup $target → $target.bak.$TS"
    fi
    run "ln -s '$src' '$target'"
    echo "link  $target → $src"
}

# ----------------------------------------------------------------------------

if [ "$UNINSTALL" = "1" ]; then
    for f in items/roadie_panel.sh plugins/roadie_panel.sh plugins/roadie_event_bridge.sh \
             lib/colors.sh lib/state.sh; do
        uninstall_one "$DST_DIR/$f"
    done
    echo "uninstall done. Reload SketchyBar: sketchybar --reload"
    exit 0
fi

# Créer les dirs cibles si absents.
run "mkdir -p '$DST_DIR/items' '$DST_DIR/plugins' '$DST_DIR/lib'"

# Symlink chaque fichier.
for sub in items plugins lib; do
    [ -d "$SRC_DIR/$sub" ] || continue
    for src_file in "$SRC_DIR/$sub"/*.sh; do
        [ -f "$src_file" ] || continue
        name=$(basename "$src_file")
        install_one "$src_file" "$DST_DIR/$sub/$name"
        run "chmod +x '$src_file'"
    done
done

# Ajouter (idempotent) les 2 lignes au sketchybarrc.
if [ ! -f "$SKETCHYBARRC" ]; then
    echo "WARN: $SKETCHYBARRC absent. Le user doit l'éditer manuellement pour ajouter :"
    echo '    source "$ITEM_DIR/roadie_panel.sh"'
    echo '    "$PLUGIN_DIR/roadie_event_bridge.sh" &'
else
    # SPEC-023 — désactive l'ancienne ligne SPEC-011 (roadie_desktops.sh) si présente.
    # Elle crée des items roadie.1..10 qui entrent en conflit avec le nouveau panneau.
    # Suit le symlink éventuel (~/.config/sketchybar/sketchybarrc est souvent un lien).
    REAL_RC="$(readlink -f "$SKETCHYBARRC" 2>/dev/null || echo "$SKETCHYBARRC")"
    if grep -qE '^[[:space:]]*source.*roadie_desktops\.sh' "$REAL_RC"; then
        run "cp '$REAL_RC' '$REAL_RC.bak.$TS'"
        run "awk '/^[[:space:]]*source.*roadie_desktops\\.sh/ {print \"# SPEC-023 commented (conflicting): \" \$0; next} {print}' '$REAL_RC' > '$REAL_RC.tmp' && mv '$REAL_RC.tmp' '$REAL_RC'"
        echo "commented old roadie_desktops.sh line in $REAL_RC"
    fi
    if ! grep -q 'roadie_panel.sh' "$SKETCHYBARRC"; then
        run "echo '' >> '$SKETCHYBARRC'"
        run "echo '# SPEC-023 SketchyBar roadie panel' >> '$SKETCHYBARRC'"
        run "echo 'source \"\$ITEM_DIR/roadie_panel.sh\"' >> '$SKETCHYBARRC'"
        run "echo '\"\$PLUGIN_DIR/roadie_event_bridge.sh\" &' >> '$SKETCHYBARRC'"
        echo "added 2 lines to $SKETCHYBARRC"
    else
        echo "ok    $SKETCHYBARRC already configured"
    fi
fi

echo
echo "Done. Reload SketchyBar: sketchybar --reload"
