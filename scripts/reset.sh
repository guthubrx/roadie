#!/usr/bin/env bash
# scripts/reset.sh — réinitialise l'état desktops/stages de roadies.
#
# Sécurité : crée un backup tar.gz avant toute suppression.
#            Confirmation interactive sauf --yes.
#            Stop daemon (et rail) avant reset, restart à la fin.
#
# Usage :
#   ./scripts/reset.sh --state             # vide stages/desktops déclarés, garde roadies.toml
#   ./scripts/reset.sh --hard              # --state + ~/.roadies/ + nettoie *.archived-*
#   ./scripts/reset.sh --nuke              # tout supprime y compris roadies.toml
#   ./scripts/reset.sh --hard --yes        # non-interactif
#   ./scripts/reset.sh --hard --no-restart # reset sans relancer le daemon
#
# Niveaux :
#   --state    : vide ~/.config/roadies/{stages,displays}/
#                garde   ~/.config/roadies/roadies.toml
#   --hard     : --state +
#                supprime ~/.roadies/ (sock + pid)
#                supprime tous les *.archived-* et *.legacy-* dans la config
#   --nuke     : --hard +
#                supprime ~/.config/roadies/roadies.toml
#                (retour à un état totalement vierge — daemon recréera défauts)

set -euo pipefail

CONFIG_DIR="$HOME/.config/roadies"
RUNTIME_DIR="$HOME/.roadies"
BACKUP_DIR="/tmp"

# Couleurs
_log()  { printf '\033[1;36m[reset]\033[0m %s\n' "$*"; }
_warn() { printf '\033[1;33m[reset] WARN:\033[0m %s\n' "$*" >&2; }
_err()  { printf '\033[1;31m[reset] ERROR:\033[0m %s\n' "$*" >&2; }
_ok()   { printf '\033[1;32m[reset] OK:\033[0m %s\n' "$*"; }

usage() {
    cat <<'EOF' >&2
usage: reset.sh [--state|--hard|--nuke] [--yes] [--no-restart]

Niveaux (mutuellement exclusifs, --hard par défaut si rien spécifié) :
  --state      vide ~/.config/roadies/{stages,displays}/ (garde roadies.toml)
  --hard       --state + ~/.roadies/ + nettoie les *.archived-*/*.legacy-*
  --nuke       --hard + supprime roadies.toml (état totalement vierge)

Options :
  --yes          pas de confirmation interactive
  --no-restart   ne relance pas le daemon après reset

Backup auto : /tmp/roadies-reset-backup-<timestamp>.tar.gz
EOF
}

LEVEL=""
ASSUME_YES=0
NO_RESTART=0

for arg in "$@"; do
    case "$arg" in
        --state) LEVEL="state" ;;
        --hard)  LEVEL="hard" ;;
        --nuke)  LEVEL="nuke" ;;
        --yes|-y) ASSUME_YES=1 ;;
        --no-restart) NO_RESTART=1 ;;
        --help|-h) usage; exit 0 ;;
        *) _err "flag inconnu : $arg"; usage; exit 2 ;;
    esac
done

if [ -z "$LEVEL" ]; then
    LEVEL="hard"
    _log "Aucun niveau spécifié → default --hard"
fi

# ============================================================================
# Étape 1 : récap + confirmation
# ============================================================================
echo ""
_log "Niveau : --$LEVEL"
case "$LEVEL" in
    state)
        echo "  → vide ${CONFIG_DIR}/stages/"
        echo "  → vide ${CONFIG_DIR}/displays/"
        echo "  → garde ${CONFIG_DIR}/roadies.toml"
        ;;
    hard)
        echo "  → vide ${CONFIG_DIR}/stages/"
        echo "  → vide ${CONFIG_DIR}/displays/"
        echo "  → supprime ${RUNTIME_DIR}/"
        echo "  → supprime tous les *.archived-* et *.legacy-* dans ${CONFIG_DIR}/"
        echo "  → garde ${CONFIG_DIR}/roadies.toml"
        ;;
    nuke)
        _warn "Mode --nuke : suppression COMPLÈTE de ${CONFIG_DIR}/ et ${RUNTIME_DIR}/"
        echo "  → ${CONFIG_DIR}/roadies.toml SERA SUPPRIMÉ"
        ;;
esac
echo ""

if [ "$ASSUME_YES" -eq 0 ]; then
    read -r -p "Confirmer ? [y/N] " confirm
    case "$confirm" in
        y|Y|yes|YES|oui|OUI) ;;
        *) _log "Annulé."; exit 0 ;;
    esac
fi

# ============================================================================
# Étape 2 : backup tar.gz
# ============================================================================
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP_FILE="${BACKUP_DIR}/roadies-reset-backup-${TIMESTAMP}.tar.gz"

_log "Création backup → ${BACKUP_FILE}"
# tar -C $HOME pour avoir des paths relatifs propres dans le tar
TAR_PATHS=()
[ -d "$CONFIG_DIR" ]  && TAR_PATHS+=(".config/roadies")
[ -d "$RUNTIME_DIR" ] && TAR_PATHS+=(".roadies")

if [ "${#TAR_PATHS[@]}" -eq 0 ]; then
    _warn "Rien à backuper (config et runtime absents) — backup vide non créé"
else
    tar -czf "$BACKUP_FILE" -C "$HOME" "${TAR_PATHS[@]}" 2>/dev/null
    _ok "Backup créé : $(du -h "$BACKUP_FILE" | cut -f1) → ${BACKUP_FILE}"
fi

# ============================================================================
# Étape 3 : stop l'app (sinon elle réécrit la config). Cleanup résidu V1
# (binaire roadie-rail séparé) si présent — idempotent.
# ============================================================================
_log "Arrêt de roadied"
DAEMON_WAS_RUNNING=0

# Cleanup résidu V1 (silencieux si absent).
pkill -f "roadie-rail" 2>/dev/null || true

if pgrep -f "roadied --daemon" >/dev/null 2>&1; then
    DAEMON_WAS_RUNNING=1
    pkill -f "roadied --daemon" || true
    for _ in 1 2 3 4 5; do
        pgrep -f "roadied --daemon" >/dev/null 2>&1 || break
        sleep 0.3
    done
    pkill -9 -f "roadied --daemon" 2>/dev/null || true
    _ok "roadied stoppé"
fi

# ============================================================================
# Étape 4 : reset selon le niveau
# ============================================================================
case "$LEVEL" in
    state)
        _log "Suppression ${CONFIG_DIR}/stages/ et ${CONFIG_DIR}/displays/"
        rm -rf "${CONFIG_DIR}/stages" "${CONFIG_DIR}/displays"
        ;;
    hard)
        _log "Suppression ${CONFIG_DIR}/stages/ et ${CONFIG_DIR}/displays/"
        rm -rf "${CONFIG_DIR}/stages" "${CONFIG_DIR}/displays"

        _log "Suppression ${RUNTIME_DIR}/"
        rm -rf "$RUNTIME_DIR"

        _log "Nettoyage des *.archived-* et *.legacy-* dans ${CONFIG_DIR}/"
        # find -delete : sûr (filtré par pattern strict)
        find "$CONFIG_DIR" -maxdepth 1 -name "*.archived-*"      -delete 2>/dev/null || true
        find "$CONFIG_DIR" -maxdepth 1 -name "*.legacy.archived-*" -delete 2>/dev/null || true
        find "$CONFIG_DIR" -maxdepth 1 -name "*.bak.archived-*"  -delete 2>/dev/null || true
        ;;
    nuke)
        _log "Suppression complète ${CONFIG_DIR}/ et ${RUNTIME_DIR}/"
        rm -rf "$CONFIG_DIR" "$RUNTIME_DIR"
        ;;
esac

_ok "Reset --$LEVEL appliqué"

# ============================================================================
# Étape 5 : restart daemon (si demandé et si on l'avait stoppé)
# ============================================================================
if [ "$NO_RESTART" -eq 1 ]; then
    _log "Restart skip (--no-restart)"
elif [ "$DAEMON_WAS_RUNNING" -eq 1 ]; then
    APP_BIN="$HOME/Applications/roadied.app/Contents/MacOS/roadied"
    LOG="/tmp/roadied.log"

    if [ ! -x "$APP_BIN" ]; then
        _warn "Daemon binaire introuvable ($APP_BIN) — pas de restart"
    else
        _log "Restart daemon"
        nohup "$APP_BIN" --daemon > "$LOG" 2>&1 &
        DAEMON_PID=$!
        disown "$DAEMON_PID" 2>/dev/null || true
        sleep 0.5
        if kill -0 "$DAEMON_PID" 2>/dev/null; then
            _ok "daemon relancé, PID=$DAEMON_PID (log : tail -f $LOG)"
        else
            _err "daemon a quitté immédiatement, voir $LOG"
            tail -10 "$LOG" >&2 || true
        fi
    fi
else
    _log "(daemon n'était pas en cours, pas de restart automatique)"
fi

echo ""
_ok "Reset terminé."
echo "  Backup : ${BACKUP_FILE}"
echo "  Restore : tar -xzf '${BACKUP_FILE}' -C \"\$HOME\""
