#!/usr/bin/env bash
# scripts/recheck-tcc.sh — détecte et diagnostique les drift TCC après rebuild.
#
# Vérifie 5 conditions et rapporte un diagnostic structuré :
#   1. Le binaire deployed est signé avec roadied-cert (pas ad-hoc).
#   2. Le hash CodeDirectory n'a pas changé depuis le dernier toggle TCC connu
#      (marker stocké dans ~/.roadies/last-tcc-toggle.hash).
#   3. Le daemon est up (launchctl + pgrep).
#   4. Le daemon répond au socket Unix dans un timeout court.
#   5. Les logs récents ne mentionnent pas "Accessibility manquante" ni
#      "screen_capture_state granted=false".
#
# Usage :
#   ./scripts/recheck-tcc.sh                   # diagnostic, exit 0 si tout OK
#   ./scripts/recheck-tcc.sh --mark-toggled    # à appeler après un toggle TCC
#                                                manuel (mémorise le hash courant
#                                                comme baseline TCC).
#   ./scripts/recheck-tcc.sh -h | --help       # ce help.
#
# Codes de sortie :
#   0 : tout OK
#   1 : drift détecté, action utilisateur requise (toggle TCC)
#   2 : signature corrompue (binaire ad-hoc)
#   3 : daemon down

set -uo pipefail
export LC_NUMERIC=C

APP_BIN="$HOME/Applications/roadied.app/Contents/MacOS/roadied"
TOGGLE_MARKER="$HOME/.roadies/last-tcc-toggle.hash"
DAEMON_LOG="$HOME/.local/state/roadies/daemon.log"

# Couleurs si stdout est un TTY.
if [ -t 1 ]; then
    R=$'\033[31m'; G=$'\033[32m'; Y=$'\033[33m'; B=$'\033[36m'; N=$'\033[0m'
else
    R=""; G=""; Y=""; B=""; N=""
fi

usage() {
    sed -n '2,/^$/p' "$0" | sed 's/^# \?//' >&2
    exit 0
}

case "${1:-}" in
    -h|--help) usage ;;
esac

# Mode --mark-toggled : sauve le hash signature courant comme baseline TCC.
if [ "${1:-}" = "--mark-toggled" ]; then
    if [ ! -x "$APP_BIN" ]; then
        echo "${R}✗${N} binaire absent : $APP_BIN"
        exit 2
    fi
    HASH=$(codesign -dv --verbose=4 "$APP_BIN" 2>&1 | awk -F= '/^CandidateCDHashFull/ {print $2; exit}')
    if [ -z "$HASH" ]; then
        echo "${R}✗${N} impossible de lire le CDHash"
        exit 2
    fi
    mkdir -p "$(dirname "$TOGGLE_MARKER")"
    echo "$HASH" > "$TOGGLE_MARKER"
    echo "${G}✓${N} TCC baseline marquée : CDHash=$HASH"
    echo "  → toute différence future = drift TCC = re-toggler dans Réglages."
    exit 0
fi

# ============================================================================
# Diagnostic complet (mode default)
# ============================================================================
ISSUES=0
echo "${B}==>${N} recheck-tcc — vérification post-rebuild"
echo

# 1. Binaire présent et signé avec roadied-cert.
echo "${B}[1/5]${N} signature du binaire deployed"
if [ ! -x "$APP_BIN" ]; then
    echo "  ${R}✗${N} binaire absent : $APP_BIN"
    echo "    → run ./scripts/install-dev.sh"
    exit 2
fi

CS_OUTPUT=$(codesign -dv --verbose=4 "$APP_BIN" 2>&1)
AUTHORITY=$(echo "$CS_OUTPUT" | awk -F= '/^Authority=/ {print $2; exit}')
IS_ADHOC=$(echo "$CS_OUTPUT" | grep -c "Signature=adhoc")
CDHASH=$(echo "$CS_OUTPUT" | awk -F= '/^CandidateCDHashFull/ {print $2; exit}')

if [ "$IS_ADHOC" -gt 0 ]; then
    echo "  ${R}✗${N} binaire signé ${R}AD-HOC${N} (Signature=adhoc)"
    echo "    → grants TCC complètement perdues."
    echo "    → run ./scripts/install-dev.sh APRÈS avoir débloqué le keychain"
    echo "      (Keychain Access > Login > unlock)."
    exit 2
fi

if [ "$AUTHORITY" != "roadied-cert" ]; then
    echo "  ${Y}⚠${N} authority = '$AUTHORITY' (attendu : roadied-cert)"
    ISSUES=$((ISSUES + 1))
else
    echo "  ${G}✓${N} authority = roadied-cert"
fi
echo "  ${B}·${N} CDHash=$CDHASH"

# 2. Drift de hash depuis le dernier toggle TCC.
echo
echo "${B}[2/5]${N} hash binaire vs dernier toggle TCC"
if [ ! -f "$TOGGLE_MARKER" ]; then
    echo "  ${Y}⚠${N} pas de baseline TCC enregistrée."
    echo "    → si le daemon répond bien (étape 4), lancer :"
    echo "      ./scripts/recheck-tcc.sh --mark-toggled"
    echo "    pour figer le hash courant comme référence."
else
    LAST_HASH=$(cat "$TOGGLE_MARKER")
    if [ "$CDHASH" = "$LAST_HASH" ]; then
        echo "  ${G}✓${N} hash inchangé depuis le dernier toggle"
    else
        echo "  ${R}✗${N} hash a changé depuis le dernier toggle TCC"
        echo "    baseline : $LAST_HASH"
        echo "    actuel   : $CDHASH"
        echo "    → TCC va probablement invalider la grant."
        ISSUES=$((ISSUES + 1))
    fi
fi

# 3. Daemon up.
echo
echo "${B}[3/5]${N} daemon en cours"
DAEMON_PID=$(pgrep -x roadied | head -1)
if [ -z "$DAEMON_PID" ]; then
    echo "  ${R}✗${N} aucun process roadied"
    echo "    → run ./scripts/install-dev.sh ou launchctl bootstrap"
    exit 3
fi
echo "  ${G}✓${N} PID=$DAEMON_PID"

# launchctl status : info historique (dernier exit du process précédent).
# Pas comptabilisé comme erreur si le daemon actuel répond bien (étape 4).
# `-11` = SIGSEGV vrai crash, `2` = wait-loop AX expirée → mémorisé pour info,
# pas bloquant si le respawn courant est OK.
LAUNCHCTL_STATUS=$(launchctl list 2>/dev/null | awk '$3 == "com.roadie.roadie" {print $2}')
if [ -n "$LAUNCHCTL_STATUS" ] && [ "$LAUNCHCTL_STATUS" != "0" ] && [ "$LAUNCHCTL_STATUS" != "-" ]; then
    echo "  ${B}·${N} launchctl historique : exit=$LAUNCHCTL_STATUS du run précédent"
    case "$LAUNCHCTL_STATUS" in
        2)   echo "      (wait-loop Accessibility expirée — résolu si étape 4 OK)" ;;
        -11) echo "      ${Y}⚠ SIGSEGV historique (vérifier ~/Library/Logs/DiagnosticReports/)${N}" ;;
    esac
fi

# 4. Daemon répond via CLI dans un timeout court.
echo
echo "${B}[4/5]${N} daemon répond au socket"
if timeout 2 ~/.local/bin/roadie daemon status >/dev/null 2>&1; then
    echo "  ${G}✓${N} CLI répond"
    # Bonus : extraire arch_version pour confirmer V2.
    ARCH=$(~/.local/bin/roadie daemon status 2>/dev/null | awk '/^arch_version:/ {print $2}')
    if [ -n "$ARCH" ]; then
        echo "  ${B}·${N} arch_version=$ARCH"
    fi
else
    echo "  ${R}✗${N} timeout sur 'roadie daemon status'"
    echo "    → daemon UP mais bloqué (très probablement wait-loop AX)."
    ISSUES=$((ISSUES + 1))
fi

# 5. Logs récents : Accessibility / Screen Recording warnings.
echo
echo "${B}[5/5]${N} logs récents (60s)"
if [ ! -f "$DAEMON_LOG" ]; then
    echo "  ${Y}⚠${N} log absent : $DAEMON_LOG"
else
    # Filtre les lignes des 60 dernières secondes (approximation : tail).
    NOW_MS=$(date +%s)000
    SINCE_MS=$(( NOW_MS - 60000 ))
    RECENT=$(tail -200 "$DAEMON_LOG")

    AX_FAIL=$(echo "$RECENT" | grep -c "permission Accessibility" || true)
    SR_DENIED=$(echo "$RECENT" | grep -c '"screen_capture_state".*"granted":"false"' || true)

    if [ "$AX_FAIL" -gt 0 ]; then
        echo "  ${R}✗${N} $AX_FAIL log(s) 'permission Accessibility manquante' récent(s)"
        echo "    → toggle Accessibility dans Réglages Système requis."
        ISSUES=$((ISSUES + 1))
    else
        echo "  ${G}✓${N} aucun warning Accessibility"
    fi

    if [ "$SR_DENIED" -gt 0 ]; then
        echo "  ${Y}⚠${N} Screen Recording denied dans les logs"
        echo "    → les thumbnails du rail seront en mode dégradé (icônes)."
        echo "    → toggle Screen Recording si tu veux les vraies vignettes."
        ISSUES=$((ISSUES + 1))
    else
        echo "  ${G}✓${N} Screen Recording OK (ou absent du log récent)"
    fi
fi

# ============================================================================
# Résumé
# ============================================================================
echo
if [ "$ISSUES" -eq 0 ]; then
    echo "${G}✓ TCC OK${N} — aucun drift détecté."
    if [ ! -f "$TOGGLE_MARKER" ]; then
        echo "  Pour figer cet état comme baseline :"
        echo "    ./scripts/recheck-tcc.sh --mark-toggled"
    fi
    exit 0
else
    echo "${R}✗ $ISSUES problème(s) détecté(s).${N}"
    echo
    echo "Solution standard :"
    echo "  1. Réglages Système → Confidentialité → Accessibilité"
    echo "  2. Décocher puis recocher 'roadied'"
    echo "  3. ${B}./scripts/recheck-tcc.sh --mark-toggled${N} (mémorise la baseline)"
    echo "  4. ${B}./scripts/recheck-tcc.sh${N} (re-vérifie)"
    exit 1
fi
