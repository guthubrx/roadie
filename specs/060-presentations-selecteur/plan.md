# Plan 060

1. Réutiliser WindowSwitcherConfig et les surcharges d'apparence des profils.
   Une clé `presentation` porte les six valeurs ; `classic` reste le défaut.
2. Grouper les résultats déjà filtrés par l'identité (écran, bureau, stage),
   jamais par le nom. Conserver l'ordre de première apparition des groupes et
   l'ordre du profil à l'intérieur. Un passage O(n), sans acquisition supplémentaire.
3. Séparer géométrie pure et vues AppKit. Un plan commun fournit cartes, en-têtes,
   panneaux de groupe, navigation et taille du document pour les cinq organisations.
   Les cartes, images et callbacks restent ceux du sélecteur existant.
4. Le panneau conserve uniquement les groupes parcourus et les résultats rendus.
   La sélection globale reste dans le modèle. Un changement via Tab révèle son
   groupe ; un clic sur un groupe sélectionne sa première fenêtre. Recherche et
   rechargement réconcilient les groupes par identité.
5. Géométrie commune pour les aperçus latéraux ou bas, les onglets et l'arbre.
   Défilement borné à l'écran, police existante, navigation spatiale sur cartes.
6. Tests ciblés avant suite séquentielle Swift, jobs=2. Revue indépendante après
   implémentation. Pas de benchmark sur la machine chargée.
7. Documentation FR/EN, preuves natives et réelles distinctes. Installation signée
   avec certificat existant, restart et santé. Conserver configuration/raccourcis.

## Choix écartés
Ne pas dupliquer cinq panneaux complets ni ajouter une UI web. Ne pas transformer
le regroupement visuel en nouveau filtre persistant. Ces choix préserveraient mal
les actions, la sélection globale et les surcharges existantes.
