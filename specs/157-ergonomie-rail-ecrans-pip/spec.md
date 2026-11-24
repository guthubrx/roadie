# Spec 157 — Ergonomie quotidienne : icônes d'applications dans le NavRail, actions rapides écrans/bureaux et Picture-in-Picture flottant

Statut : en cours (Session 173, validée par l'utilisateur le 24 novembre 2026).

## Contexte et objectifs

Améliorer le confort quotidien de Roadie sans toucher aux animations à ressort (déjà présentes et réglables dans Paramètres → Effets) :

1. **US1 — Icônes d'applications sous chaque carte du NavRail** :
   - Conserver intégralement les indicateurs visuels existants sur les aperçus (bordure blanche continue pour le plein écran natif, coins blancs pour le zoom/agrandissement Roadie).
   - Afficher sous l'aperçu de chaque stage non vide (modes `stacked`, `parallax`, `mosaic`) une rangée horizontale compacte des icônes des applications présentes dans cette stage (dans l'ordre des membres, dédupliquées par `bundleID`), afin de voir immédiatement toutes les applications présentes même lorsqu'une fenêtre est agrandie/zoomée.
   - Contrôlé par le réglage `fx.rail.show_app_icons_row` (booléen, `true` par défaut, désactivable dans Paramètres → Rail).

2. **US2 — Égaliser les proportions (`balance`) depuis le lanceur et le NavRail** :
   - Exposer `LayoutCommandService.balance()` (valable sur tous les écrans : 4K, 5K, etc.) en commande système dans le lanceur (`Cmd+Space`) et dans le menu contextuel du NavRail.

3. **US3 — Échanger deux écrans en une touche (`display swap`)** :
   - Ajouter `roadie display swap [N|left|right|up|down]` qui échange les stages actifs (avec leurs fenêtres, arbres BSP, modes, noms et focus) entre l'écran actif et l'écran cible en une transaction atomique et un seul plan de placement.
   - Sans cible explicite, échange avec l'autre écran (ou l'écran suivant si plus de 2 écrans).
   - Exposé en CLI (utilisable dans `[[shortcuts]]`/BTT), dans le lanceur et dans le menu contextuel du NavRail.

4. **US4 — Nettoyage en un clic des stages vides (`stage prune-empty`)** :
   - Ajouter `roadie stage prune-empty` qui supprime en une action sur l'écran courant toutes les stages inactives, non parquées, vides et **sans nom personnalisé**.
   - Les stages nommées, occupées, parquées ou actives ne sont jamais supprimées.
   - Exposé en CLI, dans le menu contextuel du NavRail et dans le lanceur.

5. **US5 — Picture-in-Picture flottant automatiquement** :
   - Détecter automatiquement les fenêtres Picture-in-Picture (`com.apple.PIPAgent`, ou fenêtres PiP Firefox/Chrome/Brave/Edge/Arc/Safari) et les exclure du tuilage dans `baseTilingDecision`, tout en laissant les règles utilisateur explicites prioritaires.
   - Contrôlé par le réglage `tiling.float_picture_in_picture` (booléen, `true` par défaut, désactivable dans Paramètres → Tuilage).

## Exclusions

- Ne pas modifier les courbes d'animation à ressort (`fx.animations.curve = "spring"` déjà présent).
- Ne jamais supprimer automatiquement une stage nommée par l'utilisateur lors d'un `prune-empty`.

## Critères de réussite

- Tous les nouveaux réglages respectent `docs/dev/ajouter-un-reglage.md` (Config, `knownKeys`, `SettingsCatalog`, compteurs `SettingsCatalogTests`, `Spec155ConfigGuardTests`, docs FR/EN et `CHANGELOG.md`).
- Tests unitaires dédiés pour US1 à US5 + suite complète `./scripts/test --no-parallel` et `python3 -I -B -m unittest discover -s scripts/tests` 100 % verts.
- Revue indépendante Bridget approuvée, livraison sur `main`, installation signée `roadied-cert`, redémarrage vérifié 5/5 et ménage complet.
