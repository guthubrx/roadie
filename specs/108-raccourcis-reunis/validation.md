# Validation 108

- `Spec108ShortcutsTests` (8) : défauts et lecture des touches, `[[shortcuts]]` accepté par le validateur,
  arguments entre guillemets, table des touches et état de la sélection, plan Carbon (doublons, invalides),
  lecture d'une réponse BTT (dossier, commande, désactivé, sélecteur exclu), conflits et pause par touche
  physique, gestionnaire de chaque ligne, catégorie Raccourcis et capture d'une touche seule.
- Tests mis à jour : `SettingsCatalogTests` (231 réglages simples, deux listes de plus, catégorie de la recherche),
  `Spec058SettingsLayoutTests` (gestionnaire du sélecteur réglé dans Raccourcis).
- Lecture réelle de BTT (lecture seule) : 119 raccourcis globaux, 72 commandes `roadie`, conflits ⌘L, ⌥↑ et ⌥↓.
- Rendu hors écran de la catégorie sur ces données : colonnes alignées, dossiers dans l'ordre.
- Suite complète : 2 170 tests / 308 suites.
- Non vérifié en réel : appui sur ⌘L barre ouverte avec la pause, bascule d'une commande vers Roadie
  (frappes simulées refusées à l'agent). Essai utilisateur demandé.
