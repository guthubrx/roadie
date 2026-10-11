# Validation manuelle : Tiling réactif façon yabai

## Préparation

1. Installer : `ROADIE_CODESIGN_IDENTITY="roadied-cert" make install && make restart`.
2. Vérifier : `roadie doctor`. Il doit afficher `status=ok` et `accessibilityTrusted=true`.
3. Noter l'heure de départ : `START=$(date -u +%FT%TZ)`.
4. Pendant les essais, n'ouvrir aucune autre application. Faire 5 essais par scénario, espacés d'au moins 10 s.

## Scénarios

| # | Action | Résultat attendu |
|---|---|---|
| 1 | Stage de 2 fenêtres, ouvrir une 3e (Cmd-N dans un terminal) | La fenêtre active est coupée en deux, les autres ne bougent pas, un seul mouvement |
| 2 | Fermer une fenêtre (Cmd-W) | Sa voisine directe prend la place, en un mouvement |
| 3 | Mettre une fenêtre en plein écran natif (Ctrl-Cmd-F), attendre 5 s, en sortir | La fenêtre reprend sa place juste après l'animation, sans attente ni correction |
| 4 | Changer de stage 5 fois avec le raccourci | Fenêtres à leur place en un mouvement, sans correction après coup |
| 5 | Glisser une fenêtre au centre d'une autre, puis sur le bord gauche d'une autre | Échange au centre, insertion à gauche sur le bord |
| 6 | Redimensionner une fenêtre à la souris et relâcher | La voisine s'ajuste une fois ; rien ne bouge ensuite |
| 7 | Ne rien faire pendant 60 s | Aucun placement dans le journal |
| 8 | `roadie move left`, `roadie warp right`, `roadie resize left`, `roadie balance`, `roadie layout toggle-split` | Effet immédiat, en une passe |
| 9 | Ouvrir un terminal dans une case trop petite pour sa taille minimale | Au plus 2 écritures pour cette fenêtre, puis plus rien |

## Campagne de charge

- Refaire les scénarios 1, 3 et 4 avec 6 applications ouvertes (navigateur, terminal, T3 Code, Finder, éditeur, lecteur).
- Refaire le scénario 1 pendant qu'une application est lente : par exemple une application en train d'indexer, ou suspendue avec `kill -STOP` sur un processus de test, jamais Firefox, puis `kill -CONT`. Attendu : Roadie ne gèle pas, et la mise de côté de 5 s s'applique.

## Mesure

```bash
scripts/measure-layout-reactivity --since "$START"
```

À comparer avec la référence de `research.md` :
- temps jusqu'à stabilité au p90 inférieur à 150 ms (SC-001) ;
- une passe dans au moins 95 % des épisodes ;
- aucun `layout_manual_gesture` sans geste réel (SC-004).
