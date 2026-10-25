# Validation de Roadie 0.9.0

## Périmètre
Version mineure depuis v0.8.0 : sessions 065 (fenêtres fermées gardées en mémoire),
066 (réordonner les bureaux), 067 (déplacer stages et fenêtres, noms de stage uniques),
068 (fenêtres à taille imposée) et 070 (glisser d'un écran à l'autre). Publication
demandée le 25 octobre 2026. Version applicative et défaut du script DMG à 0.9.0 ;
README, guides FR/EN, index, notes FR/EN et changelog alignés.

## Vérifications
Suite Swift : 1 954 tests dans 248 suites réussis (`scripts/test --no-parallel`).
Tests de scripts : 28 réussis. Aucun tiret cadratin dans les textes ajoutés.

## Paquet vérifié
Construit par `scripts/package-dmg`. DMG de 10 603 790 octets, `hdiutil verify` valide,
monté en lecture seule puis démonté. Roadie.app et lien Applications présents. Bundle
0.9.0, minimum macOS 14.0. Daemon et CLI 0.9.0, arm64. `codesign --verify --deep
--strict` réussi. UUID du daemon : FF943711-DCDA-396F-9B0D-B77B0FEAAFB3.

```text
f7c49c4cec19eab7132cac32dc1529418e208b08d11d572155c1d515e1ed59d1  Roadie.dmg
```

## Revue indépendante
Non réalisée pour cette publication.

## Publication et vérification GitHub
https://github.com/guthubrx/roadie/releases/tag/v0.9.0 - Latest, hors brouillon et hors
préversion, publiée le 25 octobre 2026 à 10:26:52Z. Tag annoté v0.9.0 sur 664f1d3d,
référence distante contrôlée. `main` avancé sans commit de fusion et poussé. Notes FR
et EN dans le même corps, relues par l'API : identiques au texte préparé, à une ligne
vide finale près. Roadie.dmg et Roadie.dmg.sha256 retéléchargés : identiques au paquet
local, `shasum -a 256 -c` OK.

## Installation locale
Roadie 0.9.0 installé, UUID identique au paquet, PID 17022, santé 5/5, certificat
roadied-cert conservé, configuration identique avant et après.

## Nettoyage
Branches locales `session-066-reordonner-bureaux`, `session-067-deplacer-stages` et
`session-070-ecrans` supprimées après fusion. `dist/`, compilations debug et release,
fichiers temporaires supprimés ; index de compilation de l'éditeur conservé. Worktree de
conversation conservé, détaché sur `main`. Sauvegardes d'état du 25 octobre conservées
dans `~/.roadies/`.

## Limites
Distribution arm64, macOS 14 et ultérieur, signée ad hoc, non notarisée. Glisser entre
écrans vérifié par tests ; essai réel à la souris non confirmé avant la publication.
Après un redémarrage, une fenêtre à taille imposée peut encore changer deux fois de
taille avant que le refus soit retenu.
