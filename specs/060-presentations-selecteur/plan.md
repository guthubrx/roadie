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

## Correction de fidélité après comparaison utilisateur
La capture installée montre un panneau trop vertical, des captures de fenêtres
hautes réduites dans de grands emplacements et un aperçu sans contexte. Reprendre
le socle commun : largeur jusqu'à 1440 points, hauteur liée à la largeur et bornée
à l'écran ; vignettes de groupe uniformes avec recadrage haut et aperçu intégral ;
une seule ligne de titre avec icône, contexte porté par les en-têtes et le détail.
Ajouter un vrai panneau de détail (chemin, titre, image, application et action),
un en-tête et un pied lisibles. Garder les choix de police, les modes d'ouverture,
les raccourcis, les filtres et les identités. Aucun nouveau relevé AX ni capture.
Vérifier les écrans larges/hauts/étroits, les textes longs, les groupes de tailles
différentes, puis comparer les rendus natifs et la fenêtre installée aux maquettes.

## Ajustement à une page après essai utilisateur
Le second retour porte sur onze fenêtres : éviter une grande largeur avec des
captures en bandes et un document coupé. L'auto-dimensionnement cherche un plan
qui tient dans la zone utile. Il essaie au plus trente plans, avec une à trois
colonnes de bureaux pour les sections et des tailles de cartes bornées. Les
stages d'un bureau restent réunies. La police ne rétrécit pas ; toutes les
identités sont conservées. La hauteur du panneau suit le document jusqu'à la
limite de l'écran. Le défilement sert seulement si aucune taille lisible ne tient.
Les tailles manuelles sont respectées si l'auto-dimensionnement est désactivé.
