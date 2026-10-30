# Validation - Session 134

**Date** : 30 octobre 2026

- `scripts/test --no-parallel` : 2 332 tests dans 347 suites réussis (81,9 s).
- Roadie installé (PID 83867, santé 5/5, signature roadied-cert, configuration valide ; réglage absent du
  fichier de l'utilisateur, donc 2 par défaut). Raccourci de la recherche à l'écran toujours enregistré.
- Complexité : à l'écran, O(n) exact puis, seulement sans résultat, O(n × q × t) pour au plus 500 cibles, avec
  une empreinte de lettres qui écarte les textes trop éloignés ; dans le lanceur, le calcul approché ne tourne
  que sous trois correspondances exactes.

## Limites

- Essai au clavier réel laissé à l'utilisateur (frappes simulées refusées sur ce poste ; aucun diaporama).
- Les fichiers trouvés par Spotlight ne bénéficient pas des fautes rattrapées.

## Corrections après essai (30 octobre 2026)

- **Clic refusé** (`focus_failed`) : relevé réel `axFront=17686` (Roadie) `frontmost=7965` (Excel), fenêtre
  active d'Excel correcte. L'accessibilité voit encore la barre au premier plan juste après sa fermeture ;
  désormais, la fenêtre visée active dans son application et en haut de la pile (hors Roadie et liserés
  JankyBorders) suffit (`isFocusReached`, testé avec ces valeurs). Retour confirmé par l'utilisateur dans Excel.
- **Maj + étiquette** : clique la cible (`chooseLabel`) ; la barre transmet au champ les lettres des étiquettes
  affichées, sans quoi la majuscule s'ajoutait à la saisie.
- **Lanceur sans écran** : `launcher_on_screen = false` chez l'utilisateur ; ouverture vérifiée sans
  `targets.app_scan`. `pick_modifier` passé de `shift` à `control` à sa demande (Maj + 3 tape « 3 » en
  AZERTY). macOS garde ⌃1 à ⌃3 pour les bureaux 1 à 3.
- Suite complète : 2 335 tests dans 347 suites réussis. PID 79377, santé 5/5.
