# Quickstart : valider la boîte de commandes et la fenêtre de réglages

Prérequis : Roadie installé et lancé (`make install`, signature `roadied-cert`), la hyper key envoie Cmd + Option + Ctrl, au moins deux stages, si possible deux écrans.

## 1. Boîte de commandes

1. Caps Lock + F. La barre de recherche apparaît. Taper `/` : la liste des commandes s'affiche au-dessus.
2. Taper `/st` puis Tab : la saisie devient `/stage `. La liste montre les stages.
3. `/stage 2` puis Retour : le stage 2 devient visible, la boîte se ferme.
4. `/screen droite` puis Retour : le focus passe à l'écran de droite (avec deux écrans).
5. `/swap droite` : la fenêtre active s'inverse avec sa voisine de droite.
6. `/zzz` puis Retour : message d'erreur, boîte ouverte, commande la plus proche proposée.
7. Effacer le `/` : retour au mode recherche de texte. Taper « subscr » : comportement identique à la SPEC-021.
8. `/doctor` puis Retour : le résultat s'affiche dans la boîte (12 lignes au plus).
9. Rouvrir la boîte, `/` puis Flèche haut : la dernière commande revient.

## 2. Bookmarks, grille

1. Sur une fenêtre : `/bm set a`. Changer de fenêtre. `/bm a` : le focus revient.
2. `/grid` : la boîte se ferme, la grille de l'écran s'ouvre. `/grid fenêtre` : la grille de la fenêtre.
3. `/letters` : le mode lettres s'ouvre.

## 3. Fenêtre de réglages

1. `/settings` puis Retour : la fenêtre s'ouvre en moins de 1 s, sur Général.
2. Cliquer « Grille ». Passer l'opacité du remplissage (`overlay_fill_opacity`) de 0,10 à 0,40. Fermer, lancer `/grid` : le fond de la grille est nettement plus visible, sans redémarrage.
3. Dans la recherche, taper « bordure » : les réglages des bordures de toutes les catégories apparaissent.
4. Vérifier que la fenêtre n'est pas tuilée : `roadie windows list` ne la liste pas, ou la liste en flottant ; les autres fenêtres ne bougent pas à son ouverture.
5. `/settings` une seconde fois : la même fenêtre passe devant.
6. Éditer `roadies.toml` à la main (`overlay_fill_opacity = 0.5`) : la fenêtre affiche 0.5 sans être rouverte.
7. Échap puis Cmd + W : la fenêtre se ferme.

## 4. `/set`

1. `/set target_grid.overlay_fill_opacity 0.4` puis Retour : le fond de la grille est plus visible.
2. `/set target_grid.overlay_fill_opacity` : « target_grid.overlay_fill_opacity = 0.4 (défaut 0.1, de 0 à 1) ».
3. `/set target_grid.overlay_fill_opacity 5` : refus, fichier intact.
4. `/set target_grid.overlay_fill_opacity défaut` : retour à 0.1.
5. Comparer les commentaires du fichier avant/après : `diff` ne montre que la ligne `overlay_fill_opacity`.
6. Cas du nombre de lignes : `/set target_grid.rows 4` est refusé avec les 9 `hint_characters` par défaut (12 cases demandent 12 lettres) ; Roadie dit pourquoi et le fichier reste intact. Après `/set target_grid.hint_characters azeqsdwxcrtyuiop`, `/set target_grid.rows 4` est accepté.

## 5. Taille des étiquettes

1. Mesure : lancer le mode lettres (double Cmd gauche), noter la taille des étiquettes.
2. `/set target_mode.label_font_size 20`, relancer : les étiquettes sont plus grosses et ne se superposent pas plus qu'avant.
3. `/set target_grid.label_font_size 20`, `/grid` : les étiquettes de la grille grandissent.
4. `/set target_mode.label_font_size défaut` : retour à l'aspect d'origine.

## 6. Tests automatiques

```bash
./scripts/test
```

Attendu : tous les tests passent, dont `SlashCommandCatalogTests`, `SlashCommandModelTests`, `SlashCommandRunnerTests`, `ConfigFileEditorTests`, `SettingsCatalogTests`, `TargetOverlayStyleTests`, et les tests existants de recherche.
