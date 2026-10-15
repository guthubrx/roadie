# Plan de correction

1. Reproduire une fenêtre connue sur un écran absent avec un nouveau LayoutMaintainer.
2. Réutiliser la garde de stabilisation existante avant tout parking automatique.
3. Lorsque le relevé contient une fenêtre candidate sans scope, appliquer le parking
   léger existant avec ce relevé. Recalculer l'état sur le même relevé en production.
4. Conserver le suivi normal des notifications d'écran et le retour des stages.
5. Vérifier les arrivées retardées, l'absence de permission, les relevés vides,
   l'idempotence et le retour de l'écran, puis installer et redémarrer.

Pas de nouveau contrôleur, de nouveau moteur ou de changement de raccourci.
La récupération ne purge pas l'état historique et ne sélectionne pas un autre groupe.
