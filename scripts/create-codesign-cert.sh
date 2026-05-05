#!/usr/bin/env bash
# Crée un certificat auto-signé `roadied-cert` dans le trousseau login.
# Utilisé par install-dev.sh pour signer roadied avec une identité stable
# → TCC mémorise la grant Accessibility entre les rebuilds.
#
# Référence : ADR-008 signing & distribution strategy.

set -e

CERT_NAME="roadied-cert"

if security find-identity -v -p codesigning login.keychain 2>&1 | grep -q "$CERT_NAME"; then
  echo "Cert '$CERT_NAME' already exists in login.keychain. Nothing to do."
  exit 0
fi

echo "==> Creating self-signed code-signing cert: $CERT_NAME"
echo
echo "INSTRUCTIONS — Keychain Access va s'ouvrir."
echo "Suis les étapes (GUI manuel, security CLI ne supporte pas la création"
echo "interactive de certs code-signing avec extensions correctes) :"
echo
echo "  1. Keychain Access → menu Trousseau d'accès → Assistant de certification"
echo "     → Créer un certificat..."
echo "  2. Nom         : $CERT_NAME"
echo "  3. Type d'id   : Auto-signée racine"
echo "  4. Type cert.  : Signature de code"
echo "  5. (option)    : Coche 'Permettre de spécifier les valeurs par défaut'"
echo "                   pour passer la durée de validité à 10 ans"
echo "  6. Trousseau   : login"
echo "  7. Crée le cert."
echo
echo "Ensuite, relance ./scripts/install-dev.sh."
echo
read -r -p "Appuie sur Entrée pour ouvrir Keychain Access..."
open -a "Keychain Access"
