# Validation de Roadie 0.11.1

## Périmètre
Version corrective depuis v0.11.0 : audit V15 de la base de code du 29 octobre 2026, session 129 (actions des
workflows sans délai, commandes système attendues et échecs signalés, index des littéraux, parcours Firefox
linéaire, code mort) et référence Alfred à jour. Publication demandée le 29 octobre 2026.

## Vérifications
Suite Swift complète : 2 283 tests dans 334 suites réussis (`scripts/test --no-parallel`, aucune suite exclue).
Tests de scripts : 28 réussis (`python3 -I -B -m unittest discover -s scripts/tests`).
Aucun tiret cadratin dans les notes de version.

## Paquet vérifié
Construit par `scripts/package-dmg`. DMG de 14 409 339 octets, `hdiutil verify` valide, monté en lecture seule puis
démonté. Roadie.app et lien Applications présents. Bundle 0.11.1, minimum macOS 14.0, arm64. CLI
`roadie 0.11.1`. `codesign --verify --deep --strict` réussi. UUID du daemon : 5665A2A6-F566-308F-A119-F7070555AD36.

```text
03b0cbabae903fdabdf5c8bfea81692d09151c4f3231f4079ffe9cff1dc5e2c1  Roadie.dmg
```

## Revue indépendante
Non réalisée : `bridget_auto_delegate` absent du catalogue Bridget depuis le chargement de Bridget211 (incident
remis à bridge1016, sans réponse).

## Publication et vérification GitHub
https://github.com/guthubrx/roadie/releases/tag/v0.11.1 - Latest, hors brouillon et hors préversion, publiée le
29 octobre 2026 à 18:59:03Z. Tag annoté v0.11.1 sur 592ae0e4, poussé. `main` avancé sans commit de fusion et poussé
(3c9d66d9..592ae0e4). Notes EN puis FR relues par l'API : identiques au texte préparé, à une ligne vide finale
près. Liens des notes servis (HTTP 200 : notes 0.11.0, audit, validation, comparaison). Roadie.dmg et
Roadie.dmg.sha256 retéléchargés : identiques au paquet local, `shasum -a 256 -c` OK.

## Installation locale
Roadie 0.11.1 installé, UUID identique au paquet, PID 30417, santé 5/5, certificat roadied-cert conservé,
configuration identique avant et après (empreinte 166624a713447bc4).

## Nettoyage
Branches `130-release-0111` et précédentes supprimées après fusion ; `dist/` et compilation de release supprimés.
Worktree de conversation conservé, détaché sur `main`.

## Limites
Distribution arm64, macOS 14 et ultérieur, signée ad hoc, non notarisée.
