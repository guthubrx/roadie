# Contrat de l'identité du build - 155

But : savoir quel commit tourne, sans relever un UUID de binaire à la main.

## Chaîne de valeur

```text
git rev-parse --short=8 HEAD            (scripts/install, scripts/package-dmg)
        │   + "-dirty" si git status --porcelain liste un fichier
        ▼
scripts/build-app-bundle <binaire> <Roadie.app> <version> [commit]
        │   écrit la clé RoadieBuildCommit dans Contents/Info.plist
        ▼
RoadieVersion.buildCommit               (lecture directe d'Info.plist au lancement)
        ├──► roadied --version           « roadied 0.13.0 (0b7de36b) »
        └──► ~/.roadies/daemon-status.json   champ "buildCommit"
```

## `scripts/build-app-bundle`

| Appel | Résultat |
|-------|----------|
| 3 arguments | Comme avant. `Info.plist` sans clé `RoadieBuildCommit` |
| 4 arguments, le 4e non vide | `Info.plist` contient `<key>RoadieBuildCommit</key><string>…</string>` |
| 4 arguments, le 4e vide | Comme 3 arguments |
| Moins de 3 ou plus de 4 arguments | Message d'usage sur la sortie d'erreur, code 64 |

## `scripts/install` et `scripts/package-dmg`

- La version vient de `Sources/RoadieDaemon/DaemonHealth.swift`, par la même commande
  `sed` dans les deux scripts. `ROADIE_VERSION` reste une surcharge pour `package-dmg`.
- Le commit vient de `git rev-parse --short=8 HEAD`. Hors d'un dépôt Git, la valeur est
  vide et la clé n'est pas écrite. Aucun script n'échoue pour cette raison.

## `Info.plist`

| Clé | Type | Présence |
|-----|------|----------|
| `RoadieBuildCommit` | chaîne | Facultative |

Contrôle : `plutil -extract RoadieBuildCommit raw <Roadie.app>/Contents/Info.plist`.

## `~/.roadies/daemon-status.json`

Champ ajouté au contrat `specs/016-roadie-stabilization/contracts/daemon-status.md` :

| Champ | Type | Présence |
|-------|------|----------|
| `buildCommit` | chaîne | Facultatif. Absent quand le commit est inconnu |

Compatibilité : un lecteur ancien ignore le champ. Un fichier ancien sans le champ se lit
avec la valeur `nil`. Le champ `version` du fichier reste à `1`.

## Lecture par le code

`RoadieVersion.buildCommit` trouve `Info.plist` à partir du chemin de l'exécutable, après
résolution des liens symboliques : `<exécutable>/../../Info.plist`. La lecture ne passe
pas par `Bundle.main`, qui rend `nil` quand `roadied` est lancé par le lien
`~/.local/bin/roadied` (constaté, `research.md` R2).
