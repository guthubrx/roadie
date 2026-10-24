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

## Publication et vérification GitHub
Version publiée le 24 octobre 2026 à 14:35:36Z :
https://github.com/guthubrx/roadie/releases/tag/v0.8.0 - Latest, hors brouillon et
hors préversion. Tag annoté v0.8.0 sur 7b64afe2b08933404d1af90cae5cbd3d6570c3df,
référence distante contrôlée. `main` avancé sans commit de fusion et poussé.
Notes FR et EN publiées dans le même corps ; relu par l'API : identique au texte
préparé, à une ligne vide finale près ajoutée par GitHub. Deux pièces : Roadie.dmg
(10 435 451 octets) et Roadie.dmg.sha256 (77 octets), retéléchargées : identiques,
`shasum -a 256 -c` OK.

## Installation locale
Roadie 0.8.0 installé, UUID identique au paquet (F5122397-3E44-3F71-8172-5D668E435652),
PID 52475, santé 5/5, certificat roadied-cert conservé, configuration identique avant
et après (SHA-256 b4ae077c0be644faf7d5c7ab9f486eac7b14c04dbba24fb5b2f6fd45d3b60206).

## Nettoyage
Branches locales `session-061-vue-ensemble` et `session-062-fenetres-mission-control`
supprimées (fusionnées) ; aucune branche distante de session. Worktree d'audit
obsolète `/private/tmp/roadie-061-audit-checkout` archivé hors Git puis supprimé,
références prunées. Audit du 24 octobre (version antérieure de la vue) et archive
déplacés dans `/Users/moi/.roadies/diagnostics/2026-10-24-session061/`. Une seule
paire DMG/SHA-256 0.8.0 conservée dans `/Users/moi/Nextcloud/10.Scripts/39.roadie/dist/`
(ancienne 0.7.0 remplacée). Bundle intermédiaire, dossier `dist` et compilation
`.build` du worktree, caches Python et temporaires supprimés. Checkout principal
conservé ; worktree de conversation conservé.
