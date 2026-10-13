# Research: Boîte de commandes et fenêtre de réglages

Statut : constats lus dans le code le 2026-10-13. « Non vérifié » = à confirmer à l'exécution. Chemins relatifs à la racine du dépôt.

## R1 - Exécuter les commandes sans le socket

- **Constat** : `roadied` crée déjà `CLICommandRouter` (`Sources/roadied/main.swift:211`) et le serveur de socket appelle `router.run(argv)` sur le MainActor (`CommandSocketServer.swift`). `CLICommandRouter.run(_:) -> CLIResponse {exitCode, stdout, stderr}` est `public` et `@MainActor` (`CLICommandRouter.swift:103`).
- **Décision** : le lanceur appelle `CLICommandRouter().run(argv)` en process. Il traduit `CLIResponse` en résultat de boîte : succès si `exitCode == 0`, message = `stdout` (ou `stderr` en cas d'échec).
- **Pourquoi** : aucune action nouvelle (Article XIX), même comportement que la CLI (FR-005). Les services appelés sont les mêmes (`WindowCommandService`, `StageCommandService`, `DisplayCommandService`, `DesktopCommandService`, `LayoutCommandService`, `WindowBookmarkCommandService`).
- **Rejeté** : appeler chaque service à la main (duplique le routeur) ; passer par le socket (inutile dans le même processus, délai de 5 s).
- **Limite** : une instance du routeur sert un appel à la fois (buffers remis à zéro). Le lanceur crée une instance par commande.

## R2 - Commandes qui ne peuvent pas s'exécuter pendant la boîte

- **Constat** : `grid interactive` et `targets interactive` postent une notification que `TargetModeRuntimeController.handle` ignore si une session est ouverte (`TargetModeRuntimeController.swift:103-110`). `daemon restart` fait `launchctl kickstart -k` : le daemon se tue lui-même.
- **Décision** : le lanceur renvoie une action différée. La boîte se ferme (`finish`), puis l'action part au tour suivant de la boucle principale. `/restart` est la dernière action, sans message attendu.
- **Non vérifié** : l'ordre exact entre `finish` et la remise à zéro de `currentSession` (`TargetModeRuntimeController.swift:336-346`). Un test manuel le confirme ; à défaut, un délai d'un tour de boucle.

## R3 - Touches de la boîte

- **Constat** : `SearchKeyInput.kind` n'accepte comme texte que lettres, chiffres et ` *;?` ; `/ - . _` sont ignorés (`TargetOverlayPresenter.swift:972-974`). Shift + lettre devient `labelCharacter`. Tab, Flèche bas et Ctrl-N donnent `.next`, Maj-Tab, Flèche haut et Ctrl-P donnent `.previous`. Test existant : `searchKeysAreDecodedLikeHomerow`.
- **Décision** :
  - Le décodeur accepte aussi `/ . - _ , :` et les lettres accentuées comme texte. Dans le mode recherche, ces caractères restent sans effet sur les correspondances (ils se tapent dans la requête comme les autres).
  - `SearchKeyInput` expose en plus la nature de la touche de navigation (tabulation, flèche, contrôle) sans changer `Kind` : les tests existants restent valides.
  - En mode commande : Tab = compléter, Maj-Tab = suggestion précédente, Flèche haut/bas = historique, Ctrl-N / Ctrl-P = suggestion suivante/précédente, Shift + lettre = lettre majuscule dans la saisie.
  - Le mode commande commence quand le premier caractère est `/`. Un texte à chercher qui commence par `/` se tape précédé d'un espace (espaces ignorés par la recherche).
- **Rejeté** : une seconde session de saisie (duplique la barre et le tap clavier).

## R4 - Affichage de la liste et du message

- **Constat** : la barre est un rectangle de 40 pt dessiné à `y = bounds.minY + 48` (`drawSearchBar`, `TargetOverlayPresenter.swift:1190-1215`), avec un seul texte. `TargetSearchBar` (l.1143) porte `query`, `matchCount`, `properties`, `isLoading`. Aucun canal de message n'existe : `target_mode.finished` n'est qu'un événement du journal.
- **Décision** : ajouter à `TargetSearchBar` une liste de suggestions (au plus 8 lignes, la sélectionnée en surbrillance) et un message (au plus 12 lignes, rouge si erreur). Ils s'empilent au-dessus de la barre, qui reste collée en bas. Un message reste affiché jusqu'à la frappe suivante (même principe que `properties`). Les résultats multi-lignes de `/doctor` sont tronqués à 12 lignes ; la dernière ligne indique le nombre de lignes cachées.
- **Fenêtre active** : la barre est un `NSPanel` non activant. Le focus AX reste donc sur la fenêtre d'origine et les commandes lisent le focus à l'exécution. Non vérifié à l'écran.

## R5 - Écrire `roadies.toml` sans perdre de commentaires

- **Constat** : aucun code n'écrit `roadies.toml` aujourd'hui. TOMLKit sert uniquement à lire (`TOMLDecoder`, `TOMLTable(string:)`). Préservation des commentaires par TOMLKit : non vérifiée. Le fichier réel fait 774 lignes, très commentées, avec du code commenté (`# gaps_outer_top = 4`) et des tables non supportées (`[signals]`). Le parseur du rail lit ligne à ligne `clé = valeur` et ignore les en-têtes `[[…]]`.
- **Décision** : éditeur de texte ligne à ligne, sans ré-encodage TOML :
  1. Chercher l'en-tête `[table]` exact (les lignes `[[…]]` et `# [table]` ne comptent pas).
  2. Dans la table (jusqu'à l'en-tête suivant), chercher une ligne `clé = …` non commentée. La remplacer en gardant l'indentation et le commentaire de fin de ligne.
  3. Sinon, insérer `clé = valeur` après la dernière ligne `clé = …` de la table, ou juste après l'en-tête.
  4. Si la table n'existe pas, ajouter `[table]` et la ligne à la fin du fichier.
  5. Valider le texte obtenu (`RoadieConfigLoader.validate` sur un fichier temporaire). Si une erreur nouvelle apparaît, ne rien écrire.
  6. Écrire par fichier temporaire puis remplacement (le watcher du rail se réarme sur un rename).
  7. Avant la première écriture de la session : copie `roadies.toml.bak-<horodatage>` (le préfixe `roadies.toml.b` est déjà purgé en gardant les 3 dernières par `FileAdministration.configBackupActions`).
- **Valeurs** : booléens `true`/`false`, entiers, flottants avec point, chaînes entre guillemets avec échappement, couleurs en chaîne `"#RRGGBB"`.
- **Rejeté** : ré-encoder toute la table avec TOMLKit (risque de perdre commentaires, ordre et tables inconnues, FR-024) ; ajouter une bibliothèque d'édition TOML (dépendance non justifiée).
- **Limite** : seules les valeurs scalaires sur une ligne sont éditées. Une clé dont la valeur existante s'étend sur plusieurs lignes est refusée.

## R6 - Catalogue de réglages et dérive

- **Constat** : 171 clés scalaires (96 hors rail + 75 du rail). Les validations de plage sont réparties en deux endroits : clamps silencieux dans `Config.swift` et `RailSettings.swift:150-241`, erreurs dans `ConfigValidationRules`. Les clés connues sont dans `ConfigValidationRules.knownKeys` (`Config.swift:1216`, privé). Certaines clés sont « sans effet » (`ineffectiveKeys`, `Config.swift:1258`) : `desktops.enabled|count|back_and_forth|mode`, `stage_manager.enabled|hide_strategy`.
- **Décision** :
  - Le catalogue décrit 167 réglages : 171 moins les 6 sans effet, plus 2 clés nouvelles.
  - Nom = `catégorie.clé` (catégories en minuscules sans accent : `tuilage`, `stages`, `lettres`, `grille`, `recherche`, `rail`, `bordures`, `focus`, `avance`). Le nom de la clé du fichier garde son orthographe : aucune traduction à tenir à jour.
  - Une API en lecture expose `knownKeys` pour le test de dérive : toute clé scalaire connue du validateur, hors sans effet, doit avoir un descripteur, et inversement.
  - Un second test compare chaque défaut du catalogue au défaut de `RoadieConfig()` (par encodage de la configuration par défaut) et à `RailSettings` pour le rail. Si l'encodage TOML de `RoadieConfig` n'est pas disponible, repli : table de défauts relue à la main dans le test (non vérifié ; `RoadieConfig` est `Codable`).
- **Rejeté** : générer le catalogue depuis le code (les libellés français et les plages ne s'y trouvent pas) ; des noms français (`grille.lignes`) à synchroniser à la main avec 167 clés.

## R7 - Fenêtre de réglages dans un daemon `accessory`

- **Constat** : `roadied` est `.accessory` (`main.swift:147`), `LSUIElement=true`, sans menu principal. Tous les panneaux sont des `NSPanel` non activants dessinés à la main. Il n'existe aucune vraie fenêtre avec contrôles ni SwiftUI. Seul précédent : `NSApplication.shared.activate()` avant une alerte (`RailController.swift:555`). Roadie exclut de son tiling les fenêtres de son propre processus (`SystemSnapshotProvider.swift:617-640`, filtre `pid != currentPID` plus filtre par nom `roadied`/`roadie`).
- **Décision** :
  - `NSWindow` (titre « Réglages Roadie », redimensionnable, taille minimale 760×520) avec un `NSHostingController` SwiftUI.
  - Fenêtre unique conservée par un contrôleur statique ; une seconde demande appelle `makeKeyAndOrderFront`.
  - À l'ouverture : `NSApp.activate()`. Politique `accessory` conservée : pas d'icône dans le Dock. `collectionBehavior = [.moveToActiveSpace]` pour qu'elle apparaisse sur le bureau courant.
  - Pas de menu principal : la fenêtre gère elle-même Échap (`cancelOperation`) et Cmd + W (`performKeyEquivalent`). Échap pendant l'édition d'un champ texte ne ferme pas la fenêtre.
  - Suivi du fichier par `RailFileWatcher` (réutilisé : `init(path:onChange:)`, `start()`, `stop()`).
- **Non vérifié** : la fenêtre ne doit pas être tuilée. Le filtre par pid la protège si elle est créée dans le processus qui fait le snapshot. Si `roadied run` n'est pas le processus qui la crée (mode séparé), le filtre par nom peut échouer (casse non vérifiée). Un test manuel (quickstart, étape 4) le vérifie ; garde-fou : `isLikelyTransientSettingsWindow` rend de toute façon flottante une fenêtre « Réglages » de ≤ 760×760.
- **Rejeté** : fenêtre AppKit pure (3 fois plus de code pour 167 contrôles) ; fenêtre HTML (nouvelle dépendance web).

## R8 - Taille des étiquettes

- **Constat** : police 13 pt `.semibold` en dur (`TargetOverlayPresenter.swift:1378`) ; badge de 24 pt de haut et 28 pt de large minimum (l.1223) ; marges et pas de placement 10, 6, 6, 4 (l.1245-1279). Les sessions lettres et recherche créent leurs fenêtres en style `.labels` sans config ; la grille reçoit `TargetOverlayStyle.grid(config)`. `TargetOverlayStyle` est le seul objet qui arrive jusqu'à `TargetOverlayView`.
- **Décision** : `TargetOverlayStyle` gagne `labelFontSize` (défaut 13). Un facteur `scale = labelFontSize / 13` s'applique à : police, hauteur et largeur minimale du badge, rayon, `gap`, `inset`, pas de placement, marge d'évitement. Les épaisseurs de trait ne changent pas. La barre de saisie de la recherche garde sa police de 15 pt (la demande porte sur les étiquettes).
- **Clés** : `experimental.target_mode.label_font_size` et `experimental.target_grid.label_font_size`, Double, défaut 13, plage 8 à 48 (clamp au décodage comme les autres, erreur de validation hors plage).
- **Injection** : `startTargetsInteractive` et `startTargetsSearch` lisent `effectiveConfig.experimental.targetMode` et passent le style ; la grille utilise déjà `TargetOverlayStyle.grid(config)`.

## R9 - Historique des commandes

- **Constat** : l'état persistant utilise `JSONPersistence` (`load`, `write`) sous `~/.local/state/roadies/`.
- **Décision** : fichier `command-history.json` (liste de chaînes, 50 au plus, la plus récente en dernier, doublon consécutif ignoré). Lecture à l'ouverture de la boîte, écriture après une commande réussie.

## R10 - Journal

- **Constat** : `EventLog` accepte des types d'événements libres (`config.reload_applied` n'est pas dans le catalogue de `AutomationEventCatalog`).
- **Décision** : événements `settings.changed` (nom, ancienne et nouvelle valeur) et `command.rejected` (commande, raison). Pas de modification du catalogue. Les valeurs des réglages n'ont pas de donnée personnelle ; l'historique de commandes n'est pas journalisé.

## R11 - Ce qui n'existe pas dans Roadie aujourd'hui

- `toggle floating` et `window close` : non implémentés (`CLICommandRouter.swift:649, 872`). `/float` et `/close` ne sont pas proposées.
- `window swap` est un alias de `window move` dans le routeur (`:868`) : `/swap` appelle `window swap`.
- `stage switch` prend un identifiant, pas un nom : `/stage nom` résout le nom en identifiant par `StageStore().state()` avant l'appel.
- `stage create` exige un identifiant : `/stage new [nom]` prend le plus petit identifiant numérique libre.
- `window display N` n'accepte qu'un numéro d'écran : `/send N`.

## Inventaire des réglages (pour SettingsCatalog)

Source : lecture de `Config.swift` et `RailSettings.swift`. « P » = plage ; sans plage = pas de validation.

| Catégorie | Table TOML | Clés scalaires |
|---|---|---|
| Tuilage | `tiling` (11) | `default_strategy` (bsp, spatial_bsp, master_stack, float ; bsp), `split_policy` (largest_dim), `gaps_outer` (8), `gaps_outer_top/right/bottom/left` (optionnels), `gaps_inner` (4), `master_ratio` (0.6), `smart_gaps_solo` (false), `popup_filter` (true) |
| Tuilage | `window_placement` (2) | `new_apps_target` (mouse, focused_display, macos ; macos), `new_window_side` (right, left ; right) |
| Tuilage | `width_adjustment` (3) | `nudge_step` (0.05), `minimum_ratio` (0.25), `maximum_ratio` (1.5 ; ≥ minimum) |
| Stages et bureaux | `stage_manager` (1 utile) | `default_stage` ("1") ; `enabled` et `hide_strategy` sans effet, masqués |
| Stages et bureaux | `desktops` (0 utile) | quatre clés sans effet, masquées |
| Focus et souris | `focus` (5) | `stage_follows_focus` (true), `assign_follows_focus` (false), `stage_move_follows_focus` (true), `focus_follows_mouse` (false), `mouse_follows_focus` (false) |
| Bordures | `fx.borders` (6) | `enabled` (false), `thickness` (2), `corner_radius` (10), `active_color` (#7AA2F7), `inactive_color` (#414868), `pulse_on_focus` (false) |
| Mode lettres | `experimental.target_mode` (7 + 1 nouvelle) | `enabled` (true), `picker_enabled` (true), `overlay_enabled` (false), `overlay_labels_only` (true), `overlay_duration_seconds` (3 ; P 0.2-30), `app_mouse_actions_enabled` (false), `scroll_mode_enabled` (false), **`label_font_size`** (13 ; P 8-48, nouvelle) |
| Mode lettres | `experimental.app_targets` (7) | `enabled` (false), `scope` (frontmost_window, visible_windows), `max_targets` (150 ; P 1-500), `timeout_ms` (120 ; P 10-2000), `hint_characters` (asdfghjkl ; ≥ 2 caractères), `ax_boost_enabled` (false), `max_depth` (12 ; P 1-40) |
| Recherche | `experimental.target_mode` (1) | `search_hotkey` (command+control+alt+f ; vide = désactivé) |
| Grille | `experimental.target_grid` (26 + 1 nouvelle) | `enabled` (false), `mode` (auto_click, recursive), `overlay_enabled` (true), `overlay_draw_grid` (true), `overlay_fill_color` (#4DABF7), `overlay_fill_opacity` (0.10 ; P 0-1), `overlay_border_color` (#4DABF7), `overlay_border_opacity` (0.55 ; P 0-1), `overlay_label_color` (#FFFFFF), `overlay_label_background_opacity` (0.84 ; P 0-1), `rows` (3 ; P 2-12), `columns` (3 ; P 2-12), `max_depth` (3 ; P 1-20), `hint_characters` (azeqsdwxc ; ≥ rows × columns caractères), `confirm_action_key` (space), `reset_key` (r), `back_key` (backspace), `exit_key` (escape), `arrow_navigation_enabled` (true), `arrow_edge_behavior` (clamp, wrap), `action_delay_ms` (30 ; P 0-1000), `wake_mouse_pixels` (1 ; P 0-20), `mouse_follow_grid` (false), `focus_follow_grid` (false), `label_placement` (callout, center), `default_scope` (display, focused_window), **`label_font_size`** (13 ; P 8-48, nouvelle) |
| Avancé | `experimental.target_record` (12) | `enabled` (false), `replay_enabled` (false), `directory`, `default_duration_seconds` (10), `max_duration_seconds` (120 ; P 1-3600), `max_events` (2000 ; P 1-20000), `include_mouse_moves`, `include_key_events`, `include_ax_context`, `record_text_input`, `indicator` (notification, navrail, both, none), `navrail_bottom_offset` (50 ; P 0-400) |
| Avancé | `experimental.titlebar_context_menu` (9) | `enabled` (false), `height` (36 ; P 12-96), `leading_exclusion` (84 ; P 0-240), `trailing_exclusion` (16 ; P 0-240), `managed_windows_only`, `tile_candidates_only`, `include_stage_destinations`, `include_desktop_destinations`, `include_display_destinations` (tous true) |
| Rail | `fx.rail` (14) | `renderer`, `width` (150 ; P 90-320), `background_color`, `background_opacity` (0 ; P 0-1), `auto_hide`, `edge_hit_width` (8 ; P 1-40), `edge_magnetism_width` (24 ; P 0-160), `animation_ms` (160 ; P 0-1000), `hide_delay_ms` (350 ; P 0-5000), `layout_mode` (overlay, resize), `dynamic_left_gap`, `empty_click_hide_active`, `empty_click_safety_margin` (12 ; P 0-80), `hide_on_maximized` |
| Rail | `fx.rail.layout` (5) | `header_position` (top, bottom, hidden), `stages_position` (top, center, bottom), `spacing` (13 ; P 0-80), `top_padding`, `bottom_padding` (P 0-240) |
| Rail | `fx.rail.header.display` (10) et `fx.rail.header.desktop` (10) | `enabled`, `template`, `color`, `font_size` (13 / 10 ; P 6-40 / 6-32), `font_family`, `weight` (regular, medium, semibold, bold), `alignment` (left, center, right), `opacity` (P 0-1), `offset_x`, `offset_y` (P -120 à 120) |
| Rail | `fx.rail.stage_labels` (13) | `enabled`, `color`, `font_size` (11 ; P 6-28), `font_family`, `weight`, `alignment`, `opacity` (0.72), `offset_x`, `offset_y`, `placement` (above, below), `z_order` (below, above), `visibility_seconds` (P 0-3600), `fade_seconds` (0.35 ; P 0-10) |
| Rail | `fx.rail.stages` (3), `fx.rail.preview` (5), `fx.rail.stacked` (4), `fx.rail.parallax` (11) | voir `RailSettings.swift:150-241` pour les défauts et plages |

Total : 96 hors rail − 6 sans effet + 2 nouvelles + 75 rail = 167 réglages. Les listes (`smart_gaps_solo_sides`, `allowed_subroles`, `floating_bundles`, `presets`, `include_roles`, `additional_boost_bundle_ids`) et les tableaux de tables (`display_overrides`, `workspaces`, `stage_overrides` ×2, `rules`, `signals.hooks`) s'affichent en lecture seule.
