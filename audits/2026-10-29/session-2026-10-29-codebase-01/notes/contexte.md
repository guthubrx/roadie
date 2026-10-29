# Contexte d'audit - base de code complète, Roadie 0.11.0

Révision figée : 3c9d66d993eb6e9e86e78e711653e32cf25b9886 (main, 29 octobre 2026), copie propre
`/tmp/roadie-audit-129` créée par `git worktree add --detach`. Mode readonly, un cycle. Inventaire du
moteur : 1 403 fichiers non ignorés. Sources Swift : 71 510 lignes (RoadieDaemon 62 730, RoadieCore
3 773, RoadieAX 2 525, RoadieTiler 1 448, roadied 746, RoadieStages 276).

Dernier audit complet : session 093 du 27 octobre 2026 (5ed75b05). Depuis, 247 commits et
109 fichiers de sources modifiés (+8 913/-1 839 lignes), surtout le lanceur (sessions 094 à 125) et
la traduction de l'interface (126, 127). Le cœur du tuilage (LayoutMaintainer, StageStore, socket,
persistance) a très peu changé : +147/-9 lignes, lues intégralement.

## Biens, acteurs, entrées

Biens : configuration TOML, état des stages et des bureaux, disposition des fenêtres, workflows et
leurs réglages, historique et signets des navigateurs lus localement, classement appris, raccourcis
BTT de l'utilisateur. Acteurs : utilisateur local, applications locales du même compte, auteurs de
workflows Alfred importés. Entrées : CLI et socket local 0600, fichiers de configuration, archives de
workflows (code exécutable avec les droits de l'utilisateur), saisie de la barre, API macOS (AX,
Carbon, LaunchServices, SkyLight), bases SQLite et fichiers de session des navigateurs.

## Invariants examinés

- Un script de workflow est du code de confiance de l'utilisateur ; la saisie de la barre ne doit pas
  être injectée hors des règles d'échappement choisies par le workflow.
- Une commande ne doit pas écrire hors des dossiers prévus (`workflowDirectoryName`, réglages gardés).
- Les lectures des navigateurs se font sur une copie temporaire privée, supprimée après lecture.
- Les processus lancés sont bornés (délai, plafond de sortie, groupe de processus).
- Les résultats asynchrones tardifs de la barre sont écartés (clé et argument courants).
- Les magasins du lanceur sont bornés (historique 20, classement élagué, cache Script Filter 200).
- La langue de l'interface est fixée au démarrage ; un texte traduit ne sert pas d'identifiant.

## Lectures intégrales ou ciblées

Intégrales : AlfredBridge, AlfredScriptRunner, LauncherTerminal, LauncherSystemCommands,
LauncherWebHistory, FloatingWindowTitles, UILanguage, RoadieCommandHotkeys, LauncherBTTPause
(BTTRoadieTriggers 100-174), AlfredFileFilter, changements du routeur CLI, de ConfigFileEditor,
SettingsService, SystemSnapshotProvider, StageStore et roadied/main depuis 5ed75b05.
Ciblées : LauncherBookmarks (copie SQLite, favoris, LZ4), LauncherOpenItems (osascript borné,
onglets Firefox), TargetOverlayPresenter (Script Filters, relance, annulation), TargetModeRuntimeController
(barre vide, documents et onglets ouverts), AlfredWorkflowEngine (Run Script, NSAppleScript, File
Filter), SettingsViewModel (relance de langue), WindowBookmarkCommands (bascule d'espace),
WindowRuleMatcher (cache des expressions), contextes des 45 signaux SwiftLint.

Recherches transverses : lancements de processus (13), `-c` de shell, NSAppleScript, SQLite,
`@unchecked Sendable` et `nonisolated(unsafe)` (46), attentes bloquantes, textes français restés hors
`tr`, comparaisons de textes traduits, recherches linéaires dans des boucles (181 signaux
heuristiques, ceux des chemins chauds relus).

## Hors lecture

Les vues SwiftUI des paramètres (environ 6 000 lignes), le rendu de la vue d'ensemble, la majorité de
LayoutMaintainer (4 300 lignes) et de DaemonSnapshot (2 500 lignes) n'ont pas été relus ligne à ligne
dans cette session ; ils ont été audités les 13, 18 et 27 octobre et n'ont pas changé depuis. Aucun
parcours graphique réel n'a été rejoué. Les spécifications historiques (128 dossiers) ne sont pas
toutes rapprochées du code ; seules 088 (délais des scripts) et 127 (traduction) l'ont été.
