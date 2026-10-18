# Session 048 - Consommation au repos

Date : 18 octobre 2026. Pipeline `/my.specify-all 1 a 4`. Specs : specs/048-*/.

Constats CRITICAL de l'audit performance du 15 octobre : relevés des lecteurs réutilisés
tant qu'aucun changement n'est signalé (ADR 015), fenêtres ScreenCaptureKit mémorisées,
statut d'enregistrement mémorisé, vignettes mises à jour en place.
Mesure au repos : 11,45 % puis 2,34 % d'un cœur (-80 %). 1 721 tests.
Audit V15 inconclusive (historique ciblé hors adaptateur, sans fuite, option A).

Détails : validation.md de la spec.
