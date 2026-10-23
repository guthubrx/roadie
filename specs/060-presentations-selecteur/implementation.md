# Journal 060

## T001 à T003
Implémentées ensemble pour garder un sélecteur compilable et cohérent.
Une propriété d'organisation dans l'apparence existante ; un calcul commun des
groupes et cadres ; un panneau AppKit réutilisant les mêmes cartes et callbacks.
Pas de dépendance supplémentaire, nouvelle capture AX ou mutation de stage.

Validation : 143 tests ciblés puis 1 892 tests Swift/234 suites et 28 scripts.
Les erreurs de compilation intermédiaires (import et macros de tests) ont été
corrigées à partir des sorties du compilateur. Le premier passage exécuté a
relevé un défaut de navigation spatiale et une fixture de profil à actualiser ;
les deux sont corrigés et les suites complètes passent.

## T004 et T005
Revue, preuves du parcours installé et installation restent à terminer.
