# Modèle de Données : Performance ressentie Roadie

## InteractionCritique

Représente une action utilisateur dont la latence est immédiatement ressentie.

**Champs**:

- `id`: identifiant unique de l'interaction.
- `type`: catégorie (`stage_switch`, `desktop_switch`, `display_focus`, `directional_focus`, `alt_tab_activation`, `rail_action`, `layout_tick`).
- `startedAt`: date de début.
- `completedAt`: date de fin si terminée.
- `result`: résultat (`success`, `partial`, `no_op`, `failed`).
- `targetContext`: contexte que l'utilisateur voulait atteindre.
- `source`: origine de l'action (`cli`, `btt`, `rail`, `focus_observer`, `maintainer`, `system`).

**Relations**:

- Possède une ou plusieurs `PerformanceStep`.
- Produit zéro ou un `PerformanceThresholdBreach`.

**Règles de validation**:

- `completedAt` ne peut pas précéder `startedAt`.
- `type` doit appartenir au catalogue documenté.
- Une interaction critique terminée doit avoir un `result`.

## PerformanceStep

Mesure une étape d'une interaction critique.

**Champs**:

- `name`: nom stable (`snapshot`, `state_update`, `hide_previous`, `restore_target`, `layout_apply`, `focus`, `secondary_work`, `total`).
- `startedAt`: date de début de l'étape.
- `durationMs`: durée en millisecondes.
- `count`: nombre d'éléments traités si applicable.
- `status`: résultat de l'étape (`success`, `skipped`, `failed`).

**Relations**:

- Appartient à une `InteractionCritique`.

**Règles de validation**:

- `durationMs` doit être positif ou nul.
- `name` doit appartenir au vocabulaire d'étapes.
- Une étape `total` doit couvrir au moins la durée des étapes principales connues.

## PerformanceSnapshot

Résumé court des interactions récentes, exposé à l'utilisateur.

**Champs**:

- `generatedAt`: date du résumé.
- `recentInteractions`: dernières interactions critiques retenues.
- `summaryByType`: agrégats par type d'interaction.
- `slowestRecent`: interactions les plus lentes dans la fenêtre récente.
- `thresholdBreaches`: dépassements récents.

**Relations**:

- Agrège plusieurs `InteractionCritique`.

**Règles de validation**:

- L'historique doit rester borné pour ne pas grossir indéfiniment.
- Les agrégats doivent ignorer les interactions incomplètes ou clairement corrompues.

## PerformanceThreshold

Définit un seuil de confort utilisateur.

**Champs**:

- `interactionType`: type concerné.
- `limitMs`: durée limite en millisecondes.
- `percentileTarget`: percentile visé si le seuil s'applique à un agrégat.
- `enabled`: activation du seuil.

**Règles de validation**:

- `limitMs` doit être strictement positif.
- Les seuils par défaut doivent couvrir stage, desktop et AltTab.

## PerformanceThresholdBreach

Signale une interaction lente.

**Champs**:

- `interactionID`: interaction concernée.
- `interactionType`: type concerné.
- `durationMs`: durée observée.
- `limitMs`: seuil dépassé.
- `dominantStep`: étape principale responsable si identifiable.
- `message`: description actionnable.

**Relations**:

- Référence une `InteractionCritique`.

**Règles de validation**:

- `durationMs` doit être supérieur à `limitMs`.
- `dominantStep` doit être absent si aucune étape dominante ne peut être identifiée honnêtement.

## TargetContext

Décrit le contexte utilisateur attendu à la fin d'une interaction.

**Champs**:

- `displayID`: écran cible si connu.
- `desktopID`: desktop Roadie cible si connu.
- `stageID`: stage cible si connu.
- `windowID`: fenêtre cible si connue.
- `sourceDisplayID`: écran de départ si pertinent.
- `sourceDesktopID`: desktop de départ si pertinent.
- `sourceStageID`: stage de départ si pertinent.

**Règles de validation**:

- Une interaction stage doit inclure au moins `displayID` et `stageID`.
- Une interaction desktop doit inclure au moins `displayID` et `desktopID`.
- Une interaction AltTab doit inclure `windowID` quand la fenêtre est connue.

## State Transitions

```text
InteractionCritique créée
  -> étapes ajoutées pendant l'action
  -> interaction terminée avec result
  -> seuils évalués
  -> éventuel PerformanceThresholdBreach publié
  -> interaction retenue dans PerformanceSnapshot jusqu'à expiration de l'historique court
```

```text
AltTab focus observé
  -> TargetContext résolu depuis la fenêtre
  -> événements rapprochés regroupés si même intention
  -> stage/desktop cible activé
  -> interaction terminée ou échouée avec diagnostic
```
