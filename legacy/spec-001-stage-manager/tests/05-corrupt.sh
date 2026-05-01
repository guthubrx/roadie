#!/usr/bin/env bash
# tests/05-corrupt.sh — tolerance fichier corrompu (FR-008) +
# respect de l'edition manuelle des fichiers d'etat (FR-011).

set -e
source "$(dirname "$0")/helpers.sh"
require_binary
setup_stage_dir

echo ">>> Scenario A : ligne malformee + lignes valides"

# Ligne 1 : malformee (champs manquants)
# Ligne 2 : malformee (CGWindowID non numerique)
# Ligne 3 : valide mais cgWindowID inexistant en systeme (sera prune)
printf 'malformee_un_champ\n9999\tcom.foo\tnope\n1234\tcom.apple.Terminal\t999999999\n' > "$STAGE_DIR/1"

OUT_ERR=$("$STAGE_BIN" 1 2>&1 >/dev/null || true)
EXIT=$?

# Le binaire doit avoir signale au moins une ligne corrompue sur stderr.
if ! echo "$OUT_ERR" | grep -q "corrompue"; then
	echo "ASSERT FAIL: aucun message 'corrompue' sur stderr" >&2
	echo "stderr capture :" >&2
	echo "$OUT_ERR" >&2
	exit 1
fi

# La ligne valide mais avec wid mort doit etre prunee.
if ! echo "$OUT_ERR" | grep -q "no longer exists, pruned"; then
	echo "ASSERT FAIL: aucun message de prune pour la ligne valide morte" >&2
	echo "stderr capture :" >&2
	echo "$OUT_ERR" >&2
	exit 1
fi

# Apres le run, les 2 lignes malformees ET la ligne morte doivent avoir disparu.
# (Les corrompues sont logees mais pas re-ecrites ; la prune efface le fichier
#  reecrit a partir des lignes valides survivantes uniquement.)
if [ -s "$STAGE_DIR/1" ]; then
	if grep -q "malformee_un_champ\|nope" "$STAGE_DIR/1"; then
		echo "ASSERT FAIL: lignes corrompues encore presentes apres prune" >&2
		cat "$STAGE_DIR/1" >&2
		exit 1
	fi
fi

echo "    OK : lignes corrompues ignorees, ligne morte prunee"

echo ">>> Scenario B : edition manuelle d'une ligne valide en plein milieu"

# On simule un utilisateur qui edite ~/.stage/2 a la main avec un editeur.
# Le binaire doit honorer cette ligne au prochain switch.
cat > "$STAGE_DIR/2" <<EOF
4321	com.example.editor	555555555
EOF

OUT_ERR=$("$STAGE_BIN" 2 2>&1 >/dev/null || true)

# La ligne valide pointe vers un wid inexistant : doit etre prunee proprement,
# pas plantee.
if ! echo "$OUT_ERR" | grep -q "no longer exists, pruned"; then
	echo "ASSERT FAIL: ligne editee manuellement non prunee" >&2
	echo "$OUT_ERR" >&2
	exit 1
fi

# Apres prune, le fichier doit etre vide ou inexistant.
assert_file_empty_or_absent "$STAGE_DIR/2"

# current doit valoir 2 (basculement effectue malgre stage vide).
assert_file_contains "$STAGE_DIR/current" "2"

echo "    OK : edition manuelle respectee et prunee comme une ligne normale"

echo "TEST 05-corrupt : SUCCES"
