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

## Publication et vérification GitHub
https://github.com/guthubrx/roadie/releases/tag/v0.11.0 - Latest, hors brouillon et hors préversion, publiée le
29 octobre 2026 à 16:05:27Z. Tag annoté v0.11.0 sur 0dcaa548, référence distante contrôlée. `main` avancé sans
commit de fusion et poussé. Notes EN puis FR relues par l'API : identiques au texte préparé, à une ligne vide
finale près. Image des notes servie (HTTP 200). Roadie.dmg et Roadie.dmg.sha256 retéléchargés : identiques au
paquet local, `shasum -a 256 -c` OK.

## Installation locale
Roadie 0.11.0 installé, UUID identique au paquet, PID 31805, santé 5/5, certificat roadied-cert conservé,
configuration identique avant et après (empreinte 166624a713447bc4).

## Nettoyage
Branche `128-release-0110` supprimée après fusion. `dist/`, compilations et fichiers temporaires supprimés.
Worktree de conversation conservé, détaché sur `main`, à la demande de l'utilisateur. Entrée de remise de côté
(stash) du 12 mai 2026 (`030-window-pins`) conservée : elle n'appartient pas à cette livraison.

## Limites
Distribution arm64, macOS 14 et ultérieur, signée ad hoc, non notarisée.
