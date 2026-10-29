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

## Limites
Distribution arm64, macOS 14 et ultérieur, signée ad hoc, non notarisée.
