# Spec 166 — Fluidité 120 Hz & gestes trackpad, raccourcis autonomes et distribution 1-clic

- **ID** : 166
- **Branche** : `feat/166-fluidite-raccourcis-distribution`
- **Date** : 2026-11-25
- **Statut** : En cours

## 1. Contexte et objectif

Suite à l'analyse comparative du marché des gestionnaires de fenêtres macOS (2026), trois axes structurants permettent à Roadie de rattraper et dépasser la nouvelle vague (`OmniWM`, `Rift`, `Paneru`, `AeroSpace`) tout en conservant sa compatibilité macOS 14+ sans désactivation de SIP :

1. **Sensation physique 120 Hz & gestes trackpad natifs en mode `scrolling`** :
   - Aligner l'horloge d'animation (`EffectAnimator` et `FrameTransitionRuntime`) sur la fréquence rafraîchissement écran réelle (jusqu'à 120 Hz sur ProMotion, repli 60 Hz, zéro CPU au repos).
   - Rendre le défilement du ruban `scrolling` fluide à ressort avec glissement position-seule (`preservesSize = true` dès que la taille des colonnes ne change pas), pilotable par balayage horizontal 3/4 doigts au trackpad et par `⌥ Option` + molette/défilement sur souris externe.
2. **Raccourcis clavier 100 % autonomes dès l'installation** :
   - Fournir des préréglages complets (`standard`, `vim`, `minimal`) couvrant tuilage, stages, Tabbed BSP, ruban défilant, scratchpad et vue d'ensemble, directement enregistrés par `RoadieCommandHotkeys` sans BetterTouchTool ni Karabiner.
   - Offrir une gestion complète en CLI (`roadie shortcuts list|presets|apply-preset|add|remove|check` et `roadie config init`), dans le Lanceur et en 1 clic dans **Paramètres > Raccourcis**, sans jamais écraser une configuration existante sans demande explicite.
3. **Distribution « 1 clic » (sans notarisation Apple pour le moment)** :
   - Publier un Cask Homebrew maintenu (`Casks/roadie.rb`) généré automatiquement par `scripts/generate-cask` et synchronisé avec `scripts/package-dmg`.
   - Fournir un script d'installation 1-ligne / 1-clic (`scripts/install-release.sh`) avec vérification SHA-256, levée explicite de quarantaine Gatekeeper, installation CLI + `Roadie.app` + LaunchAgent + initialisation non-destructive de `config.toml`, et mode `--dry-run`.
   - Automatiser la publication des artefacts sur tag `v*` via `.github/workflows/release.yml` (sans étape de notarisation Apple à ce stade).

## 2. Exigences fonctionnelles

### Pilier 1 — Fluidité 120 Hz & gestes trackpad (`scrolling`)
- **FR-001** : `EffectAnimator` adapte automatiquement sa période de rafraîchissement à la fréquence maximale des écrans connectés (bornée entre `30` et `120` Hz) et coupe son timer dès qu'aucune transition n'est active.
- **FR-002** : En mode `.scrolling`, le recentrage après changement de focus ou de colonne utilise `preservesSize = true` lorsque la taille de la fenêtre correspond déjà à la cible et s'anime fluidement via un ressort critique lorsque `tiling.scrolling_smooth_scroll = true` (défaut), même si les animations globales `fx.animations.enabled` sont désactivées.
- **FR-003** : `ScrollingGestureDetector` (logique pure testable) détecte les balayages horizontaux multi-doigts (3 ou 4 doigts selon `tiling.scrolling_trackpad_fingers`, défaut `3`) avec filtre de ratio horizontal/vertical (`|dx| >= 1.6 * |dy|`), seuil minimal (`0.08`), anti-rebond (`220 ms`) et réarmement propre, ainsi que le défilement `⌥ Option + scrollWheel`.
- **FR-004** : `ScrollingTrackpadGestureController` n'active ses moniteurs passifs que lorsque `tiling.scrolling_trackpad_gestures = true` ou `overview.trackpad_gesture = true` (défauts) : balayage horizontal 3/4 doigts uniquement sur stage active `.scrolling`, et balayage vertical 4 doigts haut/bas pour ouvrir/fermer la Vue d'ensemble sans BetterTouchTool (`overview.trackpad_gesture`).
- **FR-005** : Les 5 nouveaux réglages (`tiling.scrolling_smooth_scroll`, `tiling.scrolling_trackpad_gestures`, `tiling.scrolling_trackpad_fingers`, `tiling.scratchpad_reboot_policy`, `overview.trackpad_gesture`) respectent intégralement la checklist `docs/dev/ajouter-un-reglage.md`.

### Pilier 2 — Raccourcis autonomes, indépendance BTT et Scratchpad au reboot
- **FR-006** : `ShortcutPresets` expose 3 préréglages sans collision interne (`standard`, `vim`, `minimal`) et une fusion non-destructive `mergePreset(_:into:replaceExisting:)`.
- **FR-007** : La CLI expose `roadie shortcuts list|presets|apply-preset|add|remove|check` et `roadie config init [--preset standard|vim|minimal|none] [--force] [--config PATH]` avec sortie texte et `--json`, complétion zsh, et rechargement live de `RoadieCommandHotkeys`.
- **FR-008** : **Paramètres > Raccourcis** et le **Lanceur** permettent d'appliquer un préréglage autonome en un clic, avec bilan clair du nombre de raccourcis ajoutés/ignorés ; un bouton optionnel « Tout reprendre de BetterTouchTool » facilite la migration sans empêcher l'usage continu de BTT ou Karabiner.
- **FR-008b** : Le menu contextuel de barre de titre (**Fenêtre**) propose « Transformer en scratchpad » ou « Retirer du scratchpad (<nom>) » (actif même sur une fenêtre déjà en scratchpad dont `scope == nil`).
- **FR-008c** : `tiling.scratchpad_reboot_policy` paramètre le comportement après redémarrage ou fermeture : `reattach_or_relaunch` (défaut façon Pyprland : rattachement par `bundleID`/titre puis relance à la demande), `reattach` (rattachement sans relance) ou `ephemeral` (façon i3/Sway).

### Pilier 3 — Distribution 1-clic (hors notarisation)
- **FR-009** : `scripts/generate-cask` génère un fichier Homebrew Cask valide (`Casks/roadie.rb`) à partir de la version, du dépôt GitHub et du SHA-256 (ou `:no_check`), installant `Roadie.app` et la CLI `roadie`, gérant la levée de quarantaine sans notarisation et la désinstallation propre.
- **FR-010** : `scripts/package-dmg` supporte une identité `ROADIE_CODESIGN_IDENTITY` optionnelle (repli ad hoc `-`) et produit `dist/Roadie.dmg`, `dist/Roadie.dmg.sha256` et `dist/roadie.rb`.
- **FR-011** : `scripts/install-release.sh` installe Roadie en une commande depuis GitHub Releases ou un `--dmg` local, vérifie le SHA-256, initialise `config.toml` si absent, configure le LaunchAgent et supporte `--dry-run`, `--preset`, `--no-start`.
- **FR-012** : `.github/workflows/release.yml` construit et publie automatiquement `Roadie.dmg`, `Roadie.dmg.sha256` et `roadie.rb` sur les tags `v*`, sans étape de notarisation Apple.

## 3. Hors périmètre explicite

- Notarisation Apple (`notarytool`, certificat Developer ID Apple payant) : volontairement différée à une étape ultérieure sur demande utilisateur.
- Modification des raccourcis BetterTouchTool ou de la configuration `config.toml` existante de l'utilisateur lors d'une mise à jour.

## 4. Critères d'acceptation

- `2 700+` tests Swift (`./scripts/test --no-parallel`) + tests Python (`scripts/tests`) verts à 100 %, incluant les gardes `Spec155ConfigGuardTests` et `SettingsCatalogTests`.
- Aucune régression sur les modes `spatialBsp` (y compris Tabbed BSP), `tabbed`, `scrolling`, `masterStack`, `bsp`, `float`.
- Revue indépendante Bridget approuvée avant fusion sur `main`.
- Installation locale signée `roadied-cert`, démon redémarré et `roadie daemon health --json` à 5/5 `ok`.
