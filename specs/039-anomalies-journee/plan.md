# Plan

1. Sauvegarder journaux, état et configuration hors Git ; relever distribution des délais et piles runtime.
2. Corriger la validité du relevé partagé : compter le délai de réutilisation depuis la fin de production ; conserver les invalidations explicites et les plafonds existants.
3. Éviter le parcours des panneaux attachés si tous les identifiants CG candidats de cette application sont déjà résolus par les fenêtres AX. Conserver le parcours complet pour les identifiants manquants et les autres appelants.
4. Analyser les gestes et échecs de la journée. Ne pas modifier un comportement uniquement parce qu'un événement porte le mot failed/reverted.
5. Tests ciblés puis suite complète, revue indépendante demandée, compilation et installation. Comparaison runtime dans les mêmes conditions, parcours réel si accessible.

Réutilisation : SnapshotService, AXApplicationWindows, harnais existants. Aucun nouveau cache durable ni dépendance. Complexité O(n) pour regrouper les identités CG ; parcours AX existant conservé uniquement si nécessaire.

## Compléments après observations

- Le rail et le menu lisent NSEvent.mouseLocation lors du traitement, parfois différé. Lire les coordonnées immuables de CGEvent et les convertir par RoadieScreenCoordinate. Le survol périodique continue à lire la souris réelle.
- Le tick date l'expiration du geste après le scan AX. Accepter un scan commencé avant l'échéance, sans prolonger une attente commencée trop tard ; tester première observation et poll différé, gardes et identités inchangées.
- daemon health exécuté depuis la CLI non autorisée produit self-test=false, tandis que query health exécuté dans le daemon renvoie quatre OK. Router seulement daemon health sur le canal existant. Aucun réglage de permissions.
