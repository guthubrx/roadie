#!/usr/bin/env bash
# tests/01-permission.sh — TEST MANUEL (exclu de `make test`).
#
# La revocation de la permission Accessibility ne peut pas etre scriptee sans
# privileges root et desactivation de TCC. Ce test documente la procedure que
# l'utilisateur doit suivre a la main pour verifier FR-007 et FR-008.

set -e
source "$(dirname "$0")/helpers.sh"
require_binary

cat <<EOF
=== TEST MANUEL : permission Accessibility ===

Ce test ne peut pas etre automatise. Suivez la procedure :

1. Ouvrez Reglages Systeme > Confidentialite et securite > Accessibilite.
2. Decochez 'stage' (ou supprimez-le de la liste avec le bouton -).
3. Quittez Reglages Systeme.
4. Dans ce terminal, executez : $STAGE_BIN 1
5. ATTENDU :
   - exit code = 2
   - stderr commence par 'stage : permission Accessibility manquante.'
   - stderr indique le chemin absolu du binaire et la procedure.
6. Re-cochez 'stage' dans Accessibilite pour restaurer le fonctionnement.

Chemin du binaire a re-autoriser : $STAGE_BIN

FIN.
EOF
