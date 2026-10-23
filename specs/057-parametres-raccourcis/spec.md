# Session 057 - Paramètres structurés et raccourcis directs
Statut: Implémentée ; preuve graphique partielle documentée dans validation.md
Priorité: P1
Validation: « mais ouiiiiii go avance », 23 octobre 2026.
Estimation: 4 à 6 heures.
## Objectif
Conserver la navigation gauche et réorganiser toutes les pages en sections cohérentes. Profils du sélecteur lisibles et modifiables directement; gestionnaire Roadie/BTT explicite; combinaison enregistrée par appui physique. Trois modes au relâchement, recherche/actions contextuelles. Quatre flèches géométriques, survol sélectionne et clic valide.
## Contraintes
Réutiliser SettingsService/SettingsCollectionCodec et les services existants; aucune nouvelle dépendance. Préserver valeurs, polices, CLI, configuration inconnue et réglages existants. Application immédiate des valeurs valides. Aucun raccourci BTT tiers retiré. Échec de liaison visible et ancienne configuration conservée. Un seul gestionnaire actif par profil. Tests et installation Mac, certificat conservé.
## Acceptation
- Toutes les entrées du catalogue figurent exactement une fois dans une section.
- Les profils s'ajoutent, se dupliquent, se renomment et se retirent sans exposer leurs identifiants.
- Enregistrement des touches, Échap annule, combinaison affichée en symboles; collisions connues visibles.
- Roadie et BTT déclenchent le bon profil; changement sûr sans double action, sans supprimer un raccourci inconnu.
- Relâchement: focus / maintien / recherche distincts; apparence du champ et actions cohérente.
- Flèches, survol puis clavier et clavier puis souris; dernière ligne incomplète, défilement et saisie IME préservés.
- Réglages, docs FR/EN et reçu de validation; revue indépendante si disponible; build/install, santé et essai réel.
## Références
Proposition et maquette: docs/analyses/2026-10-23-refonte-parametres.*
Parité AltTab: docs/analyses/2026-10-23-parite-alttab.*
Les autres écarts restent dans ce rapport; ils ne sont pas annoncés livrés par la refonte.

