# Validation de Roadie 0.8.0

## Périmètre
Version mineure depuis v0.7.0 : sessions 060 (cinq organisations du sélecteur), 061
(vue d'ensemble, tâches T001 à T029), 062 (Mission Control) et correction CLI
`desktop focus next|prev`. Publication explicitement demandée le 24 octobre 2026.
Version applicative et défaut du script DMG alignés à 0.8.0. README, guides, index,
notes FR/EN et changelog synchronisés.

## Vérifications
Suite Swift : 1 931 tests dans 240 suites ; seul échec, le test instable connu
`daemonListeningOnSocketIsUsedEvenWithoutPidFile`, réussi relancé seul. Tests de
scripts : 28 réussis. Modules de tests recompilés de zéro avant la suite (une
compilation incrémentale périmée avait provoqué un plantage le même jour).
Liens relatifs et liens de tag des README, guides et notes contrôlés ; aucun tiret
cadratin dans les notes. Valeurs documentées (flou 20 %, contour 2 points, loupe
150 %) relues dans `OverviewConfig.swift`.

## Paquet vérifié
Construit par `scripts/package-dmg` versionné, sans recette temporaire. DMG de
10 435 451 octets, `hdiutil verify` valide, monté en lecture seule puis démonté.
Roadie.app, icône et lien Applications présents. Bundle 0.8.0, minimum macOS 14.0.
Daemon et CLI 0.8.0, arm64. Signature ad hoc contrôlée par
`codesign --verify --deep --strict`. UUID du daemon :
F5122397-3E44-3F71-8172-5D668E435652.

```text
7a14294badb98ba3224c88e622b87da91b03e71694b86aa984f675ac02810999  Roadie.dmg
```

## Revue indépendante
Non réalisée. La relecture des textes publiés a été demandée à Bridget
(`roadie-063-release-080-text-review-1`, base 4283f003) : admission refusée
(`routing_candidate_unavailable`, `permissions_changed`, 10 candidats). Aucun repli
sur un autre mécanisme. Les contrôles mécaniques ci-dessus ont été faits par le
responsable. Les revues et audits prévus en 061 (T009, T011) n'ont pas été faits
avant cette publication, à la demande de l'utilisateur de publier.

## Limites
Distribution arm64, macOS 14 et ultérieur, signée ad hoc, non notarisée. Pas d'essai
sur Intel ni sur macOS 14. Rendu des réglages de la vue d'ensemble dans la fenêtre
des paramètres non capturé. Gestes BetterTouchTool déclenchés par BTT, non au trackpad.
