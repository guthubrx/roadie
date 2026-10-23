# 016 - Paramètres organisés et gestionnaires de raccourcis
Date: 2026-10-23
Statut: Accepté dans la session 057 validée.
## Contexte
Le catalogue et la persistance sont solides, mais la présentation générique ne distingue pas les usages. Les touches externes et internes doivent partager les profils sans double enregistrement.
## Décision
Conserver la source des valeurs et ajouter une partition de présentation pure. Donner un éditeur dédié aux profils, réutilisant le codec. Ajouter un gestionnaire explicite par profil avec inférence des anciennes configurations. La capture native sérialise les touches; BTT reçoit des actions CLI et des UUID propres à Roadie. Le sélecteur navigue par géométrie locale sans nouveau relevé.
## Conséquences
Aucune dépendance ajoutée. Les valeurs inconnues et les protections de concurrence restent actives. La liaison BTT reste une frontière faillible: contrôle, retour arrière et état visible sont requis. Les permissions du daemon sont réutilisées. Les tests purs ne remplacent pas l'essai de touche réel.

