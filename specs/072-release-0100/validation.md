# Validation de Roadie 0.10.0

## Périmètre
Version mineure depuis v0.9.0 : session 071 (aperçu en direct des déplacements avec
fantômes, création d'une stage ou d'un bureau en déposant dans le vide, centrage
vertical, visée sur la disposition affichée, contour bleu unique de la stage qui reçoit
une fenêtre) et complément 068 (refus de taille conservé quand l'application revient
d'elle-même). Publication demandée le 25 octobre 2026.

## Vérifications
Suite Swift : 1 960 tests dans 249 suites réussis (`scripts/test --no-parallel`).
Tests de scripts : 28 réussis. Aucun tiret cadratin dans les textes ajoutés.

## Paquet vérifié
Construit par `scripts/package-dmg`. DMG de 10 678 324 octets, `hdiutil verify` valide,
monté en lecture seule puis démonté. Roadie.app et lien Applications présents. Bundle
0.10.0, minimum macOS 14.0. Daemon et CLI 0.10.0, arm64. `codesign --verify --deep
--strict` réussi. UUID du daemon : DDA396F8-CAA4-3E8C-A92E-1D21BF4E7885.

```text
3e3f8055ee477ad36f44e77070707974d12de0fac8a8665ff194035cd1182cec  Roadie.dmg
```

## Revue indépendante
Non réalisée pour cette publication.

## Publication et vérification GitHub
https://github.com/guthubrx/roadie/releases/tag/v0.10.0 - Latest, hors brouillon et
hors préversion, publiée le 25 octobre 2026 à 12:06:50Z. Tag annoté v0.10.0 sur
410ed34a, référence distante contrôlée. `main` avancé sans commit de fusion et poussé.
Notes FR et EN relues par l'API : identiques au texte préparé, à une ligne vide finale
près. Roadie.dmg et Roadie.dmg.sha256 retéléchargés : identiques au paquet local,
`shasum -a 256 -c` OK.

## Installation locale
Roadie 0.10.0 installé, UUID identique au paquet, PID 5655, santé 5/5, certificat
roadied-cert conservé, configuration identique avant et après.

## Nettoyage
Branche locale `session-071-apercu-direct` supprimée après fusion. `dist/`, compilations
debug et release, fichiers temporaires supprimés ; index de compilation de l'éditeur
conservé. Worktree de conversation conservé, détaché sur `main`.

## Limites
Distribution arm64, macOS 14 et ultérieur, signée ad hoc, non notarisée. Aperçu en
direct vérifié par tests natifs et rendus sur données fictives, puis essayé par
l'utilisateur. Après un redémarrage, une fenêtre à taille imposée peut encore changer
deux fois de taille avant que le refus soit retenu.
