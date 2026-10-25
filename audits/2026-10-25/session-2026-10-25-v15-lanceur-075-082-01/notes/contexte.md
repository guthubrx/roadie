# Contexte - lanceur Capslock+F, sessions 075 à 082

Base 6daaa8b2 → 5400a7bc (révision 0), puis 0a579d60 (révision 1, correction F4). Sources et tests
sélectionnés : 44 fichiers ; lecture étendue aux appelants (StageCommandService.assign,
WindowContextActions.assign, LayoutMaintainer.tick, SnapshotService) et aux fichiers locaux.

## Biens à protéger
- Disposition et stages de l'utilisateur (stages.json, arbres BSP) : un aperçu ou une annulation
  ne doit jamais laisser des fenêtres déplacées.
- Règles générées (`roadies.generated.toml`) : écrites seulement sur un choix explicite, relues
  avant remplacement ; `roadies.toml` jamais écrit.
- Données privées : titres, chemins, adresses d'onglets ; aucun journal ne doit les contenir.
- Fichiers locaux `~/.roadies/launcher-*.json`, `projects.json` : jamais écrits par les tests.

## Acteurs et entrées
Utilisateur local (barre, menu de titre, CLI `roadie launch|project|undo|targets actions`),
applications tierces lues par accessibilité (AXDocument) et AppleScript (navigateurs), Spotlight.
Aucune entrée réseau, aucune authentification ; `osascript` lancé avec des scripts construits à
partir d'identifiants fixes (pas de texte utilisateur interpolé).

## Invariants vérifiés
1. Aperçu (078) : fin sans validation → cadres relevés réécrits, stage de départ remise, maintien
   relâché ; maintien à échéance 1,5 s.
2. Règle unique par application (075) : flottement et affinité dans `affinity-app-…`.
3. Abréviations et projets : seuls objets durables ; stage par nom réel (règle 067).
4. Déplacements notés seulement si la stage change ; 200 au plus.
5. Fichiers du lanceur dans un dossier temporaire pendant les tests (`TestEnvironment`).

## Inconnues et limites
Onglets non relevés en réel (autorisation d'automatisation) ; Firefox non couvert ; essais au
clavier non simulés (aucune frappe envoyée) ; démon multi-processus non essayé.
