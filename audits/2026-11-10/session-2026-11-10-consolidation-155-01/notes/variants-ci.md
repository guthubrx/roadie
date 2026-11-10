# Variante de référence GitHub Actions mobile

Règle : github-actions.mutable-checkout-reference, symbole US8/T031, instance template-checkout.
L'alerte concernait uniquement specs/155-consolidation-projet/gabarits/tests.yml:16.
Le workflow réel était déjà épinglé. Le gabarit et sa recette ont été alignés sur le SHA
11d5960a326750d5838078e36cf38b85af677262, résolu avec git ls-remote actions/checkout refs/tags/v4.
Revue des deux fichiers YAML et de la recette : aucune référence mobile restante pour checkout.
Semgrep révision 1 : exécution complète, 0 candidat. Aucun workflow exécuté.
Correction préventive du matériel de recette, sans changement de comportement Swift.
