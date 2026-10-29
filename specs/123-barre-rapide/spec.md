# Session 123 : barre de lancement rapide sous forte charge

## Besoin

Sous forte charge (charge système de 18 à 52 sur 16 cœurs), la barre mettait du temps à s'afficher et la frappe
saccadait. L'utilisateur veut une barre « hyper snappy », en étudiant toutes les pistes avant de réduire ce qui est
affiché. Signalement ajouté pendant la session : un document ouvert (« Suivi commandé Maya.xlsx ») apparaissait, puis
était remplacé une à deux secondes plus tard par d'autres fichiers.

## Règle

- Mesurer chaque ouverture : événement `launcher.timing` dans `~/.roadies/events.jsonl`, sans saisie ni titre
  (attente de la touche, premier dessin, fil principal libre, arrivée des fichiers, plus long blocage, dessins).
- Rien de coûteux sur le fil principal : textes de recherche préparés une fois (historique, signets), icônes et
  vignettes réduites en fond à la taille exacte, Spotlight interrogé en fond (`MDQuery`) avec un délai de 120 ms.
- Les documents déjà ouverts s'affichent tout de suite : liste locale des fichiers ouverts (10 ans, cache de
  5 minutes), puis documents et onglets de l'ouverture précédente (moins de 60 s).
- Un fichier déjà ouvert reste devant un fichier jamais ouvert que Spotlight ajoute ensuite. Les choix appris passent
  avant ; entre fichiers jamais ouverts, la correspondance du nom décide.
- Aucune réduction du nombre de résultats affichés.

Décision : docs/decisions/021-fichiers-ouverts-avant-spotlight.md.
