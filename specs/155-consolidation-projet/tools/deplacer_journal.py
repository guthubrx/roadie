#!/usr/bin/env python3
"""Déplace le journal des sessions d'AGENTS.md vers .specify/memory/sessions/journal.md.

Outil à usage unique de la spec 155 (tâche T016). Il se repère sur les marqueurs du
fichier, jamais sur des numéros de ligne.

Usage (depuis la racine du worktree) :
    python3 -I -B specs/155-consolidation-projet/tools/deplacer_journal.py
    python3 -I -B specs/155-consolidation-projet/tools/deplacer_journal.py --check

Sans option : déplace le journal. Avec --check : compare le résultat au fichier AGENTS.md
du commit de base et ne modifie rien. Option --root DOSSIER : travaille sur une copie.
"""
import argparse
import os
import subprocess
import sys
from pathlib import Path

BASE_COMMIT = "0b7de36b"
START = "<!-- SPECKIT START -->"
FEATURE_PREFIX = "Current SpecKit feature:"
END = "<!-- SPECKIT END -->"
USER_START = "<!-- SPECKIT-USER START -->"
USER_END = "<!-- SPECKIT-USER END -->"
HEADER = [
    "# Journal des sessions Roadie",
    "",
    "Historique des livraisons, une entrée par session, de la plus ancienne à la plus récente.",
    "Ce fichier a été sorti d'`AGENTS.md` par la session 155. Ajoute chaque nouveau bilan à la fin.",
    "",
]


def fail(message):
    print(f"ERREUR : {message}", file=sys.stderr)
    sys.exit(1)


def index_of(lines, predicate, name):
    found = [i for i, line in enumerate(lines) if predicate(line)]
    if len(found) != 1:
        fail(f"le repère « {name} » apparaît {len(found)} fois dans AGENTS.md (attendu : 1)")
    return found[0]


def split(lines):
    """Rend (bloc 1, bloc 2, lignes à garder). Complexité : O(n), n = lignes d'AGENTS.md."""
    start = index_of(lines, lambda l: l == START, START)
    feature = index_of(lines, lambda l: l.startswith(FEATURE_PREFIX), FEATURE_PREFIX)
    end = index_of(lines, lambda l: l == END, END)
    user_start = index_of(lines, lambda l: l == USER_START, USER_START)
    user_end = index_of(lines, lambda l: l == USER_END, USER_END)
    if not start < feature < end < user_start < user_end:
        fail("les repères d'AGENTS.md ne sont pas dans l'ordre attendu")
    block1 = lines[start + 1:feature]
    block2 = lines[user_end + 1:]
    kept = lines[:start + 1] + lines[feature:user_end + 1]
    return block1, block2, kept


def non_empty(lines):
    return [line for line in lines if line.strip()]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true")
    parser.add_argument("--root", default=str(Path(__file__).resolve().parents[3]))
    args = parser.parse_args()
    root = Path(args.root)
    agents = root / "AGENTS.md"
    journal = root / ".specify" / "memory" / "sessions" / "journal.md"

    if args.check:
        # Le commit de base est lu dans le dépôt de l'outil : son contenu est le même partout,
        # et une copie donnée par --root n'est pas toujours un dépôt Git.
        base = subprocess.run(
            ["git", "-C", str(Path(__file__).resolve().parents[3]), "show", f"{BASE_COMMIT}:AGENTS.md"],
            capture_output=True, text=True, check=False,
        )
        if base.returncode != 0:
            fail(f"lecture d'AGENTS.md au commit {BASE_COMMIT} impossible")
        block1, block2, _ = split(base.stdout.split("\n"))
        expected = non_empty(block1 + block2)
        if not journal.is_file():
            fail(f"{journal} est absent")
        actual = non_empty(journal.read_text(encoding="utf-8").split("\n"))
        body = actual[len(non_empty(HEADER)):]
        if body[:len(expected)] != expected:
            fail("le journal ne reprend pas toutes les lignes d'origine, dans l'ordre")
        _, rest2, kept = split(agents.read_text(encoding="utf-8").split("\n"))
        present = set(kept) | set(rest2)
        still_there = [line for line in expected if line in present]
        if still_there:
            fail(f"{len(still_there)} ligne(s) de journal restent dans AGENTS.md")
        print(f"OK : {len(expected)} lignes de journal conservées, 0 restante dans AGENTS.md")
        return

    if journal.exists():
        fail(f"{journal} existe déjà : le déplacement a déjà été fait")
    lines = agents.read_text(encoding="utf-8").split("\n")
    block1, block2, kept = split(lines)
    moved = non_empty(block1 + block2)
    if not moved:
        fail("aucune ligne de journal à déplacer")
    while block1 and not block1[-1].strip():
        block1.pop()
    while block2 and not block2[-1].strip():
        block2.pop()
    while kept and not kept[-1].strip():
        kept.pop()
    # Les deux contenus sont écrits à côté, puis mis en place : pas d'état à moitié fait.
    journal.parent.mkdir(parents=True, exist_ok=True)
    outputs = [(journal, HEADER + block1 + [""] + block2), (agents, kept)]
    for path, content in outputs:
        path.with_name(path.name + ".tmp155").write_text("\n".join(content) + "\n", encoding="utf-8")
    for path, _ in outputs:
        os.replace(path.with_name(path.name + ".tmp155"), path)
    print(f"lignes_deplacees={len(moved)}")
    print(f"journal={journal}")
    print(f"octets_agents={agents.stat().st_size}")


if __name__ == "__main__":
    main()
