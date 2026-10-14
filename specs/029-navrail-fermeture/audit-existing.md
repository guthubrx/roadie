# Audit de l'existant — session 029

## Réutilisé

- notification `AXUIElementDestroyed` par fenêtre ;
- tombstone `destroyedWindowIDs` ;
- ordonnanceur événementiel à 15 ms ;
- mutation atomique du `StageStore` ;
- watcher du fichier des stages à 20 ms ;
- filtrage automatique des stages sans membre représenté.

## Écart fonctionnel

Le tombstone nettoie l'arbre BSP mais pas le membre persistant. La grâce
visuelle confond donc une fermeture certaine avec une absence temporaire.

Une terminaison complète d'application peut produire les mêmes destructions AX.
Le correctif ne supprime donc pas l'appartenance. Il ajoute un état visuel
persisté et réversible. Le rattachement SPEC-016 reste possible après relance.

## Risques

- Réutilisation rapide d'un identifiant CoreGraphics : la présence vivante doit
  toujours empêcher le retrait.
- Liste CoreGraphics encore en retard au premier passage : une reprise courte,
  bornée et pilotée par échéance est nécessaire.
- Preuve périmée : elle ne doit jamais supprimer une fenêtre masquée plus tard.
- Arrêt de Roadie : il ne doit pas être interprété comme la fermeture de toutes
  les applications.
- Deux notifications pour la même fenêtre : le retrait doit rester idempotent.
- Stages plein écran ou sur un autre Space : leur absence non confirmée doit
  garder la grâce actuelle.

## Conclusion

Le correctif tient dans les contrats existants. Aucune migration, nouvelle API,
nouveau daemon ou nouvelle dépendance n'est justifié.
