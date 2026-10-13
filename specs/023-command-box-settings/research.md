# Research: Boîte de commandes et fenêtre de réglages

Statut : constats lus dans le code le 2026-10-13. « Non vérifié » = à confirmer à l'exécution. Chemins relatifs à la racine du dépôt.

## R1 - Exécuter les commandes sans le socket

- **Constat** : `roadied` crée déjà `CLICommandRouter` (`Sources/roadied/main.swift:211`) et le serveur de socket appelle `router.run(argv)` sur le MainActor (`CommandSocketServer.swift`). `CLICommandRouter.run(_:) -> CLIResponse {exitCode, stdout, stderr}` est `public` et `@MainActor` (`CLICommandRouter.swift:103`).
- **Décision** : le lanceur appelle `CLICommandRouter().run(argv)` en process. Il traduit `CLIResponse` en résultat de boîte : succès si `exitCode == 0`, message = `stdout` (ou `stderr` en cas d'échec).
- **Pourquoi** : aucune action nouvelle (Article XIX), même comportement que la CLI (FR-005). Les services appelés sont les mêmes (`WindowCommandService`, `StageCommandService`, `DisplayCommandService`, `DesktopCommandService`, `LayoutCommandService`, `WindowBookmarkCommandService`).
- **Rejeté** : appeler chaque service à la main (duplique le routeur) ; passer par le socket (inutile dans le même processus, délai de 5 s).
- **Limite** : une instance du routeur sert un appel à la fois (buffers remis à zéro). Le lanceur crée une instance par commande.

## R2 - Commandes qui ne peuvent pas s'exécuter pendant la boîte

- **Constat** : `grid interactive` et `targets interactive` postent une notification que `TargetModeRuntimeController.handle` ignore si une session est ouverte (`TargetModeRuntimeController.swift:103-110`). `finish` remet `currentSession` à nil (l.336-344). La notification revient ensuite sur le MainActor par une tâche (l.74-82). `daemon restart` fait `launchctl kickstart -k` : le daemon se tue lui-même (`CLICommandRouter.swift:1750-1765`).
- **Décision** : séquence unique pour toute action différée : (1) la session se termine (`cleanup`, fenêtres fermées, tap retiré) ; (2) `TargetModeRuntimeController.finish` remet l'état à zéro ; (3) seulement ensuite, un tour de boucle plus tard, le lanceur appelle `CLICommandRouter().run(argv)`. Le lanceur reçoit l'action par `onFinish`, pas avant.
- **Exception `/restart`** : aucun résultat n'est affiché, car le processus s'arrête. La boîte se ferme puis le redémarrage part en dernier. Le contrat de résultat court ne s'applique pas à cette commande.
- **Test** : un test du contrôleur vérifie que `/grid` et `/letters` lancés par une action différée démarrent une session (la notification n'est plus ignorée). Test manuel complémentaire (quickstart §2).

## R3 - Touches de la boîte

- **Constat** : `SearchKeyInput.kind` n'accepte comme texte que lettres, chiffres et ` *;?` ; `/ - . _` sont ignorés (`TargetOverlayPresenter.swift:972-974`). Shift + lettre devient `labelCharacter` (saut d'étiquette). Tab, Flèche bas et Ctrl-N donnent `.next`, Maj-Tab, Flèche haut et Ctrl-P donnent `.previous`. Retour peut attendre un second Retour (double-clic, 0,35 s). Test existant : `searchKeysAreDecodedLikeHomerow` (`TargetSearchModelTests.swift:183-205`).
- **Décision** :
  - **Aiguillage avant le modèle de recherche.** `TargetSearchModel` gagne `isCommandMode` (vrai si `query` commence par `/`). En tête de `handleSearch`, si `isCommandMode`, toutes les touches vont à `SlashCommandModel` ; `TargetSearchModel` ne voit plus ni Maj + lettre, ni Tab, ni flèches, ni Retour. Le premier `/` tapé dans une requête vide bascule en mode commande. Effacer le `/` rend la main à la recherche. Le Retour différé de la recherche est annulé à la bascule.
  - Le décodeur accepte aussi `/ . - _ , :` et les lettres accentuées comme texte. Il décode le **caractère produit** par la touche (`event.characters`), pas la touche physique : sur AZERTY, `/` s'obtient avec Maj et arrive comme texte `/`. Le test de décodage ajoute les cas `/` (avec et sans Maj), `.`, `-`, `é`.
  - `SearchKeyInput` expose en plus la nature de la touche de navigation (tabulation, flèche, contrôle) sans changer `Kind` : les tests existants restent valides.
  - En mode commande : Tab = compléter, Maj-Tab = suggestion précédente, Flèche haut/bas = historique, Ctrl-N / Ctrl-P = suggestion suivante/précédente, Shift + lettre = lettre majuscule dans la saisie, Retour = exécuter (sans attente de second Retour), Échap = fermer.
  - **Mode recherche inchangé (FR-010)** : seul le `/` d'une saisie vide ouvre le mode commande. En mode recherche, `. - _ , :` et un `/` hors du premier caractère restent ignorés comme avant et laissés à l'application active ; un indicateur thread-safe lu par le tap indique le mode commande, où toute touche sans Commande est avalée et tout caractère imprimable est du texte (T027, T030).
- **Tests** : transition `/` puis effacement ; Maj + lettre, Tab, flèches et Retour en mode commande ; mêmes touches en mode recherche inchangées ; décodage AZERTY du `/`.
- **Rejeté** : une seconde session de saisie (duplique la barre et le tap clavier).

## R4 - Affichage de la liste et du message

- **Constat** : la barre est un rectangle de 40 pt dessiné à `y = bounds.minY + 48` (`drawSearchBar`, `TargetOverlayPresenter.swift:1190-1215`), avec un seul texte. `TargetSearchBar` (l.1143) porte `query`, `matchCount`, `properties`, `isLoading`. Aucun canal de message n'existe : `target_mode.finished` n'est qu'un événement du journal.
- **Décision** : ajouter à `TargetSearchBar` une liste de suggestions (au plus 8 lignes, la sélectionnée en surbrillance) et un message (au plus 12 lignes, rouge si erreur). Ils s'empilent au-dessus de la barre, qui reste collée en bas. Un message reste affiché jusqu'à la frappe suivante (même principe que `properties`). Les résultats multi-lignes de `/doctor` sont tronqués à 12 lignes ; la dernière ligne indique le nombre de lignes cachées.
- **Contexte actif** : la barre est un `NSPanel` non activant : le focus AX reste sur la fenêtre d'origine. Les commandes lisent le focus au moment du Retour (FR-004 réduit en conséquence). Non vérifié à l'écran.

## R5 - Écrire `roadies.toml` sans perdre de commentaires

- **Constat** : aucun code n'écrit `roadies.toml` aujourd'hui. TOMLKit sert uniquement à lire. Préservation des commentaires par TOMLKit : non vérifiée. Le fichier réel fait 774 lignes : valeurs avec `#` dans une chaîne (`active_color = "#7AA2F7"`, l.115), tableaux sur plusieurs lignes avec commentaires internes (`floating_bundles = [ … ]`, l.191-195), `[[rules]]` (l.687+), code commenté (`# gaps_outer_top = 4`), tables non supportées. Le parseur du rail lit ligne à ligne `clé = valeur`.
- **Décision** : éditeur de texte qui analyse le fichier ligne à ligne avec un petit automate d'état, sans ré-encodage TOML :
  1. **Automate** : suit, sur chaque ligne, l'état « dans une chaîne `"…"` (avec échappements `\`), dans une chaîne littérale `'…'`, dans `"""` ou `'''` multi-lignes, dans un tableau `[` non refermé ». Le commentaire de fin de ligne commence au premier `#` **hors chaîne**. Un en-tête `[table]` ou `[[table]]` n'est reconnu qu'en début de ligne, hors valeur multi-lignes.
  2. **Périmètre** : l'éditeur ne modifie que les couples (table, clé) du catalogue. Toute autre demande est refusée.
  3. **Remplacement** : dans la table visée (jusqu'à l'en-tête suivant, `[[…]]` compris), chercher une ligne `clé = …` non commentée. La remplacer en gardant l'indentation et le commentaire de fin de ligne.
  4. **Insertion** : si la clé est absente, l'ajouter après la dernière ligne de la table qui n'est ni vide, ni un commentaire, ni dans une valeur multi-lignes (jamais au milieu d'une valeur) ; à défaut, juste après l'en-tête.
  5. **Table absente** : ajouter `[table]` et la ligne à la fin du fichier, après une ligne vide.
  6. **Refus** (le fichier reste intact, message clair) : valeur existante sur plusieurs lignes ou tableau ; clé en notation pointée ou table en ligne (`a.b = …`, `{…}`) ; clé présente deux fois dans la même table ; table `[table]` présente deux fois ; en-tête `[table]` suivi d'un sous-tableau `[[table.x]]` ambigu pour l'insertion ; fin de ligne inattendue de l'automate (guillemet non fermé).
  7. **Écriture** : le texte candidat est écrit dans un fichier temporaire **du même dossier** (`roadies.toml.candidate-<uuid>`), donc avec les mêmes règles générées (`RoadieConfigLoader.generatedRulesPath` dérive du nom `roadies.generated.toml` dans le même dossier ; `Config.swift:1046-1064`) : `RoadieConfigLoader.validate(path:)` sur ce fichier. Si une erreur nouvelle apparaît par rapport au fichier actuel, rien n'est écrit. Sinon, juste avant le remplacement, relire le fichier d'origine et comparer son contenu à celui qui a servi à l'édition. S'il a changé : une seule reprise (relecture, nouvelle édition, nouvelle validation) ; s'il change encore, refus (« le fichier a changé pendant l'écriture »). Le remplacement est atomique (`rename`) ; le watcher du rail se réarme sur un rename.
  8. **Sauvegarde** : copie `roadies.toml.bak-<horodatage>` avant la première écriture de la session (le préfixe `roadies.toml.b` est purgé par `FileAdministration.configBackupActions`, 3 conservées au moins).
  9. **Fichier absent** : le texte de départ est vide ; le fichier est créé avec la table et la clé.
- **Valeurs écrites** : booléens `true`/`false`, entiers, flottants avec point, chaînes entre guillemets avec échappement des `"` et `\`, couleurs en chaîne `"#RRGGBB"`. Une chaîne qui contient un saut de ligne est refusée.
- **Tests** : un fichier de test reprend les constructions du fichier réel (valeur avec `#` dans une chaîne, chaîne entre apostrophes, tableau multi-lignes avec commentaires, `[[rules]]`, clé commentée, même clé dans deux tables, table en double, guillemet non fermé, fichier sans saut de ligne final, fin de ligne CRLF). Pour chaque cas : le texte avant et après ne diffère que par la ligne visée, ou le refus laisse le texte identique. Le quickstart ajoute un essai sur une **copie** du fichier réel (`/tmp`), jamais sur l'original.
- **Rejeté** : ré-encoder toute la table avec TOMLKit (risque de perdre commentaires, ordre et tables inconnues, FR-024) ; ajouter une bibliothèque d'édition TOML (dépendance non justifiée).

## R6 - Catalogue de réglages et dérive

- **Constat** : 171 clés scalaires (96 hors rail + 75 du rail ; la table héritée `fx.rail.header` et ses 16 clés ne sont pas comptées). Les validations de plage sont réparties : clamps silencieux dans `Config.swift` et `RailSettings.swift:150-241`, erreurs dans `ConfigValidationRules`. Les clés connues sont dans `ConfigValidationRules.knownKeys` (`Config.swift:1216`, privé, type privé). Certaines clés sont « sans effet » (`ineffectiveKeys`, `Config.swift:1258`) : `desktops.enabled|count|back_and_forth|mode`, `stage_manager.enabled|hide_strategy`. Le fichier réel contient des clés inconnues du code (`persistence_ms`, `halo_enabled`, l.369-372) : le validateur les signale comme inconnues.
- **Décision** :
  - **Nom d'un réglage = `table.clé`** : chemin de la table sans le préfixe `experimental.` ni `fx.`, puis la clé du fichier. Il est unique, car deux clés de même nom vivent dans des tables différentes (`target_mode.enabled`, `app_targets.enabled`, `rail.header.display.font_size`, `rail.stage_labels.font_size`). La catégorie de la fenêtre est une donnée séparée du descripteur.
  - « Tous les réglages » (SC-007) = toutes les clés scalaires **reconnues** par le validateur, hors clés sans effet et hors table héritée `fx.rail.header`. Le catalogue en décrit 167 (171 − 6 sans effet + 2 nouvelles). Les clés inconnues du code ne sont pas montrées.
  - API publique de lecture ciblée pour le test : `RoadieConfigLoader.knownScalarKeys() -> [String: Set<String>]` et `RoadieConfigLoader.ineffectiveKeys() -> [String: Set<String>]` (tables → clés), dérivées des tables privées existantes. Le test de dérive vérifie : chaque clé scalaire connue (hors sans effet, hors liste, hors tableau de tables) a un descripteur, et chaque descripteur correspond à une clé connue.
  - Test de défauts : chaque défaut du catalogue est comparé au défaut de `RoadieConfig()` (encodage de la configuration par défaut) ; pour le rail, à `RailSettings.defaults`. Repli si l'encodage TOML de `RoadieConfig` n'est pas disponible : table de défauts relue à la main dans le test (non vérifié ; `RoadieConfig` est `Codable`).
- **Rejeté** : générer le catalogue depuis le code (les libellés français et les plages ne s'y trouvent pas) ; des noms `catégorie.clé` (collisions entre tables) ; des noms français à synchroniser à la main.

## R7 - Fenêtre de réglages dans un daemon `accessory`

- **Constat** : `roadied` est `.accessory` (`main.swift:147`), `LSUIElement=true`, sans menu principal. Tous les panneaux sont des `NSPanel` non activants dessinés à la main (`collectionBehavior` avec `.fullScreenAuxiliary` pour `TargetOverlayWindow`, `TargetOverlayPresenter.swift:1117-1127`). Il n'existe aucune vraie fenêtre avec contrôles ni SwiftUI. Seul précédent : `NSApplication.shared.activate()` avant une alerte (`RailController.swift:555`). Roadie exclut de son tiling les fenêtres de son propre processus : filtre `pid != currentPID` (`SystemSnapshotProvider.swift:617-640`).
- **Décision** :
  - `NSWindow` (titre « Réglages Roadie », redimensionnable, taille minimale 760×520) avec un `NSHostingController` SwiftUI.
  - Fenêtre unique conservée par un contrôleur statique ; une seconde demande appelle `makeKeyAndOrderFront`.
  - **Activation et focus (corrigé le 2026-10-13, T041)** : `NSApp.activate()` est refusé à un processus d'arrière-plan (macOS 14) : la fenêtre restait derrière les fenêtres de l'application active, invisible (constaté sur l'écran de l'utilisateur : fenêtre au rang 14 derrière Teams et T3 Code). La fenêtre est donc un `NSPanel` `.nonactivatingPanel` flottant : `orderFrontRegardless()` + `makeKey()`, sans jamais activer le daemon, centré sur l'écran du pointeur. L'application de l'utilisateur reste l'application active ; il n'y a plus de focus à restaurer. La fenêtre ne fait pas partie du tuilage : elle ne reçoit aucune commande de la boîte.
  - **Spaces** : `collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]`, pour qu'elle s'ouvre sur le bureau courant, y compris sur un Space plein écran.
  - Politique `accessory` conservée : pas d'icône dans le Dock.
  - Pas de menu principal : la fenêtre gère elle-même Échap (`cancelOperation`) et Cmd + W (`performKeyEquivalent`). Échap pendant l'édition d'un champ texte ne ferme pas la fenêtre.
  - **Suivi du fichier** : `RailFileWatcher` (réutilisé : `init(path:onChange:)`, `start()`, `stop()`). Il ne démarre pas si le fichier est absent (`open` échoue) ; la fenêtre le redémarre à chaque ouverture et relit aussi les valeurs à chaque prise de focus (`windowDidBecomeKey`).
- **Tuilage** : la fenêtre est exclue par le filtre de pid tant que `roadied run` la crée dans le processus qui fait le snapshot (cas du lancement installé). Le filtre par nom (`roadied`/`roadie`) ne protège que les fenêtres d'un autre processus roadied ; sa casse n'est pas vérifiée. L'heuristique `isLikelyTransientSettingsWindow` exige l'absence de bouton plein écran ; elle ne protège donc pas une fenêtre redimensionnable. Elle n'est pas un filet de sécurité.
- **Vérifications manuelles** (quickstart §3) : activation et clavier, Échap, Cmd + W, restauration du focus, ouverture depuis un Space plein écran, non-tuilage.
- **Rejeté** : fenêtre AppKit pure (3 fois plus de code pour 167 contrôles) ; fenêtre HTML (nouvelle dépendance web).

## R8 - Taille des étiquettes

- **Constat** : police 13 pt `.semibold` en dur (`TargetOverlayPresenter.swift:1378`) ; badge de 24 pt de haut et 28 pt de large minimum (l.1223) ; marges et pas de placement 10, 6, 6, 4 (l.1245-1279). Les sessions lettres et recherche créent leurs fenêtres en style `.labels` sans config ; la grille reçoit `TargetOverlayStyle.grid(config)`. `TargetOverlayStyle` est le seul objet qui arrive jusqu'à `TargetOverlayView`.
- **Décision** : `TargetOverlayStyle` gagne `labelFontSize` (défaut 13). Un facteur `scale = labelFontSize / 13` s'applique à : police, hauteur et largeur minimale du badge, rayon, `gap`, `inset`, pas de placement, marge d'évitement. Les épaisseurs de trait ne changent pas. La barre de saisie de la recherche garde sa police de 15 pt (la demande porte sur les étiquettes).
- **Clés** : `experimental.target_mode.label_font_size` et `experimental.target_grid.label_font_size`, Double, défaut 13, plage 8 à 48 (clamp au décodage comme les autres, erreur de validation hors plage).
- **Tests** : `TargetOverlayStyle` calcule `scale` ; un test vérifie les dimensions du badge pour 8, 13, 20 et 48 points (le badge reste plus petit que l'écran de test 1280×720, `clamped` le garde dans l'écran) et que 13 reproduit exactement les valeurs actuelles (24 de haut, 28 de large minimum). Le chevauchement des étiquettes relève du repli de placement existant (`candidateOrigins`) : non modifié, mesuré à l'écran (quickstart §5).
- **Injection** : `startTargetsInteractive` et `startTargetsSearch` lisent `effectiveConfig.experimental.targetMode` et passent le style ; la grille utilise déjà `TargetOverlayStyle.grid(config)`.

## R9 - Historique des commandes

- **Constat** : l'état persistant utilise `JSONPersistence` (`load`, `write`) sous `~/.local/state/roadies/`.
- **Décision** : fichier `command-history.json` (liste de chaînes, 50 au plus, la plus récente en dernier, doublon consécutif ignoré). Lecture à l'ouverture de la boîte, écriture après une commande réussie.

## R10 - Journal

- **Constat** : `EventLog` accepte des types d'événements libres (`config.reload_applied` n'est pas dans le catalogue de `AutomationEventCatalog`).
- **Décision** : événements `settings.changed` (nom du réglage, résultat `applied` ou `rejected`) et `command.rejected` (nom de la commande si elle est connue, sinon `unknown`, et code de la raison). Le journal ne reçoit **ni la valeur d'un réglage, ni la saisie brute** : des réglages comme `directory` ou `template` peuvent contenir un chemin ou un texte personnel. L'historique de commandes n'est pas journalisé. Pas de modification du catalogue.

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
