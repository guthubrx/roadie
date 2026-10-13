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
2. Cliquer « Grille ». Passer `rows` de 3 à 4. Fermer, lancer `/grid` : 4 lignes, sans redémarrage.
3. Dans la recherche, taper « bordure » : les réglages des bordures de toutes les catégories apparaissent.
4. Vérifier que la fenêtre n'est pas tuilée : `roadie windows list` ne la liste pas, ou la liste en flottant ; les autres fenêtres ne bougent pas à son ouverture.
5. `/settings` une seconde fois : la même fenêtre passe devant.
6. Éditer `roadies.toml` à la main (`rows = 5`) : la fenêtre affiche 5 sans être rouverte.
7. Échap puis Cmd + W : la fenêtre se ferme.

## 4. `/set`

1. `/set target_grid.rows 4` puis Retour : la grille a 4 lignes.
2. `/set target_grid.rows` : « target_grid.rows = 4 (défaut 3, de 2 à 12) ».
3. `/set target_grid.rows 99` : refus, fichier intact.
4. `/set target_grid.rows défaut` : retour à 3.
5. Comparer les commentaires du fichier avant/après : `diff` ne montre que la ligne `rows`.

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
