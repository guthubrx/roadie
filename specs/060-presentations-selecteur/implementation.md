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
Documentation FR/EN et diaporama terminés avec les limites du parcours installé.
La demande de revue a été refusée à l'admission par Bridget ; aucune revue
indépendante n'a démarré. Relecture propre et validation poursuivies.
Complément : libellés générés alignés sur ceux du rail, calculés une fois par
inventaire. Suite finale : 1 893 tests/234 suites réussis en 58,192 s.
Build Release final installé, signature/configuration conservées, PID 11924,
santé 5/5. Ouverture du sélecteur installé observée, puis annulation sans activation.
Parcours des paramètres non capturé : deux saisies automatisées ont fermé la barre.
Voir validation.md pour les faits, limites et identifiants exacts.
