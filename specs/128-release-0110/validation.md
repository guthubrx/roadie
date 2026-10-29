# Validation de Roadie 0.11.0

## Périmètre
Version mineure depuis v0.10.0 : 115 commits, sessions 073 à 127 (voir `CHANGELOG.md`, section 0.11.0).
Publication demandée le 29 octobre 2026.

## Vérifications
Suite Swift : 2 278 tests dans 333 suites réussis (`scripts/test --no-parallel`).
Tests de scripts : 28 réussis (`python3 -I -B -m unittest discover scripts/tests`).
Aucun tiret cadratin dans les notes de version.

## Paquet vérifié
Construit par `scripts/package-dmg`. DMG de 14 404 169 octets, `hdiutil verify` valide, monté en lecture seule puis
démonté. Roadie.app et lien Applications présents. Bundle 0.11.0, minimum macOS 14.0. Daemon et CLI 0.11.0
(`roadie --version`), arm64. `codesign --verify --deep --strict` réussi.
UUID du daemon : 7468B5B2-53EC-39DA-AD8D-E8F524269A38.

```text
761af10860405afcf9b4399c4267d155f89418242f5f3b2bea036d4e7a8e02ea  Roadie.dmg
```

## Revue indépendante
Non réalisée : Bridget n'admet aucun agent depuis cette session (diagnostic en cours avec bridge1016).

## Limites
Distribution arm64, macOS 14 et ultérieur, signée ad hoc, non notarisée. Les vérifications de publication
(release, fichiers retéléchargés, installation) sont ajoutées après la publication.
