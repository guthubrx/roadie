# Spécification 027 — Réglages complets et application immédiate

**Branche** : `session-027-settings-complete` | **Date** : 2026-10-14
**Statut** : clôturée, installée et validée | **Validation** : « Go, avec des agents », puis « Oui, tout fonctionne »

## Besoin

Changer les réglages depuis la fenêtre et voir le résultat dès la modification.
Ne réserver les outils avancés qu'aux configurations de grande complexité.
Choisir la famille de police de Caps+F, en plus des tailles existantes.

## Scénarios et exigences

- US1 / FR-001 : tout champ scalaire applique sa valeur valide pendant la saisie,
  sans Retour ni perte du focus. Les brouillons incomplets restent saisissables.
  Une valeur invalide ne remplace pas la dernière valeur valide.
- FR-002 : une modification de tuilage provoque son application effective aux
  fenêtres concernées, sans redémarrage ni action manuelle. Les changements
  de police ne doivent pas déclencher un tuilage superflu.
- FR-003 : afficher les exceptions par écran et leur priorité sur les marges
  générales, pour que le résultat soit compréhensible.
- US2 / FR-004 : les douze entrées actuellement en lecture seule sont modifiables
  depuis la fenêtre. Les listes simples et les côtés utilisent des contrôles normaux.
- FR-005 : éditeurs structurés pour les marges par écran, noms des stages,
  couleurs par stage et règles de fenêtres ; ajout, modification, suppression,
  validations et rétablissement. Pas de texte de configuration imposé pour ces cas courants.
- FR-006 : les structures réellement complexes, notamment les commandes libres
  des signaux, disposent d'un éditeur avancé intégré. Les renvois au fichier externe
  ne doivent pas être le parcours normal.
- FR-007 : conserver les commentaires, valeurs inconnues et autres blocs lors
  d'une écriture ; sauvegarde, validation et remplacement atomique maintenus.
- US3 / FR-008 : familles de police indépendantes pour la saisie et les suggestions
  de Caps+F, choisies parmi les polices installées. Les tailles existantes restent indépendantes.
- FR-009 : famille et taille s'appliquent immédiatement aux sessions ouvertes,
  sans perte de saisie ; police système de secours si une famille n'est pas disponible.
- FR-010 : l'éditeur avancé permet de corriger une configuration invalide dans
  la fenêtre ; une correction invalide n'est jamais écrite ni appliquée.

## Inventaire des douze entrées

| Réglage | Éditeur attendu |
|---|---|
| tiling.smart_gaps_solo_sides | Cases pour les quatre côtés |
| tiling.allowed_subroles | Liste de textes |
| tiling.display_overrides | Marges facultatives par écran |
| width_adjustment.presets | Liste de nombres |
| stage_manager.workspaces | Identifiant et nom de stage |
| fx.borders.stage_overrides | Stage et couleur |
| fx.rail.preview.stage_overrides | Stage et couleur |
| experimental.app_targets.include_roles | Liste de textes |
| experimental.app_targets.additional_boost_bundle_ids | Liste d'applications |
| exclusions.floating_bundles | Liste d'applications |
| rules | Critères et actions de chaque règle |
| signals.hooks | Éditeur avancé intégré |

## Validation

Tests de saisie sans validation manuelle, brouillons, tableaux et sous-tables,
commentaires, clés inconnues, conflit d'écriture, reset, notification et retuilage.
Tests des familles de police et du secours. Rendus hors écran puis essai utilisateur
des marges, éditeurs et polices sur la version installée.

## Hors périmètre

Nouvelle dépendance, migration des données utilisateur et nouvelle release.
Les textes gérés par macOS gardent leur police système.
