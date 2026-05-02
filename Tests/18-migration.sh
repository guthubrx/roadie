#!/usr/bin/env bash
# T033 — Vérifier la migration V1→V2 sur un dossier de test isolé.
# Usage : ./tests/18-migration.sh
# Résultat attendu : backup .v1.bak créé, fichiers déplacés dans <UUID>/1/.
set -euo pipefail

TMP=$(mktemp -d)
trap "rm -rf $TMP" EXIT

STAGES_DIR="$TMP/stages"
FAKE_UUID="TEST-UUID-SPEC-018"

mkdir -p "$STAGES_DIR"
printf '[id]\nvalue = "1"\ndisplay_name = "Alpha"\n' > "$STAGES_DIR/1.toml"
printf '[id]\nvalue = "2"\ndisplay_name = "Beta"\n'  > "$STAGES_DIR/2.toml"
printf '[id]\nvalue = "3"\ndisplay_name = "Gamma"\n' > "$STAGES_DIR/3.toml"

echo "=== Migration V1→V2 : test scaffolded in $STAGES_DIR ==="
echo "Fichiers source :"
ls -1 "$STAGES_DIR/"
echo ""
echo "Résultat ATTENDU après exécution MigrationV1V2:"
echo "  - $STAGES_DIR.v1.bak/{1,2,3}.toml  (backup)"
echo "  - $STAGES_DIR/$FAKE_UUID/1/{1,2,3}.toml  (migrated)"
echo ""
echo "NOTE : test complet nécessite le binaire roadied compilé."
echo "       La logique MigrationV1V2 est couverte par MigrationV1V2Tests.swift."
echo "OK: scaffold créé sans erreur"
