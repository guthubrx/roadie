# Spécification 025 — Lisibilité des réglages

**Branche** : `session-025-settings-readability` | **Date** : 2026-10-14
**Statut** : en cours | **Validation utilisateur** : « go »

## Besoin et scénarios

- US1 : lire les noms, explications, valeurs et erreurs sans texte minuscule.
- US2 : choisir un mode de tuilage à partir de son nom français et reconnaître son nom technique.
- US3 : ouvrir les réglages avec `split_policy = "balanced"` et voir la valeur sélectionnée.

## Exigences

- FR-001 : textes principaux de 16 points, explications et messages de 14 points, titres de 22 points.
- FR-002 : fenêtre initiale plus grande, redimensionnable et centrée dans la zone disponible.
- FR-003 : placer les contrôles sous les explications pour éviter leur compression.
- FR-004 : conserver les valeurs techniques des menus et les alias existants.
- FR-005 : ajouter `balanced` aux choix du découpage sans changer sa signification ni le défaut `largest_dim`.
- FR-006 : ouvrir ou lire les réglages ne modifie pas le fichier utilisateur.

## Validation

Tests du catalogue et du modèle : lecture de `balanced`/`mutableBsp`, changements aller-retour,
réinitialisation et libellés. Compilation et suite Swift. Installation avec la signature stable.
Vérification visuelle utilisateur sur la version installée, si la capture reste indisponible.

## Hors périmètre

Moteur de tuilage, nouveaux réglages, changement de format, nouvelle dépendance et nouvelle release.
