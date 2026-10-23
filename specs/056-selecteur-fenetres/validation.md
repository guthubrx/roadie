# Validation de la session 056

## Sources et périmètre

Implémentation originale du sélecteur pour les fenêtres gérées par Roadie.
Sources AltTab et choix de périmètre : `research.md`, `spec.md` et `contracts.md`.
Trois lots séparés intégrés : réglages, modèle/navigation/AX et interface/clavier.
Contrats puis intégration et tests sur le Mac. Aucun code AltTab importé.

## Vérifications du 23 octobre 2026

- Source installée : `0da9e099`.
- Tests ciblés initiaux : 135 tests dans 15 suites, succès. Après grille latérale,
  CLI externe et gestion des erreurs : 101 tests dans 13 suites, succès.
- Suite complète finale : 1 849 tests dans 222 suites, succès (32,909 s),
  via `scripts/with-xcode swift test --jobs 2 --no-parallel`.
- Après le dernier ajustement de rechargement : 88 tests dans 11 suites, succès.
- Scripts : 28 tests, succès, dont le nombre de tâches de compilation demandé
  à l'installation et le refus d'une valeur invalide.
- Aucun benchmark : machine chargée. Ces durées ne sont pas une mesure de performance produit.
- Rendus AppKit hors écran : vignettes, icônes et liste ; sélection, taille de police
  et hauteur bornée contrôlées. Ce sont des fixtures, pas des captures du bureau.

## Revue indépendante

Première revue sur `83019d7d`, lecture du diff depuis `40aa7519` :

1. `--no-target-mode` : démarrage du sélecteur désormais séparé en mode standard.
   Le processus modulaire `target-mode` conserve les deux interfaces.
2. Limite de seize applications : supprimée. Toutes sont consultées, avec au plus
   quatre acquisitions AX simultanées ; test sur dix-sept applications.
3. Fenêtre absente du relevé : restauration avant disposition, nouveau relevé,
   puis cadre mémorisé si AX reste indisponible. Deux variantes couvertes.
4. Observation synthétique : aucune mise à jour de signet depuis la carte.
   L'appartenance est revérifiée sous verrou ; une sélection périmée échoue.
5. Lecture : copie du SnapshotService sans écriture d'observation. La navigation
   ne réaffecte pas les membres. Erreurs de placement rapportées.
6. MRU : observation du focus publié et diffusion entre processus modulaires.
   Les changements réels par clic ou Cmd+Tab restent à confirmer au bureau.
7. Actions AX : délais et quarantaine existants conservés ; aucune mesure de
   latence revendiquée. Les collisions Carbon sont journalisées.

Deuxième revue ciblée sur `ce58c06d` : quatre premiers points confirmés corrigés.
Compléments traités : erreur visible après action ou activation refusée, panneau
conservé pour réessayer ; rechargement annulé et génération vérifiée ; restauration
refusée avec retour d'état conditionnel si aucun autre écrivain n'a modifié le
store ; démasquage après transaction ; focus confirmé après placement.
Tests ajoutés : refus de restauration, concurrence pendant l'échec, refus de
cadre distinct de l'échec de focus, retour de la session en mode persistant.

L'utilisateur confirme le parcours Ctrl+Alt+Tab installé, puis demande la grille
latérale et un raccourci externe Cmd+Tab. Ce changement est dans la même session.
Les raccourcis internes restent facultatifs et vides par défaut.

## Installation et essai réel

Première installation `ce58c06d` : UUID 0BBF207B-370A-34A8-A8F4-FD09EBC8F684,
PID 60231, santé 5/5. Ouverture CLI constatée dans WindowServer : panneau
« Sélecteur de fenêtres Roadie », niveau 26, 1100 × 612 points ; disparition
après annulation. Capture réelle examinée localement. L’utilisateur confirme
le parcours Ctrl+Alt+Tab, Maj inverse, relâchement et contexte propriétaire.
Le journal contient des activations réussies, par exemple le 23 octobre à
03:06:17 UTC et 03:08:39 UTC. Ces événements ne constituent pas un benchmark.

Installation finale : UUID E71B3887-DD49-3060-87CA-162E9307A4F5 (arm64),
PID 8089, santé 5/5. L'inode 610462448 de l'exécutable installé correspond
à celui ouvert par le processus. Build Release, installation et relance terminés.
Une capture réelle du panneau final (1100 × 536 points) confirme le champ de
recherche sur toute la largeur et la grille à droite du grand aperçu. Ouverture
et annulation par CLI vérifiées. Le nouvel appui physique Cmd+Tab reste à confirmer.
Configuration inchangée après installation : SHA-256
`ca42b5c670755e1b39371b1157c116c31e0754930800ad2551841fe5a3f05629`.
Certificat conservé : `78a75e8032f190a20072eb91cc2919aac344ef78`.

Preuves partielles : CUA retourne `CUA_REPL_ENABLED_SURFACES is required`.
Le terminal dispose de la capture écran, mais pas de l’injection Accessibilité.
La capture réelle contient des documents de travail ; elle reste dans les
preuves locales hors Git. Aucun clic annoté n’est inventé. Le parcours clavier
initial est confirmé par l’utilisateur ; les rendus hors écran ne le remplacent pas.

## BetterTouchTool

API AppleScript uniquement ; base SQLite lue et sauvegardée avant mutation.
Dossier Roadie > 5 - Modes interactifs, parent `C30FADE0-5BEC-4C7E-B2D3-BBB3A18C887A`.
Aucun trigger Tab préexistant trouvé. Deux triggers préparés puis activés après installation :

- `E28BDB53-9C0B-4A16-82B1-734D305B6CB9` : Cmd+Tab, keycode 48,
  masque 1048576, configuration additionnelle 1048584 ;
- `E93DEAC3-71E8-499B-AE46-9A44A2BCE0AE` : Cmd+Maj+Tab, keycode 48,
  masque 1179648, configuration additionnelle 1179658.

`BTTShellTaskActionScript` contient la commande brute ; `BTTShellTaskActionConfig`
contient `/bin/bash:::-c:::-:::` suivi de la même commande. Les commandes sont
`/Users/moi/.local/bin/roadie switcher cycle --hold cmd` et la même avec `--backwards`.
Les deux flags BTTEnabled et BTTEnabled2 sont à 1 : API et base relues.
L'API omet ces champs lorsque leur valeur vaut 1 ; leur valeur effective a donc
été vérifiée dans la base en lecture seule. Parent et commandes exactes vérifiés.
Le fichier Roadie n’a pas de section switcher : son défaut hotkey vide suffit
à désactiver le raccourci interne, sans modifier la configuration de l’utilisateur.


## Dernière revue après changement demandé

Diff `ce58c06d..6b185002` : aucun blocage. CLI externe, grille et gestion des
rechargements validés par lecture. Complément : la liste est rechargée après un
échec pour retirer une carte devenue obsolète. Défauts de spec corrigés. La
configuration réelle ne contient pas de raccourci interne à migrer.

Objection non retenue : un refus de cadre ne doit pas être annoncé comme un
échec de focus si le focus a réussi. Le résultat conserve `changed=true` et
`outcome=failed` avec « placement incomplete ». Le journal de focus décrit le
focus, le résultat de commande décrit le placement. Le test
`refusedFrameDoesNotClaimThatFocusFailed` protège cette distinction. Ne pas
revenir à un faux événement de focus échoué pour faire disparaître cet écart.
