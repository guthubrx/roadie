# Vérification ciblée — session 024

Les trois HIGH PERF-010, PERF-011 et PERF-012 sont résolus.
La revue indépendante est favorable ; aucun défaut bloquant trouvé sur ce diff.
La suite complète passe : 1 354 tests Swift dans 143 suites et 26 tests des scripts.

À 400 fenêtres, médianes debug : appartenances 15,399 → 0,443 ms ;
validations 6 622,379 → 17,085 ms ; homonymes ambigus 117,742 → 16,076 ms ;
candidats déjà adoptés 32,862 → 2,323 ms. Aucun gain revendiqué pour l'état sans orphelin.

Le rapprochement a été comparé au vrai code précédent. Les résultats restent identiques,
y compris seuils, ambiguïtés, PID vivant, groupes, focus et candidats répétés.
L'index est créé à la demande et disparaît à la fin de la passe. Son pire cas n'est pas linéaire.

Ce contrôle ne remplace pas un audit complet. Les six MEDIUM et six LOW de l'audit
précédent restent ouverts. Les mesures ne certifient ni latence UI ni mémoire.
Le rapport historique demeure inchangé. Voir verification.json et les mesures de la spec 024.
