# Validation de Roadie 0.12.0

## Périmètre
Version mineure depuis v0.11.1 : sessions 131 à 137 (actions d'Alfred, fenêtres flottantes, recherche à l'écran,
fautes de frappe, sélecteur de zones Option+Tab, icônes des cartes). Publication demandée le 30 octobre 2026.

## Vérifications
Suite Swift complète : 2 350 tests dans 350 suites réussis (`scripts/test --no-parallel`, aucune suite exclue).
Tests de scripts : 28 réussis. Aucun tiret cadratin dans les notes de version ni les README. Capture
`zone-switcher.png` (EN, FR) dessinée par le vrai rendu du sélecteur avec des fenêtres et zones inventées.

## Paquet vérifié
Construit par `scripts/package-dmg`. DMG de 15 037 749 octets, `hdiutil verify` valide, monté en lecture seule puis
démonté. Roadie.app et lien Applications présents. Bundle 0.12.0, minimum macOS 14.0, arm64. CLI `roadie 0.12.0`.
`codesign --verify --deep --strict` réussi. UUID du daemon : 4877883B-2C00-3FD4-A4E9-4CC54D3D7C37.

```text
dc957dd4fb42e24edcc5b9b663fd061e8b3ed97f4013772ff338efc6f9cbd97d  Roadie.dmg
```

## Publication et vérification GitHub
https://github.com/guthubrx/roadie/releases/tag/v0.12.0 - Latest, hors brouillon et hors préversion, publiée le
30 octobre 2026 à 19:00:06Z. Tag annoté v0.12.0 sur d0f78e88, poussé ; `main` avancé sans commit de fusion
(63edfc46..d0f78e88). Roadie.dmg et Roadie.dmg.sha256 retéléchargés : identiques au paquet local,
`shasum -a 256 -c` OK. Captures, notes, audit et comparaison servis (HTTP 200). Ce reçu, écrit après l'étiquette,
n'est pas dans le tag : le lien de la note publiée pointe vers `main`.

## Installation locale
Roadie 0.12.0 installé, UUID identique au paquet, PID 57225, santé 5/5, certificat roadied-cert conservé.

## Revue indépendante
Non réalisée pour les sessions 132 à 137 (seule la 131 a un audit V15, A/pass).

## Limites
Distribution arm64, macOS 14 et ultérieur, signée ad hoc, non notarisée. Parcours réels du sélecteur de zones
confirmés par l'utilisateur en partie (aller-retour, photos, ⌘Tab) ; icônes des cartes et bordure non confirmées.
