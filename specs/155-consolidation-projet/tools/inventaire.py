#!/usr/bin/env python3
"""Écrit l'inventaire des images et des diaporamas de preuves suivis par Git.

Outil de la spec 155 (tâche T041). Il lit `git ls-files` et ne supprime rien.

Usage (depuis la racine du worktree) :
    python3 -I -B specs/155-consolidation-projet/tools/inventaire.py
"""
import subprocess
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
TARGET = ROOT / "specs/155-consolidation-projet/validation/inventaire-publications.md"
IMAGES = (".png", ".jpg", ".jpeg", ".gif", ".webp", ".heic", ".mov", ".mp4")


def main():
    files = subprocess.run(["git", "-C", str(ROOT), "ls-files"], check=True,
                           capture_output=True, text=True).stdout.splitlines()
    images = [f for f in files if f.lower().endswith(IMAGES)]
    proofs = [f for f in files if f.startswith("preuves-corrections/") and f.endswith(".html")]
    lines = ["# Inventaire des images et preuves publiées - 155", "",
             "Fichiers suivis par Git, donc visibles sur le dépôt public. Aucun fichier n'est",
             "retiré par la session 155 : le retrait est la décision D8 de `decisions.md`.", ""]
    for title, group in (("Images et vidéos", images), ("Diaporamas de preuves", proofs)):
        size = sum((ROOT / f).stat().st_size for f in group)
        lines += [f"## {title}", "", f"{len(group)} fichier(s), {size} octets au total.", ""]
        for folder, count in sorted(Counter(str(Path(f).parent) for f in group).items()):
            lines.append(f"- `{folder}/` : {count}")
        lines += ["", "| Fichier | Octets |", "|---------|--------|"]
        lines += [f"| `{f}` | {(ROOT / f).stat().st_size} |" for f in sorted(group)]
        lines.append("")
    TARGET.parent.mkdir(parents=True, exist_ok=True)
    TARGET.write_text("\n".join(lines), encoding="utf-8")
    print(f"OK : {len(images)} image(s) et {len(proofs)} diaporama(s) listés dans {TARGET}")


if __name__ == "__main__":
    main()
