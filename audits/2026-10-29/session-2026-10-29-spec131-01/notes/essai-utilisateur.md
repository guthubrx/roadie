# Essai réel de l'utilisateur (axes.quality.03) - 29 et 30 octobre 2026

Parcours essayés par l'utilisateur sur le Roadie installé au commit audité 740a0f78 puis après corrections.
Les corrections sont postérieures au commit audité ; elles sont commitées sur la branche de livraison.

## C1 - Vue Texte sans champ de saisie : plantage (HIGH, corrigé)

- Symptôme : Get info n'affiche rien. Données : `launcher.file_action info done=1`, puis redémarrage de roadied une
  seconde après (05:03:18 → 05:03:19) et un rapport `roadied-2026-10-30-050323.ips` à chaque essai (4 sur 4).
- Pile : `EXC_BAD_ACCESS KERN_INVALID_ADDRESS 0x1e` dans `swift_task_isMainExecutorImpl`, depuis
  `MainActor.assumeIsolated` d'une minuterie (`RoadieCommandHotkeys.start()`, `RestoreSafetyRuntimeController`,
  `startDaemonStatusPublisher`) : état d'exécution Swift corrompu, la minuterie n'est que la victime.
- Reproduction hors daemon (programme de laboratoire, même chemin `Task.detached` → `MainActor.run` →
  `WorkflowTextPanel.show`), arrêt sur `objc_exception_throw` (lldb) : `-[NSLayoutConstraint _setActive:…]`
  depuis `WorkflowTextPanel.layout()` ligne 121, message « Unable to activate constraint with anchors
  NSTextField.width and NSStackView.width because they have no common ancestor ». Le champ `input` n'est dans la
  pile que si `inputPlacement != .none` (lignes 95 et 97), mais sa largeur est toujours contrainte (ligne 117).
  L'exception Objective-C traverse le code Swift et laisse l'état d'exécution corrompu.
- Origine : session 117 (bd6abe3d) ; révélé par la fiche Informations de la session 131 (première vue Texte sans
  champ).
- Correction (6d17d0da) : seules les lignes de la pile sont contraintes. Test
  `Spec131MarkdownTableTests.textPanelOpensWithEveryInputPlacement` : le processus de test tombe avec l'ancienne
  contrainte, réussit avec la nouvelle. Laboratoire : « shown », minuteries vivantes.
- Variantes : `NSStackView(views: rows)` n'apparaît qu'une fois dans `Sources/RoadieDaemon` ; les ajouts de vues
  sous condition (`rows.append` dans un `if`) ne concernent que ce panneau (et des lignes de liste, sans
  contrainte). Aucune autre occurrence.

## C2 - Défilement au trackpad absent dans la barre (MEDIUM, corrigé)

- Symptôme : la grille `apps` ne défile pas au trackpad. Le masque du tap de la barre
  (`TargetSearchDismissal.eventMask`, ligne 861) n'écoute pas `scrollWheel`.
- Correction (6d17d0da) : molette ajoutée en recherche, `LauncherScroll.steps`, sélection déplacée ;
  `Spec131ScrollTests` ; `TargetSearch028DismissalTests` mis à jour. Confirmé par l'utilisateur (« apps : ok »).
- Variantes : aucun autre tap de la barre ne gère de liste défilante.

## C3 - Recherche du navigateur SF Symbols : loupe sur le texte (LOW, corrigé)

- Symptôme (capture de l'utilisateur) : la loupe recouvre le « S » du texte d'invite quand le champ a le curseur.
  `WorkflowViewStyle.decorate` (ligne 376) retire le cadre natif (`isBezeled = false`), qui réserve la place de
  la loupe d'un `NSSearchField`.
- Rendus de laboratoire : `recherche-symboles-avant.png` reproduit la capture ; `recherche-symboles-apres.png`
  propre, curseur actif.
- Correction (6d17d0da) : un champ de recherche garde son cadre natif.
- Variantes : `decorate` n'est appelé que sur le champ de la vue Texte (`NSTextField`) et celui-ci.

## C4 - Créer un alias sans retour visible (LOW, corrigé)

- Symptôme : l'alias était créé (fichier présent, 21:17) mais rien ne le montrait (ligne 1973).
- Correction (6d17d0da) : les alias créés sont montrés sélectionnés dans le Finder.

## Autres retours d'ergonomie

- La fiche Informations jugée moins utile que le Finder : remplacée par la fenêtre ⌘I du Finder (1d67637b), à la
  demande de l'utilisateur ; confirmé « ça marche ».
- Grille `apps`, menus, verbes de fichiers : confirmés par l'utilisateur.
