# Recherche - 048

## Mesure de départ (constitution XXII, étapes 1-2)

`mesures/avant.json` : 18 octobre 2026, PID 64518, inactivité 62,9 s au début,
fenêtre de 120 s. CPU 13,74 s, soit 11,45 % d'un cœur ; RSS 112 Mo.
Échantillon 10 s (`~/.roadies/diagnostics/2026-10-18-session048/avant-sample.txt`, empreinte dans `mesures/echantillons.sha256`) : relevé AX complet 539 échantillons,
énumération ScreenCaptureKit 298, configuration courante 96, bordure 69.

## Attribution (étape 3)

Appelants de `LiveSystemSnapshotProvider.windows()` dans l'échantillon :
environ 460 échantillons viennent de `SnapshotService.readerSnapshot` (lecteurs :
bordure 0,12 s, poignées de séparation 0,15 s, rail 1 s), 51 du tiler.
L'énumération ScreenCaptureKit vient de `RailThumbnailStore.capture`.

## Causes (étape 4)

- A-01 : `readerSnapshot` n'accepte qu'un relevé de moins de 150 ms
  (`SnapshotProcessState.sharedSnapshotMaxAge`). Les minuteries de 120 et 150 ms
  relancent donc un relevé complet plusieurs fois par seconde, même sans aucun
  changement. Les poignées demandent `followFocus: false`, rangé dans une autre
  entrée du cache.
- C-01 : `SCShareableContent.excludingDesktopWindows` énumère toutes les fenêtres du
  système à chaque lot, environ une fois par seconde, pour retrouver quelques
  `SCWindow` dont la fenêtre existe déjà.
- C-02 : chaque seconde, le rail relit et décode `recording.json` avant la comparaison.
- C-03 : sur l'écran concerné, `RailPanel.render` détruit et recrée toutes les cartes
  quand seule une vignette a changé.

## Décisions

- A-01 : génération d'observation incrémentée à chaque demande de passe non périodique
  (événements AX, NSWorkspace, commandes, écrans). Un lecteur réutilise le dernier
  relevé publié si la génération n'a pas changé, jusqu'à 1 s, avec les mêmes contrôles
  d'état et de configuration. Les commandes gardent la règle des 150 ms.
  Révisé après la revue du plan : plafond égal au filet du tiler (2 s par défaut), activé
  seulement par le tiler avec événements en direct (ADR 015).
  Alternative écartée : clé légère « fenêtre active + cadre CG » propre à la bordure.
  Elle ne couvre ni le rail ni les poignées, et demande encore deux relevés par seconde
  pour l'occlusion. ADR 015 complète l'ADR 013.
- C-01 : garder les `SCWindow` par identifiant. Énumérer seulement si un identifiant
  demandé manque, ou après un échec de capture. Taille de capture tirée du cadre connu
  du membre, pas du cadre `SCWindow` mémorisé.
- C-02 : statut d'enregistrement mémorisé, relu sur l'événement du watcher ; à chaque
  tick, seule la vivacité du processus est vérifiée.
- C-03 : signature de structure séparée des révisions de vignettes ; si seules les
  vignettes changent, mise à jour des images des cartes existantes.

## Limites

Le CPU au repos dépend des applications ouvertes. Les mesures avant/après sont faites
le même jour, avec les mêmes applications, et restent indicatives.
L'audit du 15 octobre n'est plus sur le disque ; la liste des constats vient du rapport
transmis à l'utilisateur et de la relecture du code actuel.
