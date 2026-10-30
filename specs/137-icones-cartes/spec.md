# Session 137 - Icônes des cartes du sélecteur

**Date** : 30 octobre 2026 · **Branche** : `137-icones-cartes` (sur 136, 135, non fusionnées)

Au survol d'une carte de ⌘Tab ou de ⌥Tab, deux icônes en haut à droite (choix de l'utilisateur) :

- **FR-001** ×, fenêtre : ferme la fenêtre (action `close` existante) ; zone : retire la zone et sa photo.
- **FR-002** Sens interdit, fenêtre : l'application rejoint `[switcher] excluded_bundles` ; zone : elle rejoint
  `[switcher] zone_click_excluded_bundles` (nouvelle liste), ses zones de clics partent, ses clics n'en créent plus ;
  la recherche à l'écran crée toujours des zones. Les deux listes s'éditent dans Paramètres > Sélecteur (annulable).
- **FR-003** Icônes visibles au survol seulement ; un clic sur une icône ne valide pas la carte ; la liste est relue.
