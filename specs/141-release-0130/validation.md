# Validation de Roadie 0.13.0

## Périmètre
Version mineure depuis v0.12.0 : sessions 139 (Maj seule recule dans les sélecteurs, images de zones réalistes) et
140 (nombre de zones de clics par application). Publication demandée le 30 octobre 2026.

## Vérifications
Suite Swift complète : 2 354 tests dans 352 suites réussis (`scripts/test --no-parallel`, aucune suite exclue).
Tests de scripts : 28 réussis (`python3 -I -B -m unittest discover -s scripts/tests`). Aucun tiret cadratin dans
les notes de version ni les README.

## Paquet vérifié
Construit par `scripts/package-dmg`. DMG de 15 068 079 octets, `hdiutil verify` valide, monté en lecture seule puis
démonté. Roadie.app et lien Applications présents. Bundle 0.13.0, minimum macOS 14.0, arm64.
`codesign --verify --deep --strict` réussi. UUID du daemon : 4F72979A-D74A-3786-A064-DBB2EC846E14.

```text
062dc73b059b1227debaae3128df0bbb9771878f5ca7721fc1eee411bcdee4de  Roadie.dmg
```

## Publication et vérification GitHub
https://github.com/guthubrx/roadie/releases/tag/v0.13.0 - Latest, hors brouillon et hors préversion, publiée le
30 octobre 2026 à 19:51:00Z. Tag annoté v0.13.0 sur 57fe791e, poussé ; `main` avancé sans commit de fusion
(fff7b619..57fe791e). Roadie.dmg et Roadie.dmg.sha256 retéléchargés : identiques au paquet local,
`shasum -a 256 -c` OK. Captures, notes et comparaison servies (HTTP 200). Ce reçu, écrit après l'étiquette, n'est
pas dans le tag : le lien de la note publiée pointe vers `main`.

## Installation locale
Roadie 0.13.0 installé (`roadie 0.13.0`), UUID identique au paquet, PID 72929, santé 5/5, certificat roadied-cert
conservé.

## Revue indépendante
Non réalisée pour les sessions 139 et 140.

## Limites
Distribution arm64, macOS 14 et ultérieur, signée ad hoc, non notarisée. Maj seule et zones par application non
essayées au clavier et à la souris réels (frappes et clics simulés refusés sur ce poste).
