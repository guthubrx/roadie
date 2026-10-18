# Constats - session 050 readonly (révision 0)

Auditeur : Claude (Opus), `independent=false`.

## H1 - réfuté - « une maximisation pendant le second appui est adoptée comme redimensionnement manuel »

- Hypothèse (lecture) : le second appui ouvre une session de geste (cadre de départ tuilé) ; la
  maximisation est écrite pendant l'appui (file principale, avant la passe de relâchement) ; au
  relâchement, `layoutGesture` voit une taille changée et `applyGesture` pourrait déplacer les
  frontières de l'arbre (`LayoutMaintainer.swift`, `applyGesture`).
- Reproduction isolée (`repro/Repro050DoubleClickGestureTests.swift`, copie du harnais de
  `Spec029ResizeTests`, exécutée dans `/tmp/roadie-repro-050`) : clic, clic, session de geste
  vérifiée sur la fenêtre 1 avec cadre de départ tuilé, `toggleMaximize(windowID: 1)` pendant
  l'appui, relâchement, passe `drag`. Résultat : arbre inchangé (ratio 0,5), aucun
  `layout_manual_gesture`, retour à 500 points au second `toggleMaximize`. Témoin sans geste identique.
- Verdict : réfuté dans le harnais (relevés et écritures simulés, horloge contrôlée). Limite :
  ordonnancement AX réel non observé.

## F1 - LOW - Défauts contradictoires entre 049 et 050 : santé en avertissement chez l'utilisateur

- Fichier : `Sources/RoadieDaemon/DaemonHealth.swift:179` (réglage Roadie transmis à la santé),
  défaut `true` (`Config.swift`, `doubleClickMaximize`).
- Observé : sur la machine de l'utilisateur, `AppleActionOnDoubleClick` est absente et
  `AppleMiniaturizeOnDoubleClick = 0` (macOS agrandit) ; la config ne fixe pas `double_click_maximize`.
  Avec ces valeurs, `macOSWindowSettingsCheck` rend `warn`, et la fonction 050 n'agit jamais.
- Conséquence : le critère de la 049 « `roadie query health` installé renvoie `ok` sur la machine de
  l'utilisateur » n'est plus atteignable sans changer un réglage macOS. Ce changement de défaut n'est
  écrit ni dans la spec 049 ni dans la 050 (la doc 050 dit seulement que la santé le signale).
- Correction : choisir et écrire le comportement voulu : défaut `false`, ou défaut `true` assumé avec
  mise à jour du critère 049 et du CHANGELOG.

## F2 - LOW - Commentaire de documentation déplacé sur le mauvais type

- Fichier : `Sources/RoadieDaemon/DaemonHealth.swift:61-63`.
- L'énumération `MacOSDoubleClickAction` est insérée entre le commentaire `///` de
  `MacOSWindowSetting` et sa déclaration : les trois lignes documentent maintenant l'énumération,
  et `MacOSWindowSetting` n'a plus de commentaire.
- Correction : déplacer les deux premières lignes au-dessus de `public struct MacOSWindowSetting`.

## F3 - LOW - Validation non consignée (T005 ouverte)

- Fichier : `specs/050-double-clic-titre/tasks.md:7` ; aucun `validation.md`.
- Suite complète, installation et santé réelle ne sont pas consignées ; seule la revue 1 l'est (T007).
- Correction : consigner suite, installation, santé et essai réel du double-clic dans `validation.md`.

## Points relus sans défaut
- Coût : un clic simple ne fait qu'une comparaison. Un double-clic, quand l'action macOS vaut « Ne rien
  faire », fait un relevé complet avant le test de barre de titre, partout sur l'écran (sélection de mot
  dans un éditeur comprise). Conforme à R4 ; même mécanisme que le constat F2 de la 051, non recompté.
- Délai AX de la requête de rôle borné à 0,5 s par le réglage global posé par le relevé qui la précède.
