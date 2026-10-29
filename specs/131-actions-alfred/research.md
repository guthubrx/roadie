# Recherche 131

## R1 Types d'objets d'Alfred manquants

Relevé des chaînes des binaires d'Alfred 5 installé (`Alfred Framework`, `Alfred Preferences`) le 29 octobre 2026 :
familles `action.*`, `input.*`, `output.*`, `trigger.*`, `utility.*`, `automation.*`, `userinterface.*`.
Absents de Roadie : `action.systemcommand`, `action.itunescommand`, `input.dictionaryfilter`,
`input.runningappsfilter` (plus `trigger.snippet`, `trigger.contact`, `input.confacfilter` et
`input.snippetfilter`, écartés). Réglages (schéma public `y-marui/alfred-clean-invisible-text`,
`docs/alfred-workflow-notes/workflow-object-schema.md`) :

- `systemcommand` : `command` (entier), `confirm` (booléen).
- `itunescommand` : `command` (entier).
- `dictionaryfilter` : `keyword`, `language`, `showallwords`, `title`, `subtext`.
- `runningappsfilter` : `keyword`, `withspace`, `argumenttype`, `outputtype`, `outputprefix`, `title`, `subtext`.

## R2 Numéros des commandes système

Ordre affiché d'Alfred (chaînes `ActionSystemCommand`) : Screensaver, ShowTrash, EmptyTrash, LogOut, Sleep,
SleepDisplays, LockMac, Restart, ShutDown, MusicVolumeUp, MusicVolumeDown, MusicVolumeMute, QuitAll, EjectAll.
Numéros enregistrés, relevés dans 40 workflows publics (GitHub, recherche de code) et reliés à leur mot-clé ou
raccourci :

| N° | Commande | Preuve |
|---|---|---|
| 1 | Économiseur d'écran | « Pause And Start Screen Saver » (ianferguson) |
| 2 | Afficher la corbeille | note « Show Trash » (mchoun) |
| 3 | Vider la corbeille | déduit (ordre) |
| 4 | Fermer la session | déduit (ordre) |
| 5 | Suspendre l'activité | « Sleep » (h1st0ry3D) |
| 6 | Verrouiller | « Lock-Screen », Win+L (morganestes) |
| 7 | Redémarrer | « Immediate Restart » (vitorgalvao), Win+R |
| 8 | Éteindre | « Immediate Shutdown » (vitorgalvao), Win+U |
| 9 | Tout quitter | ⇧⌘F4 « Quit all » (README morganestes) |
| 10 | Tout éjecter | déduit (« Shut Down Dev » : 9 puis 10) |
| 11 | Suspendre les écrans | « Sleep Display » (jesselumarie) |
| 12-14 | Volume +, Volume −, Muet | déduit (ordre des identifiants restants) |

Décision : table ci-dessus ; un numéro hors table arrête la chaîne avec « commande inconnue » (jamais deviné).
`confirm` : second Retour, comme les commandes lourdes de la barre (session 105).

## R3 Numéros des commandes Musique

Identifiants d'Alfred : PlayPause, Next, Previous, Random Album, VolumeMax, VolumeMid, VolumeMute, Rating.
Relevé (25 workflows) : 1 lecture/pause (« play », « pause »), 2 suivant (« next »), 3 précédent (« previous »),
13 note ★★★★★ (« Rate track ★★★★★ »), 6 et 7 sur ⌥⌘8 et ⌥⌘2 (volume + et − probables). Décision : 1, 2, 3,
4 album au hasard, 6 volume +, 7 volume −, 9 à 13 note de 1 à 5 étoiles ; 0 ouvre Musique ; autres : inconnue.
Exécution par AppleScript sur `Music` (nom d'application de macOS depuis 10.15).

## R4 Définitions du dictionnaire

`DCSCopyTextDefinition` (CoreServices, public) donne la définition du mot dans les dictionnaires actifs de
macOS. Liste dans la barre : mot, première ligne de définition ; Retour passe le mot, ⌘Y ouvre Dictionnaire
(`dict://mot`). `showallwords` : mots qui commencent par la saisie, via `NSSpellChecker.completions`.

## R5 Applications ouvertes

`NSWorkspace.runningApplications` (politique normale), filtrées par la saisie avec `LauncherMatch`. Argument :
chemin de l'application (`outputtype` 0), ou nom ; `outputprefix` ajouté devant.

## R6 Sujet texte et sélection

`TargetModeRuntimeController.selectedText()` lit déjà `kAXSelectedTextAttribute` de l'élément actif (ligne 904).
`targets.actions` (Capslock + Maj + F) ouvre les verbes de la fenêtre active ; une sélection non vide ouvre à la
place les verbes du texte. Texte tapé : Tab sur la ligne de repli « Texte » ouvre ses verbes. Adresses extraites
par `NSDataDetector` (liens et e-mails).

## R7 Verbes de fichier

API système existantes, sans dépendance : `FileManager.copyItem`/`moveItem`/`trashItem`, alias par
`URL.bookmarkData(options: .suitableForBookmarkFile)` puis `URL.writeBookmarkData`, étiquettes par
`URLResourceValues.tagNames`, informations par `URLResourceValues` (type, taille, dates) et SHA-256 par CryptoKit
en lecture par blocs, presse-papiers par `NSPasteboard.writeObjects([URL])`, e-mail par
`NSSharingService(named: .composeEmail)`, ouvrir avec par `NSWorkspace.open(_:withApplicationAt:)`, terminal par
`LauncherTerminal` (réutilisé). Destinations nouvelles : dossiers (Spotlight, dossiers récents et favoris du
Finder) et applications (catalogue existant). Refus si la destination existe déjà, sauf verbe « en remplaçant ».

## R8 Onglets

Safari et Chromium : AppleScript (`close tab`, `URL of tab`, `make new window`). Firefox : pas de dictionnaire ;
l'onglet est choisi par `FirefoxTabSelector` puis ⌘W ; nouvelle fenêtre par `open -na Firefox --args
--new-window URL` ; adresse lue dans sa session (déjà connue de la ligne).

## R9 Menus de l'application active

Accessibilité : `AXMenuBar` de l'application au premier plan, parcours borné (profondeur 6, 2 000 éléments,
0,8 s), éléments activés avec titre ; chemin « Fichier › Exporter… » ; Retour envoie `AXPress`. Lecture hors du
fil principal, l'application cible est mémorisée à l'ouverture de la barre.

## R10 Commandes de barre ajoutées

Mode sombre : `System Events` › `appearance preferences` › `dark mode` (comme les autres commandes de session).
Captures : `/usr/sbin/screencapture` (`-i` zone, `-iW` fenêtre, sans option écran entier) vers l'emplacement réglé
dans macOS (`com.apple.screencapture location`, sinon Bureau). Raccourcis Apple : `/usr/bin/shortcuts list` (mis
en cache), lancement par `shortcuts run`. Relancer : `terminate` puis ouverture à la fin du processus. Quitter les
autres : applications ordinaires sauf celle-ci, le Finder et Roadie.

## R11 Tâches absentes

`AlfredAutomationTasks.update` (`roadie workflow tasks update`) télécharge déjà le dépôt public. Une tâche absente
déclenche une seule mise à jour par processus, puis une nouvelle lecture ; échec réseau : message actuel.

## R12 Apps (Launchpad d'Alfred 6)

Sur macOS 26, le Launchpad est remplacé par l'application Apps (vérifié : `/System/Applications/Apps.app`).
Modèle retenu : grille de toutes les applications du catalogue, regroupées par catégorie de macOS
(`LSApplicationCategoryType`), filtrées par la saisie ; épinglage en tête gardé dans un petit fichier du lanceur.
Présentation en grille existante de la barre (sessions 092, 099).

## R13 SF Symbols

Images regardées le 29 octobre 2026 sur alfredapp.com/v6 : champ de recherche, grille de 6 colonnes, sélection
turquoise, nom et catégories dessous, à droite l'aperçu en 4 tailles et les versions minimales par système.
Données de macOS : `CoreGlyphs.bundle/Contents/Resources/name_availability.plist` (9 184 symboles et table
`year_to_release`), `symbol_categories.plist`, `symbol_search.plist`, `categories.plist` ; images par
`NSImage(systemSymbolName:)`. Panneau dédié, fidèle à ce modèle.

## R14 Styles et thèmes en verre

Images de la page Alfred 6 regardées : Glassy Dark (colonne sombre translucide, boutons ronds en bulle de verre
avec liseré), Flat Dark (même fond, boutons pleins sans verre), Glassy Light (verre clair, texte gris foncé,
sélection couleur d'accent). Décision : réglage `workflow_view_style` (`theme`, `glassy-dark`, `flat-dark`,
`glassy-light`) appliqué aux panneaux Texte, Image, PDF et SF Symbols ; verre par `NSVisualEffectView`
(`.hudWindow` sombre, `.popover` clair), bulles par un fond translucide avec liseré et reflet. Thème de barre
« Glassy Dark » et « Glassy Light » ajoutés à `LauncherTheme.builtIn`, valeurs relevées sur l'image du thème
(sélection #358188, champ plus foncé, coins de 20 points).

## R15 Tableaux Markdown

`AlfredMarkdown` découpe déjà titres, citations, listes, code. Ajout d'un bloc tableau : ligne d'en-tête, ligne
de séparation `---` avec alignements `:--`, `:-:`, `--:`, lignes de cellules ; rendu par `NSTextTable`.

## R16 Modificateurs de Retour

`LauncherVariant.of(subject:modifier:…)` choisit l'effet de ⌘, ⌥ et ⌃. Réglages `return_cmd`, `return_alt`,
`return_ctrl` dans `[experimental.target_mode]`, choix : `new-stage`, `here`, `send`, `web`, `copy`, `reveal`,
`quicklook`, `verbs`. Défauts : `new-stage`, `here`, `web`, soit le comportement actuel (session 075).
