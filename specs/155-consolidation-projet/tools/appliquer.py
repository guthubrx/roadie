#!/usr/bin/env python3
"""Applique les changements préparés d'une tâche de la spec 155.

Usage (depuis la racine du worktree) :
    python3 -I -B specs/155-consolidation-projet/tools/appliquer.py T007 --check
    python3 -I -B specs/155-consolidation-projet/tools/appliquer.py T007
    python3 -I -B specs/155-consolidation-projet/tools/appliquer.py --liste

Les changements sont décrits dans remplacements.json (même dossier) :
- « copies » : un fichier de gabarits/ copié vers sa destination ;
- « remplacements » : un texte « avant » remplacé par un texte « apres » dans un fichier.
  Le changement est vu comme déjà fait si le texte « marqueur » (à défaut, « apres ») est
  déjà dans le fichier : relancer une tâche ne change donc rien. Si le marqueur est là mais
  pas tout le texte ajouté, le changement est incomplet : l'outil s'arrête.

Règle R0 : si un texte « avant » n'apparaît pas exactement une fois, l'outil n'écrit RIEN
et rend le code 1. Ne corrige pas le fichier à la main : arrête la tâche et signale-le.
--check contrôle sans écrire. --root DOSSIER travaille sur une copie du dépôt.
"""
import argparse
import json
import os
import sys
from pathlib import Path

SPEC_DIR = Path(__file__).resolve().parents[1]


def added_text(edit):
    """Texte inséré quand « apres » est « avant » plus une insertion ; sinon « apres » entier."""
    before, after = edit["avant"], edit["apres"]
    head = len(os.path.commonprefix([before, after]))
    tail = len(os.path.commonprefix([before[head:][::-1], after[head:][::-1]]))
    if head + tail == len(before):
        return after[head:len(after) - tail]
    return after


def plan(task, data, root):
    """Rend (écritures, messages, erreurs). Complexité : O(n), n = octets des fichiers touchés."""
    writes, notes, errors = {}, [], []
    for copy in (c for c in data["copies"] if c["tache"] == task):
        source = (SPEC_DIR / copy["source"]).read_bytes()
        target = root / copy["destination"]
        if not target.exists():
            writes[target] = (source, copy.get("executable", False))
            notes.append(f"copie    {copy['source']} -> {copy['destination']}")
        elif target.read_bytes() == source:
            notes.append(f"déjà là  {copy['destination']}")
        else:
            errors.append(f"{copy['destination']} existe déjà avec un autre contenu")
    texts = {}
    for edit in (r for r in data["remplacements"] if r["tache"] == task):
        target = root / edit["fichier"]
        if target not in texts:
            if not target.is_file():
                errors.append(f"{edit['id']} : fichier absent : {edit['fichier']}")
                continue
            texts[target] = target.read_text(encoding="utf-8")
        text = texts[target]
        if edit.get("marqueur", edit["apres"]) in text:
            if added_text(edit) not in text:
                errors.append(f"{edit['id']} : changement incomplet dans {edit['fichier']} (marqueur présent, texte ajouté absent)")
            else:
                notes.append(f"déjà fait {edit['id']} {edit['fichier']}")
            continue
        count = text.count(edit["avant"])
        if count != 1:
            errors.append(f"{edit['id']} : texte « avant » présent {count} fois dans {edit['fichier']} (attendu : 1)")
            continue
        texts[target] = text.replace(edit["avant"], edit["apres"])
        writes[target] = (texts[target].encode("utf-8"), None)
        notes.append(f"remplace {edit['id']} {edit['fichier']}")
    return writes, notes, errors


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("tache", nargs="?")
    parser.add_argument("--check", action="store_true")
    parser.add_argument("--liste", action="store_true")
    parser.add_argument("--root", default=str(SPEC_DIR.parents[1]))
    args = parser.parse_args()
    data = json.loads((SPEC_DIR / "tools" / "remplacements.json").read_text(encoding="utf-8"))
    tasks = sorted({c["tache"] for c in data["copies"]} | {r["tache"] for r in data["remplacements"]})
    if args.liste:
        print(" ".join(tasks))
        return
    if args.tache not in tasks:
        sys.exit(f"ERREUR : aucune action préparée pour « {args.tache} ». Tâches connues : {' '.join(tasks)}")
    writes, notes, errors = plan(args.tache, data, Path(args.root))
    for note in notes:
        print(note)
    if errors:
        for error in errors:
            print(f"ERREUR : {error}", file=sys.stderr)
        sys.exit("ARRÊT (règle R0) : rien n'a été écrit.")
    if args.check:
        print(f"OK {args.tache} : contrôle réussi, rien n'a été écrit ({len(writes)} fichier(s) à écrire).")
        return
    # Tous les contenus sont prêts : chaque fichier est écrit à côté, puis mis en place d'un coup.
    for target, (content, executable) in writes.items():
        target.parent.mkdir(parents=True, exist_ok=True)
        temp = target.with_name(target.name + ".tmp155")
        temp.write_bytes(content)
        if executable:
            temp.chmod(0o755)
        elif target.exists():
            temp.chmod(target.stat().st_mode & 0o777)
        os.replace(temp, target)
    print(f"OK {args.tache} : {len(writes)} fichier(s) écrit(s).")


if __name__ == "__main__":
    main()
