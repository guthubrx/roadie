# Contrat des commandes - 155

Trois sorties de commande changent ou apparaissent. Toutes les autres commandes gardent
leur sortie et leur code de retour.

Rappel : la commande `roadie` ajoute un saut de ligne après chaque ligne de sortie.
Les messages suivent la langue de l'interface (`tr(fr, en)`). Les tests tournent en
français (`scripts/test` fixe `ROADIE_LANGUAGE=fr`).

## 1. `roadied --version` (modifiée)

| Cas | Sortie standard | Code |
|-----|-----------------|------|
| Binaire dans `Roadie.app` avec la clé `RoadieBuildCommit` | `roadied 0.13.0 (0b7de36b)` | 0 |
| Arbre de travail modifié au moment du build | `roadied 0.13.0 (0b7de36b-dirty)` | 0 |
| Binaire hors application, ou clé absente | `roadied 0.13.0` | 0 |

`roadied version` rend la même chose.

## 2. `roadie --version` (inchangée)

| Cas | Sortie standard | Code |
|-----|-----------------|------|
| Toujours | `roadie 0.13.0` | 0 |

Le test existant `CLICommandRouterTests.versionPrintsSingleVersionConstant` fixe cette
sortie. Il ne doit pas être modifié.

## 3. `roadie completion zsh` (nouvelle)

S'exécute dans le processus `roadie`. Le daemon n'a pas besoin de tourner.

| Appel | Sortie | Code |
|-------|--------|------|
| `roadie completion zsh` | Script zsh sur la sortie standard | 0 |
| `roadie completion` | Ligne d'usage sur la sortie d'erreur | 64 |
| `roadie completion bash` | Ligne d'usage sur la sortie d'erreur | 64 |
| `roadie completion zsh extra` | Ligne d'usage sur la sortie d'erreur | 64 |

Forme du script :

```zsh
#compdef roadie

_roadie() {
  local -a commands
  commands=(help completion update windows display ... daemon)
  if (( CURRENT == 2 )); then
    compadd -a commands
    return
  fi
  if (( CURRENT == 3 )); then
    case "$words[2]" in
      windows) compadd list ;;
      display) compadd list current focus ;;
      ...
    esac
  fi
}

if (( $+functions[compdef] )); then compdef _roadie roadie; fi
```

Garanties :

- `zsh -n` accepte le script (code 0).
- La ligne `commands=(…)` contient chaque commande implémentée de
  `CLICommandRouter.commandTable`, une fois, dans l'ordre de la table.
- Une entrée `implemented: false` n'apporte aucun mot. Exemple : `window close` est
  absente ; `window` reste proposée par ses autres sous-commandes.
- Seuls deux niveaux sont proposés : la commande et le premier mot qui suit. Les options
  (`--json`) et les valeurs (`ID`) ne sont pas proposées.

Mise en service documentée (une seule forme, vérifiée) : dans `~/.zshrc`, après
`compinit` :

```zsh
source <(roadie completion zsh)
```

## 4. `roadie update check` (nouvelle)

S'exécute dans le processus `roadie`. Le daemon ne fait aucun appel réseau. Un seul appel
par exécution : `GET https://api.github.com/repos/guthubrx/roadie/releases/latest`, avec
les en-têtes `Accept: application/vnd.github+json` et `User-Agent: roadie-update-check`.
Aucune donnée de l'utilisateur n'est envoyée.

| Cas | Sortie standard (français) | Sortie d'erreur (français) | Code |
|-----|----------------------------|----------------------------|------|
| Version publiée plus récente | `Nouvelle version disponible : v0.14.0 (installée : 0.13.0)` puis l'adresse de la release sur la ligne suivante | vide | 0 |
| Version installée à jour ou plus récente | `Roadie est à jour (0.13.0).` | vide | 0 |
| Réseau absent, délai dépassé, réponse HTTP autre que 200 | vide | `roadie: vérification impossible : <raison>` | 1 |
| Réponse illisible (JSON inattendu) | vide | `roadie: vérification impossible : réponse illisible` | 1 |
| `roadie update`, `roadie update autre`, `roadie update check extra` | vide | Ligne d'usage | 64 |

Textes anglais correspondants :

- `New version available: v0.14.0 (installed: 0.13.0)`
- `Roadie is up to date (0.13.0).`
- `roadie: update check failed: <reason>`
- `roadie: update check failed: unreadable response`

Délais : la requête a un délai de 5 secondes. La commande rend la main en 6 secondes au
plus, dans tous les cas.

La commande ne télécharge rien et n'installe rien.
