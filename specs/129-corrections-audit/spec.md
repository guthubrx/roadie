# Session 129 - Corrections de l'audit V15 du 29 octobre 2026

Demande : « on corrige TOUT ! » après l'audit de la base de code complète
(`audits/2026-10-29/session-2026-10-29-codebase-01`, décision `inconclusive`, aucun défaut grave).
Session de correction, validée d'office (consignes utilisateur).

## Exigences

- **FR-001 Actions sans délai.** Run Script, Run NSAppleScript, tâches d'automatisation et Run Shortcut
  vont à leur terme, comme dans Alfred. Les filtres (Script Filter, File Filter, vues de grille) gardent
  10 s (SPEC-088 FR-004). Constats `REL-SCRIPT-TIMEOUT` (trois instances) et variante Run Shortcut (30 s).
- **FR-002 Commandes système.** Les scripts des commandes système de la barre attendent jusqu'à 600 s
  (mot de passe de « Reconstruire l'index Spotlight », confirmation d'une fermeture de session). Un échec
  (numéro d'erreur AppleScript, osascript sans réponse, processus non lancé) est signalé par une
  notification ; une annulation par l'utilisateur (-128) reste silencieuse. Constat `REL-AUTH-TIMEOUT`.
- **FR-003 Index des littéraux.** Une clé à valeur vide (ou réduite à un commentaire) est refusée, et sa
  redéfinition reste un doublon refusé, comme dans `readLiteral`. Constat `DATA-LITERAL-INDEX`.
- **FR-004 Onglets de Firefox.** Parcours en largeur en O(n) (file lue par un indice). Constat
  `PERF-QUADRATIC-BFS`.
- **FR-005 Restes de l'audit.** Fonctions sans appelant retirées (`LauncherBookmarkStore.load`,
  `LauncherWebHistoryStore.load`, `LauncherWebHistory.matches(in pages:)`), chemin de configuration de
  `UILanguage` repris de `RoadieConfigLoader`, deux messages `launcher batch` traduits.

## Hors périmètre

Observations de l'audit sans défaut : lecture d'archive `.sfl` sans codage sûr (fichier écrit par macOS),
attente de 1,8 s au plus de la bascule d'espace (ADR 020), requête des fichiers récents sans plafond
(lue en fond), `UILanguage.current` modifiable par les rendus de captures en test séquentiel.

## Limite acceptée

Une action de workflow qui ne se termine jamais n'est plus arrêtée, comme dans Alfred ; elle s'arrête
avec son groupe de processus seulement si l'utilisateur la tue.
