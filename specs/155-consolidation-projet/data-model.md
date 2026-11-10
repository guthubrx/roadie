# Modèle de données - 155 Consolidation du projet

La feature n'ajoute aucune base de données. Elle ajoute ou modifie les données ci-dessous.

## 1. Version et identité du build

### `RoadieVersion` (`Sources/RoadieDaemon/DaemonHealth.swift`)

| Membre | Type | Valeur | Règle |
|--------|------|--------|-------|
| `current` | `String` | `"0.13.0"` (inchangé) | Seule déclaration littérale de la version dans `Sources/` et `scripts/` |
| `buildCommit` | `String?` | lu une fois au lancement | `nil` si le binaire n'est pas dans une application, si `Info.plist` est illisible, si la clé manque ou est vide |
| `display(commit:)` | `String` | `"0.13.0 (0b7de36b)"` ou `"0.13.0"` | Avec commit : `<version> (<commit>)`. Sans commit : `<version>` |

### Clé `RoadieBuildCommit` (`Roadie.app/Contents/Info.plist`)

| Champ | Type | Exemple | Règle |
|-------|------|---------|-------|
| `RoadieBuildCommit` | chaîne | `0b7de36b` ou `0b7de36b-dirty` | 8 caractères hexadécimaux du commit ; suffixe `-dirty` si `git status --porcelain` liste un fichier (modifié ou non suivi). Clé absente si le commit est inconnu |

### Champ `buildCommit` (`~/.roadies/daemon-status.json`)

| Champ | Type | Règle |
|-------|------|-------|
| `buildCommit` | chaîne, facultatif | Même valeur que la clé d'`Info.plist`. Absent du JSON quand la valeur est `nil` (comportement de `Codable` pour un facultatif). Un fichier ancien sans ce champ reste lisible |

`DaemonStatus.version` (version du format du fichier) ne change pas : l'ajout d'un champ
facultatif est compatible dans les deux sens.

## 2. Vérification de mise à jour (`Sources/RoadieDaemon/ReleaseCheck.swift`)

### `LatestRelease` (réponse de GitHub, lecture seule)

| Champ | Type | Source |
|-------|------|--------|
| `tag_name` | `String` | `https://api.github.com/repos/guthubrx/roadie/releases/latest` |
| `html_url` | `String` | même réponse |

Les autres champs de la réponse sont ignorés.

### `ReleaseCheck.Outcome`

| Champ | Type | Règle |
|-------|------|-------|
| `exitCode` | `Int32` | `0` si la dernière version est connue (à jour ou non) ; `1` sinon |
| `stdout` | `String?` | Message de résultat quand `exitCode == 0` |
| `stderr` | `String?` | Raison de l'échec quand `exitCode == 1` |

### Comparaison des versions (`ReleaseCheck.isNewer`)

- Le préfixe `v` ou `V` est ignoré.
- Les parties séparées par `.` sont comparées comme des nombres, de gauche à droite.
- Une partie absente vaut 0 (`0.14` égale `0.14.0`).
- Une partie non numérique vaut 0.

| Candidat | Actuelle | Résultat |
|----------|----------|----------|
| `v0.14.0` | `0.13.0` | plus récent |
| `v0.13.0` | `0.13.0` | pas plus récent |
| `0.9.0` | `0.13.0` | pas plus récent (comparaison numérique, pas alphabétique) |
| `v1.0` | `0.13.9` | plus récent |

## 3. Complétion (`Sources/RoadieDaemon/ShellCompletion.swift`)

Aucune donnée stockée. La fonction lit `CLICommandRouter.commandTable` :

| Entrée | Règle |
|--------|-------|
| `CLICommandSpec.usage` | Premier mot : nom de commande. Deuxième mot : sous-commandes. Le séparateur `|` donne plusieurs noms |
| `CLICommandSpec.implemented` | Une entrée `false` est ignorée |
| Mot retenu | Commence par une lettre minuscule ; contient seulement minuscules, chiffres et `-`. Les mots comme `[--json]`, `ID`, `--version` sont écartés |

## 4. Clés de configuration connues (`Sources/RoadieCore/Config.swift`)

`RoadieConfigLoader.knownKeys() -> [String: Set<String>]` expose la table déjà utilisée par
le validateur. Clé du dictionnaire : chemin de la table TOML (`""` pour la racine). Valeur :
noms de clés acceptés dans cette table. Aucune donnée nouvelle : lecture seule de l'existant.

## 5. Journal des sessions (`.specify/memory/sessions/journal.md`)

Fichier Markdown. En-tête de 4 lignes, puis les 366 lignes de journal sorties
d'`AGENTS.md`, dans leur ordre d'origine. Les nouveaux bilans s'ajoutent à la fin.

## 6. Événements retirés du journal (`~/.roadies/events.jsonl`)

| Type | État |
|------|------|
| `drag.real_press` | Plus écrit |
| `drag.real_router_press` | Plus écrit |

Les lignes déjà écrites restent dans le fichier ; elles sortent par la rotation normale à
10 Mo. Aucune migration.
