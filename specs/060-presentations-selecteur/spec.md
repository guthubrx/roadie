# Feature Specification: Présentations du sélecteur

## Fiche Synthèse
Spec: 060-presentations-selecteur
Titre: Cinq présentations du sélecteur par bureau et stage
Statut: Implemented
Priorité: P1
Tâches: 5/5 (100%)
Tests: 1893/1893 (100%)

Demande validée le 23 octobre 2026 : « fais les toutes avec choix par menu parametres ».
Branche : `session-060-presentations-selecteur`.

## Résultat attendu
- Dans Réglages Roadie > Sélecteur, choisir l'organisation commune : grille actuelle,
  colonnes par stage, bureaux en onglets, navigation hiérarchique, grille par sections,
  ou vue d'ensemble des bureaux. Choix indépendant des vignettes/icônes/liste.
- Dans Apparence de chaque profil, choisir une organisation propre ou suivre le
  réglage commun. Les modifications sont appliquées au sélecteur ouvert.
- Conserver le grand aperçu, la recherche, les actions et les comportements au
  relâchement. Une recherche examine toutes les fenêtres autorisées par le profil.
- Les fenêtres restent identifiées par WindowID. Deux stages de même nom sur des
  écrans ou bureaux distincts ne fusionnent jamais. Aucun changement d'affectation.
- Tab/Cmd+Tab garde le parcours global existant. Le bureau et la stage affichés
  suivent la sélection. Flèches, survol et clic fonctionnent dans les cinq vues.
- Onglets et arbre permettent de choisir le groupe. Les autres vues montrent tous
  les groupes. Les colonnes passent à la ligne si nécessaire. La vue d'ensemble
  reprend les positions relatives des fenêtres quand leurs cadres sont utilisables.
- Écrans petits, groupes vides après filtrage, homonymes, fenêtres sans scope,
  grandes polices et fenêtres réduites restent utilisables sans débordement.
- Sans nouvelle clé, conserver la grille actuelle et ne pas réécrire le fichier.

## Validation
Tests de configuration/persistance, identité des groupes, disposition/limites,
navigation et changement de groupe, recherche inter-bureaux, rechargement immédiat.
Rendus natifs des cinq vues, puis essai de la version installée selon l'accès réel.
Diaporama avec limites explicites ; aucune image de conception utilisée comme preuve.

## Hors périmètre
Aucun nouveau moteur de raccourcis, déplacement de fenêtre, capture AX ou service.
Pas de nouvelle release publique dans cette session.
