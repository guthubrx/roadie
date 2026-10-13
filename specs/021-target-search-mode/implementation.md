# Journal d'Implémentation - Mode recherche du mode lettres

## Métadonnées
- **Spec** : 021-target-search-mode
- **Branche** : 021-target-search-mode
- **Démarré** : 2026-10-12
- **Terminé** : 2026-10-13

## Livré

| Commit | Contenu |
|--------|---------|
| `7cc889a` | Mode recherche (modèle, barre, raccourci Carbon `search_hotkey`, variantes de clic, `*`, `?`) ; point de clic des feuilles web (`clickFrame`) |
| `6e9f7dc` | Portée `visible_windows` : fenêtres lues en parallèle, occlusion, focaliser puis cliquer, texte des petits conteneurs |
| `6577a80` | Barre immédiate : fenêtres ajoutées au fil de leur lecture, 2 s par fenêtre, étiquettes stables |
| `24420f0` | Aucune étiquette avec une barre vide ; cadres des derniers résultats |
| `888ec19`, `b200168` | Étiquettes d'une lettre (A, S, D…) à 9 résultats ou moins |
| `e934124`, `fe3378c` | Étiquettes de recherche vertes ; cadre épais pour la cible choisie, fin pour les autres |

## Mesures (2026-10-13, 11 fenêtres visibles sur 3 écrans)

Arrivée après Hyper+F : barre et 46 cibles Roadie à 0 ms ; Firefox et Brave 58 ms ;
T3 Code 116 ms (139 cibles) ; Teams 127-247 ms ; Outlook 381 ms (plafond 150) ;
Bluejay 388 ms (41 cibles, parcours complet) ; Finder 2 s (coupé, 109 et 58 cibles).
Avant la barre immédiate, avec l'échéance commune de 700 ms, Bluejay était coupé
quand la machine était chargée (702 ms, 25 cibles au lieu de 41).

## Diagnostics (données observées)

- **Clic sans effet dans l'Historique Bluejay** : le clic visait le centre de la ligne ; seuls
  vignette, titre et auteur ont un `onClick` (`History/index.tsx`). Correctif : premier
  `AXImage`/`AXStaticText` visible (FR-012).
- **« teleoperator » introuvable dans T3 Code** : la ligne de fil (`AXButton` 522 × 114) contient
  ses propres boutons ; la règle « pas de texte pour un conteneur » jetait son texte. Correctif :
  un conteneur garde son texte s'il occupe au plus un quart de la fenêtre.
- **Rectangle vert invisible** : la première correspondance était une conversation Teams sur un
  autre écran. Correctif : écran du pointeur d'abord.
- **Fenêtres `borders`** : cadres sans application comptés comme masquants. Écartés.

## Tests

- Suite complète : 881 tests verts (`swift test`).
- Validé par l'utilisateur : recherche T3 Code et Bluejay, clic dans l'Historique (double
  Commande et Hyper+F), recherche dans une fenêtre non active, étiquettes d'une lettre, cadres et
  étiquettes vertes.
- Non validé à l'écran : Maj-Retour, Cmd-Retour, double Retour, `?` (couverts par les tests du
  modèle).

## Non fait

- Contre-revue de l'implémentation et audit v14 : non lancés à la livraison (demande de
  fusion directe de l'utilisateur).
