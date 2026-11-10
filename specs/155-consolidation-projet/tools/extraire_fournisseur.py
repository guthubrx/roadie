#!/usr/bin/env python3
"""Sort ReplayableSnapshotProvider de LayoutMaintainer.swift vers son propre fichier.

Outil à usage unique de la spec 155 (tâche T033). Il se repère sur le commentaire qui
précède la classe, jamais sur des numéros de ligne. Le code déplacé n'est pas modifié.

Usage (depuis la racine du worktree) :
    python3 -I -B specs/155-consolidation-projet/tools/extraire_fournisseur.py
    python3 -I -B specs/155-consolidation-projet/tools/extraire_fournisseur.py --check
"""
import argparse
import os
import subprocess
import sys
from pathlib import Path

BASE_COMMIT = "0b7de36b"
SOURCE = "Sources/RoadieDaemon/LayoutMaintainer.swift"
TARGET = "Sources/RoadieDaemon/ReplayableSnapshotProvider.swift"
MARKER = "/// Fournisseur qui garde son dernier relevé et peut le rejouer une fois (R11, T210) : la copie de"
CLASS_LINE = "public final class ReplayableSnapshotProvider: SystemSnapshotProviding, @unchecked Sendable {"
IMPORTS = ["import AppKit", "import Foundation", "import RoadieAX", "import RoadieCore",
           "import RoadieStages", "import RoadieTiler", ""]


def fail(message):
    print(f"ERREUR : {message}", file=sys.stderr)
    sys.exit(1)


def split(lines):
    """Rend (lignes gardées, bloc déplacé). Complexité : O(n), n = lignes du fichier."""
    found = [i for i, line in enumerate(lines) if line == MARKER]
    if len(found) != 1:
        fail(f"le commentaire de la classe apparaît {len(found)} fois dans {SOURCE} (attendu : 1)")
    start = found[0]
    block = lines[start:]
    while block and not block[-1].strip():
        block.pop()
    if CLASS_LINE not in block[:5]:
        fail("la déclaration de ReplayableSnapshotProvider ne suit pas le commentaire")
    if block[-1] != "}":
        fail("le bloc à déplacer ne finit pas par une accolade fermante seule")
    other = [l for l in block if l.startswith(("public ", "final ", "struct ", "enum ", "extension ", "private extension "))]
    if other != [CLASS_LINE]:
        fail(f"le bloc contient d'autres déclarations de premier niveau : {other}")
    kept = lines[:start]
    while kept and not kept[-1].strip():
        kept.pop()
    return kept, block


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[3]
    source = root / SOURCE
    target = root / TARGET

    if args.check:
        base = subprocess.run(["git", "-C", str(root), "show", f"{BASE_COMMIT}:{SOURCE}"],
                              capture_output=True, text=True, check=False)
        if base.returncode != 0:
            fail(f"lecture de {SOURCE} au commit {BASE_COMMIT} impossible")
        kept, block = split(base.stdout.split("\n"))
        if not target.is_file():
            fail(f"{TARGET} est absent")
        if target.read_text(encoding="utf-8") != "\n".join(IMPORTS + block) + "\n":
            fail(f"{TARGET} diffère du bloc d'origine")
        if source.read_text(encoding="utf-8") != "\n".join(kept) + "\n":
            fail(f"{SOURCE} diffère du fichier d'origine sans le bloc")
        print(f"OK : {len(block)} lignes déplacées sans changement, {len(kept)} lignes restent dans {SOURCE}")
        return

    if target.exists():
        fail(f"{TARGET} existe déjà : l'extraction a déjà été faite")
    kept, block = split(source.read_text(encoding="utf-8").split("\n"))
    # Les deux contenus sont écrits à côté, puis mis en place : pas d'état à moitié fait.
    outputs = [(target, IMPORTS + block), (source, kept)]
    for path, content in outputs:
        path.with_name(path.name + ".tmp155").write_text("\n".join(content) + "\n", encoding="utf-8")
    for path, _ in outputs:
        os.replace(path.with_name(path.name + ".tmp155"), path)
    print(f"lignes_deplacees={len(block)}")
    print(f"lignes_restantes={len(kept)}")
    print(f"fichier={target}")


if __name__ == "__main__":
    main()
