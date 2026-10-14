# Spécification 025 — Lisibilité des réglages

**Branche** : `session-025-settings-readability` | **Date** : 2026-10-14
**Statut** : implémentée et validée | **Validation utilisateur** : « go », puis « Oui, cela fonctionne » sur la version installée

## Besoin et scénarios

- US1 : lire les noms, explications, valeurs et erreurs sans texte minuscule.
- US2 : choisir un mode de tuilage à partir de son nom français et reconnaître son nom technique.
- US3 : ouvrir les réglages avec `split_policy = "balanced"` et voir la valeur sélectionnée.
- US4 : régler indépendamment les polices des paramètres, du rail, des lettres, de la grille et de la recherche ; voir le résultat immédiatement.

## Exigences

- FR-001 : dans les paramètres, tailles indépendantes des textes, explications et titres ; défauts 16, 14 et 22 points.
- FR-002 : fenêtre initiale plus grande, redimensionnable et centrée dans la zone disponible.
- FR-003 : placer les contrôles sous les explications pour éviter leur compression.
- FR-004 : conserver les valeurs techniques des menus et les alias existants.
- FR-005 : ajouter `balanced` aux choix du découpage sans changer sa signification ni le défaut `largest_dim`.
- FR-006 : ouvrir ou lire les réglages ne modifie pas le fichier utilisateur.
- FR-007 : les réglages de police sont persistés dans TOML, recherchables et modifiables avec les contrôles existants et des curseurs.
- FR-008 : les polices du rail, des lettres, de la grille, des étiquettes de recherche, de la saisie et des suggestions restent indépendantes.
- FR-009 : curseur, pas à pas et saisie d'une taille valide changent le rendu immédiatement ; les sessions déjà visibles sont mises à jour sans redémarrage.

## Validation

Tests du catalogue et du modèle : lecture de `balanced`/`mutableBsp`, changements aller-retour,
réinitialisation et libellés. Compilation et suite Swift. Installation avec la signature stable.
Vérification visuelle utilisateur sur la version installée, si la capture reste indisponible.

## Hors périmètre

Moteur de tuilage, nouvelle dépendance et nouvelle release. Les infobulles gérées par macOS conservent la police du système.
