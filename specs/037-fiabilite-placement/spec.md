# Session 037 — Fiabilité du placement et livraison des corrections

Statut : Implémentée, testée et installée. Priorité : P1. Validation : « Corrige tout », le 15 octobre 2026.

## Besoin

Corriger les restes confirmés par la revue des incidents 030–036, intégrer les sept
corrections non livrées de 035 et qualifier les deux pistes ouvertes. Conserver les
sources déjà installées de la session parallèle sans modifier son worktree.

## Acceptation

1. L'inventaire CG/PID traverse le fournisseur rejouable du tiler, y compris nil et
   rejeu d'un relevé ; une fenêtre hors Space reste membre au-delà de 30 minutes.
2. Une fenêtre nouvelle illisible attend aussi sur son écran cible. Ses voisines ne
   réservent pas un trou. La disponibilité seule relance la première écriture réelle.
   Les deux écritures AX maximales, les restaurations masquées et pins restent protégés.
3. Livrer les sept mécanismes 035 : publication de configuration, macros, tail de
   journal, identifiants sérialisés, identifiants TOML, nombres finis, flux UTF-8.
4. Remplacer la recherche linéaire répétée de cadre par une mise à jour par lot en
   conservant ordre, focus, groupes, pins, bookmarks et présentation. Mesurer avant/après.
5. Qualifier le panneau modal Firefox avec son rôle réel et un témoin légitime.
   Qualifier la perte concurrente du fichier de glisser et préserver les protections.
   Ne pas masquer une piste non reproduite par une affirmation de correction.
6. Suite actuelle et nouvelles régressions réussies ; preuves visibles locales.
7. Installer la Release signée avec le certificat existant, redémarrer proprement,
   contrôler identité, santé, configuration et appartenances des fenêtres communes.

Base : UUID 3DCADF8B-8F1B-3C30-918F-E039AC922EC6, 265 empreintes Sources/Tests.
Revue source : session-2026-10-15-placements-01 dans le worktree 036.
