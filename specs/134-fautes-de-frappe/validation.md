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
