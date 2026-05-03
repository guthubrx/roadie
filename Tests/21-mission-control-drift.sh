#!/usr/bin/env bash
# SPEC-021 T055 — Test acceptance Mission Control drift
# STATUT : SKIPPED — validation manuelle utilisateur requise
#
# Scénario :
#   1. Ouvrir une fenêtre (ex: Terminal) et noter son wid via `roadie windows list --json`
#   2. Déplacer la fenêtre sur un autre desktop via Mission Control (Cmd+drag ou trackpad)
#   3. Attendre 4-6 secondes (2-3 cycles de poll à 2000ms)
#   4. Vérifier que `roadie windows list --json` retourne le bon desktop_id
#
# Ce test requiert un environnement multi-desktop avec Mission Control activé.
# Il ne peut pas être automatisé sans accès à l'API Mission Control (non disponible en CI).

echo "SKIPPED: T055 — validation manuelle Mission Control drift"
echo "Voir commentaire dans ce fichier pour le scénario de validation."
exit 0
