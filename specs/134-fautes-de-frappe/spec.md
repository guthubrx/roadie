# Session 134 - Fautes de frappe rattrapées

**Date** : 30 octobre 2026 · **Branche** : `134-fautes-de-frappe` (sur 133, 132 et 131, non fusionnées)

## Besoin

La recherche à l'écran exige le texte exact ; le lanceur pardonne les lettres oubliées et les initiales, mais
pas une lettre fausse, en trop ou inversée. L'utilisateur veut un peu de tolérance, d'abord à l'écran, puis
dans le lanceur, avec la règle validée : une frappe exacte passe toujours devant une frappe rattrapée.

## Exigences

- **FR-001** Une faute : lettre oubliée, en trop, remplacée, ou deux lettres voisines inversées (distance de
  Damerau-Levenshtein restreinte), sur un passage quelconque du texte. Aucune sous 4 lettres, une de 4 à 7,
  deux à partir de 8, plafonnées par `typo_max_errors` (0 à 2, défaut 2 ; 0 coupe), Paramètres > Recherche.
- **FR-002** Recherche à l'écran : les fautes ne sont rattrapées que si aucune correspondance exacte n'existe ;
  moins de fautes d'abord ; la barre affiche « ≈ approché ».
- **FR-003** Lanceur : section « Vouliez-vous dire », en dernier, seulement sous trois correspondances
  exactes ; applications (noms et autres noms) et cibles rattrapées par le mode recherche ; une ligne
  rattrapée n'est la ligne choisie que sans aucune correspondance exacte. Les fichiers (Spotlight) ne sont pas
  concernés.

## Critères

- **SC-001** « enregsitrer » trouve « Enregistrer » à l'écran ; « envo » reste exact.
- **SC-002** « fierfox » propose Firefox dans « Vouliez-vous dire » ; « fire » n'affiche pas la section.
