# Correction152 — Sens des animations de stage

Statut: In Progress. Priorité:P1. Tâches:2/5.

Le 3 novembre2026, l'utilisateur constate que les fenêtres arrivent de droite, indépendamment du déplacement entre stages. Sens confirmé : remonter vers une stage précédente fait arriver ses fenêtres du bas, avec un mouvement montant ; descendre les fait arriver du haut, avec un mouvement descendant. Les fenêtres quittées sortent dans le même sens que les entrantes.

La position de parking hors écran reste un détail interne : ne jamais l'utiliser comme départ ou destination visible. Une fenêtre encore déclarée visible à cause d'un pixel de parking doit suivre la même règle. L'ordre du rail, y compris le réordonnancement des stages, décide du sens lors d'un saut direct. Les commandes next/prev conservent leur sens au bouclage. Même stage : aucun nouveau sens inventé.

Conserver les durées, courbes, intensités et désactivations réglées dans Roadie. Conserver taille finale, focus, parking sûr multi-écrans, écrivain et annulation de génération existants. Une interruption rapide ne doit pas rejouer une cible périmée. Ne pas ajouter de nouveaux réglages ni changer les préférences macOS.

Validation : test des deux sens, ordre non numérique, bouclage, pixel de parking, animations désactivées et retarget rapide. Essais natifs sur deux fenêtres fictives de deux stages, avant/après, cadres et journaux relevés. Pas de gain de latence ou CPU revendiqué.

Capture temporaire acceptée : le contenu peut rester figé pendant la courte transition. Garder une interaction réactive ; si la préparation tarde, afficher immédiatement la vraie scène. Aucun réglage macOS ne pilote les effets Roadie.
