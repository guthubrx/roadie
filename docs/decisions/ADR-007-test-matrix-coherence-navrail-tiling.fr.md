# ADR-007 — Test matrix cohérence navrail × tiling pour validation par agent

🇫🇷 **Français** · 🇬🇧 [English](ADR-007-test-matrix-coherence-navrail-tiling.md)

**Date** : 2026-05-03 | **Statut** : Accepté

## Contexte

Plusieurs bugs successifs sur la cohérence navrail ↔ tiling (SPEC-018 puis SPEC-019) ont révélé que les axes de variation du système (display × desktop × stage × tiler × renderer) se croisent sans qu'il existe de matrice de test exhaustive permettant de valider qu'une régression n'a pas été introduite. Les bugs récents incluent : navrail montrant le même contenu sur 2 écrans, hover effaçant les fenêtres, clic sur stage sans effet, stages fantômes vides, helpers 66×20 polluant les vignettes, double-attribution wid disque, mémoire stage actif perdue au desktop_changed, etc.

Chaque bug a été corrigé empiriquement, mais sans suite de tests systématique chaque fix peut casser un autre cas que personne n'a re-validé. Par ailleurs, certains tests ne sont pas automatisables côté Swift (validation visuelle) et exigent une interaction GUI réelle (hover, drag-drop, resize).

Trois besoins :

1. **Exhaustivité** : couvrir TOUTES les combinatoires des axes du système, pas juste les chemins heureux.
2. **Format consommable par un agent intelligent** : la suite doit être passée par un agent (Claude Code + skill `gui` pour interaction souris) qui exécute chaque test case sans ambiguïté, ni oubli, ni interprétation.
3. **Reporting consolidé** : éviter d'avoir 600 fichiers de résultats — une seule grille avec une ligne par test, indiquant le verdict, l'écart observé, la correction appliquée et le statut post-correction.

## Décision

### Périmètre — axes de combinatoire couverts

| Axe | Valeurs |
|---|---|
| **Displays** | 1 écran (built-in seul) / 2 écrans (built-in + LG externe) / branchement-débranchement à chaud |
| **Desktops** | 1, 2, …, N par display (mode `per_display`) + mode `global` |
| **Stages** | 1 (immortelle) / 2+ par scope (display, desktop) / stage vide / stage avec > maxVisible wids |
| **Tilers** | BSP / Master-Stack |
| **Renderers navrail** | `stacked-previews` (livré) / `icons-only` (livré) / `hero-preview`, `mosaic`, `parallax-45` (TODO SPEC-019 US3-US5) |
| **Types de fenêtres** | tilées / floating / fullscreen natif / minimisées / helpers (66×20) / Electron |

### Périmètre — interactions couvertes

**Observation passive** : à un instant donné, le navrail montre-t-il ce qui est tilé à l'écran ?

**Interactions actives** :
- Clic sur vignette navrail → switch stage
- Drag-drop fenêtre entre 2 vignettes → réassignation cross-stage
- Resize fenêtre tilée (split, ratio)
- Move (focus voisin / swap)
- Cmd+Tab vers fenêtre d'un autre stage / desktop
- Click-to-raise sur fenêtre cachée
- Création / destruction de fenêtre
- Switch desktop (Ctrl+→ / `roadie desktop focus`)
- Switch display (curseur / frontmost)
- Création / suppression / renommage stage (CLI + wallpaper-click + menu contextuel rail)
- Hot-swap de tiler (`roadie tiler bsp` ↔ `master-stack`)
- Hot-swap de renderer (`roadie rail renderer …`)
- Reload daemon
- Branchement / débranchement écran à chaud

### Invariants à vérifier (référencés `INV-N` dans les test cases)

1. **INV-1** Le navrail d'un panel montre les stages de **son** écran (pas un autre)
2. **INV-2** Le contenu visible à l'écran correspond aux wids du stage actif du scope
3. **INV-3** Stage 1 toujours présente sur chaque (display, desktop) — jamais « No stages yet »
4. **INV-4** 1 wid = 1 stage max (pas de double-attribution disque ou mémoire)
5. **INV-5** Pas de helper window 66×20 dans aucune stage
6. **INV-6** Hide/show correct au switch (offscreen `frame.x < -1000` vs on-screen `frame.x ≥ 0`)
7. **INV-7** La mémoire stage actif par (display, desktop) est conservée à l'aller-retour
8. **INV-8** Les actions du panel propagent au scope **du panel**, pas à l'inférence curseur

### Edge cases à inclure systématiquement

- Stage vide (placeholder neutre du renderer)
- Stage avec > maxVisible wids (truncation lisible « +N »)
- Hot reload pendant drag-drop
- App qui crashe alors qu'elle est tilée
- Fullscreen natif macOS
- Wallpaper-click (création stage par clic bureau)
- Curseur traversant entre 2 écrans pendant un switch
- Fenêtre offscreen qui reçoit focus (Cmd+Tab)
- Renderer inconnu dans TOML (faute de frappe) → fallback `stacked-previews` + warn
- Daemon non démarré → rail affiche état offline cohérent

### Combinatoires hors-périmètre (déclarées impossibles ou non testées)

- **Mode `global` × 2 displays** : par construction le rail n'expose qu'un seul panel sur primary → pas de test cross-display.
- **Renderer `mosaic` × stage avec 0 wid** : passé US4 si jamais livré ; aujourd'hui marquer SKIP.
- **Tiler ≠ BSP/Master-Stack** : aucun autre tiler livré, pas de test.
- **Branchement écran sans permissions Accessibility** : prérequis du daemon, hors scope test fonctionnel.
- **Multi-utilisateurs simultanés sur même daemon** : pas supporté (PID lock SPEC-001).

Ces cas DOIVENT figurer en table à part dans le test matrix avec mention `IMPOSSIBLE` ou `OUT_OF_SCOPE` pour traçabilité.

### Ce que la suite ne fait PAS

- Pas de code de test automatisé Swift (XCTest) — la suite est passée manuellement ou par agent + skill `gui`.
- Pas de modification du code source pendant la passe (sauf via section « Fix applied » de la grille, où le commit/fichier corrigé est référencé après coup).
- Pas d'exécution implicite — l'agent qui passe la suite n'enchaîne pas les tests automatiquement, il itère un test à la fois et remplit la grille.

Produire **un seul fichier markdown** : `specs/019-rail-renderers/test-matrix-coherence.md`, structuré en 3 sections :

### Section 1 — En-tête contextuel (lecture par l'agent)

- Objectif de la suite, périmètre, prérequis matériels (1 ou 2 écrans), prérequis logiciels (`cliclick`, daemon vivant, rail vivant, écrans détectés).
- Liste des invariants à vérifier par chaque test (référencés par numéro `INV-N` dans les test cases).
- Glossaire minimal (scope, panel, vignette, frame on-screen, etc.).
- Mode opératoire : ordre des tests, dépendances entre tests, modalité de récupération en cas de crash daemon en cours de suite.

### Section 2 — Test cases

Chaque test case suit un format structuré strict :

```
### TC-XXX — <titre court>

- **Catégorie** : <observation passive | interaction active | edge case | hot-swap>
- **Axes touchés** : display=<…> desktop=<…> stage=<…> tiler=<…> renderer=<…>
- **Invariants vérifiés** : INV-1, INV-3, INV-7
- **Préconditions** :
  - <commande shell vérifiable>
  - <état attendu daemon>
- **Action** :
  - <séquence ordonnée de commandes shell + skill gui>
- **Résultat attendu** :
  - **Daemon state** : <ce que `roadie X` doit retourner>
  - **Tiling visuel** : <ce qui doit être à l'écran après>
  - **Navrail visuel** : <ce qui doit apparaître dans le panel>
- **Notes** : <pièges connus, timing, etc.>
```

Numérotation `TC-NNN` continue. Groupement thématique par préfixe (TC-100 = display, TC-200 = desktop, TC-300 = stage, TC-400 = drag-drop, TC-500 = resize, TC-600 = hot-swap, TC-700 = edge case).

### Section 3 — Grille d'évaluation unique

Une **table markdown unique** en bas du fichier, avec une **ligne par test case**. L'agent remplit chaque ligne après exécution :

| Colonne | Contenu |
|---|---|
| `TC` | TC-XXX (clé primaire) |
| `Status` | `PASS` / `FAIL` / `BLOCKED` (précondition non remplie) / `SKIP` (matériel manquant, ex: 2e écran) |
| `Observed` | Ce que l'agent a vu (max 2 lignes) |
| `Expected` | Rappel court de l'attendu |
| `Gap` | Si FAIL : nature de l'écart (1 phrase) |
| `Fix applied` | Référence vers le commit/fichier corrigé (vide si PASS) |
| `Post-fix status` | `PASS` après correction / `STILL_FAIL` / `N/A` |
| `Evidence` | Chemin vers screenshot `/tmp/hui-tc-XXX-*.png` ou log extrait |

Cette table est **la seule source de vérité** du run. Lecture humaine en 30 secondes : compter les `FAIL` non encore en `Post-fix=PASS`.

### Format pour l'agent

L'agent qui passera les tests reçoit le fichier comme prompt. Conventions imposées :

- Toutes les actions sont des commandes shell **exécutables littéralement** (pas de pseudo-code, pas de "cliquer ici").
- Les coordonnées GUI sont en absolu (origine 0,0 = haut-gauche écran principal). Si écran secondaire, coordonnées explicites avec offset.
- Chaque action visuelle est suivie d'un screenshot stockant le PNG sous `/tmp/hui-tc-XXX-<étape>.png` pour traçabilité.
- Les vérifications daemon sont des `roadie ...` dont la sortie attendue est citée mot-pour-mot ou par `grep`.
- Aucune interprétation libre : si un test attend "stage 1 visible plein écran et stage 2 caché offscreen", le résultat attendu est vérifié par `roadie windows list` retournant `frame.x ≥ 0` pour wid stage 1 et `frame.x < -1000` pour wid stage 2.

## Conséquences

### Positives

- **Exécutable par un agent** sans ambiguïté → reproductibilité 100 %.
- **Reporting unique** → un coup d'œil sur la grille indique l'état complet de la suite.
- **Régression facile à détecter** : ré-exécuter la suite après tout fix produit la même grille à comparer.
- **Couverture explicite** : la matrice rend visible les combinatoires non testées (= cellule vide ou SKIP).
- **Périmètre auto-documenté** : les invariants centralisés évitent les définitions divergentes entre fichiers.

### Négatives

- **Coût de passage** : la suite complète peut prendre 30-60 minutes manuellement (estimation à raffiner après rédaction).
- **Maintenance** : ajouter un renderer (US3-US5) ou un tiler nouveau impose d'étendre la matrice — non automatique.
- **Tests visuels subjectifs** : certains résultats reposent sur la capture d'écran + lecture par l'agent, susceptible à des erreurs si rendering varie (ex: dpi). Mitigation : tolérance pixel-à-pixel à 1 % (cf. SPEC-019 SC-002).
- **Pas de CI** : la suite n'est pas câblée à un pipeline GitHub Actions (impossible : besoin de macOS + 2 écrans + permissions Accessibility). Reste manuelle ou semi-manuelle via agent local.

### Articulation test ↔ correction (mode opératoire imposé à l'agent)

**Choix** : boucle hybride par classe (Option C), avec garde-fous explicites.

**Rationale** :
- Les classes de tests (display, desktop, stage, drag-drop, resize, hot-swap, edge-case) recouvrent typiquement **un module Swift dédié** → un fix touche un seul fichier, le risque de casser une autre classe est faible **dans la classe courante**.
- Une passe complète sans fix (Option A) accumule des FAIL en cascade quand une classe N+1 dépend d'un fix de classe N.
- Un test↔fix immédiat par TC (Option B) charge le contexte de raisonnement avec à la fois la perspective test et la perspective code, augmentant le risque d'erreur.
- La boucle par classe préserve la séparation cognitive (un mode à la fois) tout en gardant des cycles courts.

**Phases imposées** :

```
PHASE 1 — Setup (1 fois)
  ├─ Vérifier prérequis : daemon vivant, rail vivant, écrans détectés,
  │  permissions Accessibility, cliclick installé
  └─ STOP et escalade si non OK (pas de fix infrastructure par l'agent)

PHASE 2 — Boucle par classe, dans l'ordre TC-100 → TC-700
  Pour chaque classe :
    Étape A — Passe lecture seule
      Passer tous les TC de la classe, remplir colonne Status
    Étape B — Si FAIL > 0 dans la classe
      1. Diagnostic empirique OBLIGATOIRE : logs daemon, screenshots,
         état runtime (`roadie windows list`, `roadie stage list …`).
         JAMAIS de fix sans données runtime observées.
      2. Identifier la cause racine (1 fix peut résoudre N FAIL connexes)
      3. Appliquer fix sur le code source
      4. Noter dans la grille : commit hash + fichier modifié +
         1 phrase rationale (colonne Fix applied)
      5. Re-passer SEULEMENT les TC FAIL → noter Post-fix status
      6. Si encore FAIL → 2e cycle de fix (UN SEUL DE PLUS)
      7. Si encore FAIL après 2 cycles → STOP, escalade humaine
    Étape C — Si toute la classe = PASS ou Post-fix=PASS
      Tag commit `git tag tc-class-<name>-pass` + classe suivante

PHASE 3 — Régression complète (1 fois, après toutes les classes vertes)
  ├─ Re-passer la suite TC-100 → TC-799 en LECTURE SEULE
  ├─ Toute différence vs passe initiale (PASS → FAIL ou Post-fix=PASS → FAIL)
  │  = régression cross-classe
  └─ Si régression : mode "fix dirigé" SEULEMENT sur le TC qui a bougé,
     puis re-passe phase 3 entière (max 2 itérations)
```

**Garde-fous critiques (dérogation interdite à l'agent)** :

| Garde-fou | Justification |
|---|---|
| **Diagnostic empirique obligatoire avant tout fix** | Mémoire projet `feedback_no_workarounds.md` + règle anti-tunnel CLAUDE.md ligne « 2 tentatives, sinon observer données runtime » |
| **Maximum 2 cycles fix par classe** | Au-delà, l'hypothèse de cause est statistiquement fausse — escalade plutôt que fix tunnel |
| **Chaque fix tracé dans la grille** (commit + fichier + rationale 1 phrase) | Le humain doit pouvoir auditer toutes les modifications de la passe en 1 minute |
| **Tag commit par classe verte** | Réversibilité : si phase 3 révèle régression, retour au dernier tag stable possible |
| **Phase 3 obligatoire** | Détection régression cross-classe — sans elle, un fix tardif peut casser une classe précoce sans qu'on le sache |
| **L'agent ne modifie jamais les TC eux-mêmes** | Sinon il pourrait subtilement adapter un test à un bug qu'il vient de coder. Matrice = lecture seule, grille = écriture seule |
| **L'agent ne saute pas un TC sauf si SKIP justifié** | Un TC `BLOCKED` doit avoir une cause documentée (matériel manquant, daemon down) — pas une cause de confort (« semble difficile à automatiser ») |

### Convention de mise à jour

- Ajout d'un nouveau test case → préfixe TC dans la bonne section, ligne ajoutée dans la grille avec `Status=PENDING`.
- Modification d'un test case existant → garder le même TC-XXX, incrémenter une note `Modified: YYYY-MM-DD <reason>` dans le test case.
- Retrait d'un test case obsolète → `Status=DEPRECATED` dans la grille, ne pas supprimer (traçabilité).
- L'agent qui passe la suite **ne doit pas modifier** les test cases (lecture seule), seulement la grille.

## Liens

- [SPEC-018 audit-coherence.md](../../specs/018-stages-per-display/audit-coherence.md) — 19 findings cohérence dont 15 fixés, qui motivent cette suite
- [SPEC-019 spec.md](../../specs/019-rail-renderers/spec.md) — modularité renderers, dépendance directe pour les TC renderers
- [Test matrix](../../specs/019-rail-renderers/test-matrix-coherence.md) — livrable de cette ADR
