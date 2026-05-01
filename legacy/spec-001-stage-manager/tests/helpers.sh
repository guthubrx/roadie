#!/usr/bin/env bash
# Helpers communs aux tests d'acceptation de stage.
# Source ce fichier en tete de chaque test : `source "$(dirname "$0")/helpers.sh"`

set -e

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STAGE_BIN="$REPO_ROOT/stage"
STAGE_DIR="$HOME/.stage"
STAGE_DIR_BACKUP="$HOME/.stage.test-backup-$$"

# Sauvegarde l'etat utilisateur actuel et part d'un repertoire ~/.stage propre.
setup_stage_dir() {
	if [ -d "$STAGE_DIR" ]; then
		mv "$STAGE_DIR" "$STAGE_DIR_BACKUP"
	fi
	mkdir -p "$STAGE_DIR"
}

# Restaure l'etat utilisateur d'origine et nettoie l'etat de test.
cleanup_stage_dir() {
	rm -rf "$STAGE_DIR"
	if [ -d "$STAGE_DIR_BACKUP" ]; then
		mv "$STAGE_DIR_BACKUP" "$STAGE_DIR"
	fi
}

# Marqueur unique pour identifier nos fenetres test parmi celles de l'utilisateur.
STAGE_TEST_MARKER="STAGE_AUTOTEST_$$"

# Ouvre une fenetre Terminal marquee avec STAGE_TEST_MARKER dans son contenu
# (et donc dans son titre via PROMPT_COMMAND). Echo le compteur d'ouverture.
open_terminal() {
	osascript <<EOF >/dev/null
tell application "Terminal"
	activate
	do script "printf '\\\\033]0;${STAGE_TEST_MARKER}\\\\007' ; clear"
end tell
EOF
	sleep 0.7
}

# Ferme TOUTES les fenetres Terminal dont le titre contient STAGE_TEST_MARKER.
# Ne touche jamais aux fenetres utilisateur. A utiliser en cleanup.
close_test_terminals() {
	osascript <<EOF >/dev/null 2>&1 || true
tell application "Terminal"
	-- Restaurer toutes les fenetres marquees pour qu'elles puissent se fermer.
	repeat with w in (windows whose name contains "${STAGE_TEST_MARKER}")
		try
			set miniaturized of w to false
		end try
	end repeat
	-- Fermer toutes les fenetres marquees.
	repeat with w in (windows whose name contains "${STAGE_TEST_MARKER}")
		try
			close w
		end try
	end repeat
end tell
EOF
	sleep 0.3
}

# Compte les fenetres Terminal marquees encore minimisees.
count_test_minimized() {
	osascript <<EOF
tell application "Terminal"
	count of (windows whose name contains "${STAGE_TEST_MARKER}" and miniaturized is true)
end tell
EOF
}

# Compte les fenetres Terminal marquees ouvertes (toutes etats confondus).
count_test_windows() {
	osascript <<EOF
tell application "Terminal"
	count of (windows whose name contains "${STAGE_TEST_MARKER}")
end tell
EOF
}

# Renvoie 0 si le fichier $1 contient le motif $2 sur au moins une ligne, sinon 1.
assert_file_contains() {
	local file="$1"
	local pattern="$2"
	if ! grep -q -- "$pattern" "$file" 2>/dev/null; then
		echo "ASSERT FAIL: '$pattern' absent de $file" >&2
		echo "Contenu actuel :" >&2
		cat "$file" >&2 || true
		return 1
	fi
}

# Renvoie 0 si le fichier $1 contient exactement $2 lignes, sinon 1.
assert_file_lines() {
	local file="$1"
	local expected="$2"
	local actual
	actual=$(wc -l < "$file" 2>/dev/null || echo 0)
	# Trim espaces (BSD wc renvoie "       3").
	actual=$(echo "$actual" | tr -d ' ')
	if [ "$actual" != "$expected" ]; then
		echo "ASSERT FAIL: $file contient $actual lignes, attendu $expected" >&2
		cat "$file" >&2 || true
		return 1
	fi
}

# Renvoie 0 si le fichier $1 n'existe pas ou est vide, sinon 1.
assert_file_empty_or_absent() {
	local file="$1"
	if [ -s "$file" ]; then
		echo "ASSERT FAIL: $file existe et est non vide" >&2
		cat "$file" >&2 || true
		return 1
	fi
}

# Verifie que le binaire stage est buildé.
require_binary() {
	if [ ! -x "$STAGE_BIN" ]; then
		echo "Binaire absent ou non executable : $STAGE_BIN" >&2
		echo "Lancer 'make' depuis $REPO_ROOT" >&2
		exit 1
	fi
}

# Trap par defaut : nettoie en sortie (stage dir + fenetres test marquees).
_full_cleanup() {
	close_test_terminals
	cleanup_stage_dir
}
trap _full_cleanup EXIT
