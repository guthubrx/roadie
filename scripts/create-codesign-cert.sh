#!/usr/bin/env bash
# Crée + installe automatiquement un cert auto-signé `roadied-cert` dans
# le trousseau login. Utilisé par install-dev.sh pour signer roadied avec
# une identité stable → TCC mémorise la grant Accessibility entre rebuilds.
#
# Auto-magique : openssl génère cert+clé, security import dans login keychain.
# Pas d'interaction GUI Keychain Access requise.
#
# Référence : ADR-008 signing & distribution strategy.

set -e

CERT_NAME="${ROADIE_CERT:-roadied-cert}"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"
P12_PASS="roadied"

# Mode --force : régénère même si le cert existe (utile après changement de
# template d'extensions, cf. fix Tahoe non-critical).
FORCE=0
if [ "${1:-}" = "--force" ]; then
  FORCE=1
fi

# Si le cert existe déjà ET a une clé privée associée :
#   - sans --force : ne rien faire (workflow normal).
#   - avec --force : tout supprimer pour reprendre à zéro.
if security find-identity -v -p codesigning login.keychain 2>&1 | grep -q "$CERT_NAME"; then
  if [ "$FORCE" -eq 0 ]; then
    echo "OK: '$CERT_NAME' already a valid code-signing identity. Nothing to do."
    echo "    (use --force to regenerate from scratch)"
    exit 0
  fi
  echo "==> --force : suppression de l'identity '$CERT_NAME' existante (cert + clé)"
  security delete-identity -c "$CERT_NAME" "$KEYCHAIN" 2>/dev/null || true
fi

# Si un cert orphelin (= sans clé privée) existe avec le même nom, le supprimer
# avant d'en recréer un (sinon conflit de nom au moment de l'import).
if security find-certificate -c "$CERT_NAME" "$KEYCHAIN" >/dev/null 2>&1; then
  echo "==> Removing orphan cert '$CERT_NAME' (no associated private key)"
  security delete-certificate -c "$CERT_NAME" "$KEYCHAIN" 2>/dev/null || true
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "==> Generating self-signed code-signing cert: $CERT_NAME"

# 1. Config OpenSSL avec extensions code-signing nécessaires pour macOS.
cat > "$TMP/openssl.cnf" <<EOF
[req]
distinguished_name = req_dn
prompt = no
x509_extensions = v3_ext

[req_dn]
CN = $CERT_NAME
C = FR

[v3_ext]
# Non-critical : reproduit fidelement la structure d'un cert genere par
# Keychain Access > Certificate Assistant en mode "Code Signing".
# Apple TCC sur macOS 15 (Tahoe) refuse de stabiliser une grant pour un
# cert dont les extensions sont toutes flag critical -- observe en mai 2026,
# cf. issue OpenClaw#14138 + thread Apple Developer Forums 730043.
basicConstraints = CA:FALSE
keyUsage = digitalSignature
extendedKeyUsage = codeSigning
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid:always
EOF

# 2. Génère la clé privée + cert auto-signé valable 10 ans.
openssl req -x509 -newkey rsa:2048 -nodes \
  -keyout "$TMP/key.pem" \
  -out "$TMP/cert.pem" \
  -days 3650 \
  -config "$TMP/openssl.cnf" 2>/dev/null

# 3. Pack en PKCS12 (clé+cert ensemble) avec mdp throwaway.
# Flag `-legacy` requis pour OpenSSL 3.x : sinon Apple security ne sait pas lire
# (chiffrement par défaut OpenSSL 3 = AES-256-CBC + PBKDF2, pas reconnu par
# l'import PKCS12 historique d'Apple).
openssl pkcs12 -export -legacy \
  -inkey "$TMP/key.pem" \
  -in "$TMP/cert.pem" \
  -out "$TMP/cert.p12" \
  -password "pass:$P12_PASS" \
  -name "$CERT_NAME" 2>/dev/null

# 4. Import dans le trousseau login. -T codesign autorise codesign à utiliser
# la clé sans prompter à chaque utilisation.
echo "==> Importing into login keychain (entrer ton mdp utilisateur si demandé)"
security import "$TMP/cert.p12" \
  -k "$KEYCHAIN" \
  -P "$P12_PASS" \
  -T /usr/bin/codesign \
  -T /usr/bin/security 2>&1 | tail -3

# 5. Marquer le cert "trusted" pour code-signing (user-domain, pas admin).
echo "==> Trusting cert for code-signing (entrer ton mdp utilisateur si demandé)"
security add-trusted-cert -p codeSign -k "$KEYCHAIN" "$TMP/cert.pem" 2>&1 | tail -3 || \
  echo "(trust optional, continue)"

# 6. Verify.
echo
echo "==> Verifying..."
if security find-identity -v -p codesigning login.keychain 2>&1 | grep -q "$CERT_NAME"; then
  echo "✓ '$CERT_NAME' is now a valid code-signing identity."
  echo
  echo "Next: ./scripts/install-dev.sh"
else
  echo "✗ Cert imported but not visible as identity."
  echo "  Try: security find-identity -v -p codesigning"
  exit 1
fi
