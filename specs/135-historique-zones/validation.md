# Validation - Session 135

**Date** : 30 octobre 2026

- `scripts/test --no-parallel` : 2 339 tests dans 348 suites réussis (68,1 s).
- Roadie installé (PID 51230, santé 5/5, signature roadied-cert, configuration valide). Raccourcis enregistrés :
  `target_mode.zone_hotkey` « alt+tab » et `target_mode.zone_back_hotkey` « shift+alt+tab ».
- ⌥Tab libre : BTT n'a que ⌘Tab et ⌘⇧Tab sur Tab ; la règle Karabiner « Tab tenu = ⌃⌥ » ne vise que Tab seul.
- Configuration sauvegardée (`roadies.toml.bak-135-*`) avant l'ajout de `zone_history_hotkey = "alt+tab"`.

## Limites

- Parcours réel (zone cliquée, changement de stage, ⌥Tab) laissé à l'utilisateur : frappes simulées refusées sur ce
  poste ; aucun diaporama. L'historique commence à cette installation.
- Zone dans une page qui a défilé ou changé : l'élément mémorisé peut avoir disparu ; si la fenêtre a gardé sa taille,
  le clic suit la position relative, qui peut alors viser autre chose.

## Corrections après essai (30 octobre 2026)

- **Une seule zone gardée** : trois clics sur des lignes différentes de T3 Code (`…1.2.6`, `…1.2.0`, `…1.2.7`,
  fenêtre 299224) ne laissaient qu'une zone, leur titre étant le nom de rôle « AXButton » et la clé fenêtre + texte.
  Clé désormais fenêtre + place (8 points près) ; texte montré : le titre, ou le premier texte visible quand le titre
  n'est qu'un rôle. Test `distinctPlacesWithTheSameTextAreDistinctZones`.
- **Cartes visuelles** à la demande de l'utilisateur : vignette de 440 × 260 points autour de la zone, capturée par
  ScreenCaptureKit juste après le clic (`~/.roadies/zone-thumbs/`, effacée quand la zone sort de l'historique), zone
  entourée en jaune, icône et texte dessous, carte choisie bordée ; 7 cartes au plus. Sans capture : icône de
  l'application. Tests `thumbnailCropsAroundTheZoneAndRingsIt`, `droppedZonesAndThumbnailsAreReported`.
- Suite complète : 2 342 tests dans 348 suites. PID 28261, santé 5/5, signature roadied-cert.
- Non vérifié : capture réelle et rendu des cartes (frappes simulées refusées) ; les vignettes contiennent le contenu
  des fenêtres de l'utilisateur, gardé en local seulement.
- **Vignette dans un quart de carte** (écran 4K de l'utilisateur à 1 pixel par point) : quarts mesurés sur les PNG
  enregistrés, 0,35 / 0 / 0 / 0. Capture rejouée sur la fenêtre réelle : sans `scalesToFit`, 1,00 / 0,01 / 0 / 0 ;
  avec, 1,00 / 1,00 / 1,00 / 1,00. `scalesToFit` et `preservesAspectRatio` ajoutés, comme pour le rail ; les deux
  vignettes fausses supprimées.
- **Deux traits jaunes** : zone de 439 points de large dans une vignette de 440 ; l'entourage débordait à gauche et à
  droite. Il est désormais gardé dans l'image affichée (test sur ces valeurs).
- **Photos floues** : 440 × 260 points réduits dans une vignette de 228 × 136 (texte à moitié taille), et capture
  agrandie deux fois sur l'écran 4K à 1 pixel par point. Désormais 300 × 180 points affichés à l'échelle 1 dans des
  cartes de 312 points, capture à la densité réelle de l'écran de la fenêtre (`scale(forWindowFrame:)`) ; 4 cartes sur
  l'écran du portable, 7 sur le 4K. Captures à l'ancien format supprimées. Journal `zone.thumbnail` (raison d'un échec).
