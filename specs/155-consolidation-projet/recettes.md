# Recettes - 155 consolidation du projet

Une fiche par tâche de `tasks.md`, dans le même ordre. Lis d'abord `quickstart.md`.

Chaque fiche donne : le but, les étapes avec la commande exacte et le résultat attendu, puis les
pièges. Pour une tâche préparée, la fiche montre aussi ce que l'outil change : c'est une aide à la
relecture. Ne retape jamais ces textes à la main.

Si un résultat diffère du résultat attendu : règle R0 de `quickstart.md` (arrêt, pas d'adaptation).

Tous les nombres de tests attendus (2523, 2527, 2529, 2533, 2538) ont été observés le
10 novembre 2026, par un essai de la suite complète à chaque point de commit (`research.md` R16).

## T001 [Setup] - Relever la base de référence

**But** : Mesurer l'état de départ avant toute modification. Ces mesures servent de comparaison à la fin.

**Étape 1** - Vérifie le dossier et la branche.

```bash
pwd
git rev-parse --abbrev-ref HEAD
git status --short
```

Résultat attendu : `pwd` finit par `.worktrees/155-consolidation-projet`. La branche est `155-consolidation-projet`. `git status --short` n'affiche rien. Sinon : règle R0.

**Étape 2** - Applique le changement préparé.

```bash
python3 -I -B specs/155-consolidation-projet/tools/appliquer.py T001 --check
python3 -I -B specs/155-consolidation-projet/tools/appliquer.py T001
```

Résultat attendu : La première commande finit par `OK T001 : contrôle réussi, rien n'a été écrit (1 fichier(s) à écrire).` La seconde finit par `OK T001 : 1 fichier(s) écrit(s).`

**Étape 3** - Lance les quatre mesures.

```bash
./scripts/test --no-parallel > /tmp/roadie155-base.log 2>&1; echo "exit=$?"
grep -E "Test run with|recorded an issue" /tmp/roadie155-base.log | tail -5
python3 -I -B -m unittest discover -s scripts/tests 2>&1 | tail -3
wc -c AGENTS.md
wc -l Sources/RoadieDaemon/LayoutMaintainer.swift
git rev-parse HEAD
date '+%Y-%m-%d %H:%M'
```

Résultat attendu : `exit=0` ; `Test run with 2523 tests in 383 suites passed` ; `Ran 28 tests` puis `OK` ; `39834 AGENTS.md` ; `4462 Sources/RoadieDaemon/LayoutMaintainer.swift`.

**Étape 4** - Ouvre `specs/155-consolidation-projet/validation/baseline.md`. Remplace chaque `À REMPLIR` par la valeur que tu viens d'observer. C'est une des deux seules saisies à la main du travail.

```bash
grep -c "À REMPLIR" specs/155-consolidation-projet/validation/baseline.md
```

Résultat attendu : `0`.

**Étape 5** - Coche T001 dans `tasks.md`, puis committe.

```bash
git add -- specs/155-consolidation-projet/validation/baseline.md specs/155-consolidation-projet/tasks.md
git commit -m "docs(155): Relever la base de référence"
git status --short
```

Résultat attendu : `git status --short` n'affiche rien.

**Ce que l'outil change** (pour relecture, ne pas retaper)

- Copie `specs/155-consolidation-projet/gabarits/baseline.md` (17 lignes) vers `specs/155-consolidation-projet/validation/baseline.md`.

**Pièges**

- Si la suite de départ échoue deux fois de suite, arrête tout : règle R0. Ne commence pas T002.
- Ne relance pas `appliquer.py T001` après avoir rempli le fichier : l'outil s'arrêterait (« existe déjà avec un autre contenu »). C'est normal.

## T002 [US1] - Retirer le chemin personnel de README.fr.md

**But** : Le README français contient deux fois le chemin `/Users/moi`. Il devient `~`.

**Étape 1** - Applique le changement préparé.

```bash
python3 -I -B specs/155-consolidation-projet/tools/appliquer.py T002 --check
python3 -I -B specs/155-consolidation-projet/tools/appliquer.py T002
```

Résultat attendu : La première commande finit par `OK T002 : contrôle réussi, rien n'a été écrit (1 fichier(s) à écrire).` La seconde finit par `OK T002 : 1 fichier(s) écrit(s).`

**Étape 2** - Contrôle.

```bash
grep -c "/Users/moi" README.md README.fr.md
```

Résultat attendu : `README.md:0` et `README.fr.md:0`.

**Ce que l'outil change** (pour relecture, ne pas retaper)

- `T002a` dans `README.fr.md`. Avant :

~~~~text
installe la commande dans `/Users/moi/.local/bin`,
~~~~

  Après :

~~~~text
installe la commande dans `~/.local/bin`,
~~~~

- `T002b` dans `README.fr.md`. Avant :

~~~~text
crée `/Users/moi/Library/LaunchAgents/com.roadie.roadied.plist`,
~~~~

  Après :

~~~~text
crée `~/Library/LaunchAgents/com.roadie.roadied.plist`,
~~~~

## T003 [US1] - Renuméroter l'ADR en double (013 devient 030)

**But** : Deux décisions portent le numéro 013. Celle du champ natif prend le numéro 030, le premier libre.

**Étape 1** - Renomme le fichier avec Git. La commande ne fait rien si le fichier est déjà renommé.

```bash
test -e docs/decisions/030-native-command-input.md || git mv docs/decisions/013-native-command-input.md docs/decisions/030-native-command-input.md
ls docs/decisions | grep -c '^013-'
```

Résultat attendu : `1`.

**Étape 2** - Applique le changement préparé.

```bash
python3 -I -B specs/155-consolidation-projet/tools/appliquer.py T003 --check
python3 -I -B specs/155-consolidation-projet/tools/appliquer.py T003
```

Résultat attendu : La première commande finit par `OK T003 : contrôle réussi, rien n'a été écrit (1 fichier(s) à écrire).` La seconde finit par `OK T003 : 1 fichier(s) écrit(s).`

**Étape 3** - Contrôle.

```bash
head -1 docs/decisions/030-native-command-input.md
```

Résultat attendu : `# 030 - Champ natif dans la boîte de commandes`.

**Ce que l'outil change** (pour relecture, ne pas retaper)

- `T003a` dans `docs/decisions/030-native-command-input.md`. Avant :

~~~~text
# 013 — Champ natif dans la boîte de commandes
~~~~

  Après :

~~~~text
# 030 - Champ natif dans la boîte de commandes
~~~~

**Pièges**

- Fais le `git mv` avant `appliquer.py T003 --check`. Sans le renommage, l'outil s'arrête (« fichier absent ») : c'est normal.
- Ne modifie pas les fichiers du dossier `audits/` qui citent l'ancien nom : ce sont des archives.

## T004 [US1] - Sortir la sauvegarde de constitution de Git

**But** : Un fichier de sauvegarde est suivi par Git. Il sort de l'index et reste sur le disque. `.gitignore` écarte les prochains.

**Étape 1** - Applique le changement préparé.

```bash
python3 -I -B specs/155-consolidation-projet/tools/appliquer.py T004 --check
python3 -I -B specs/155-consolidation-projet/tools/appliquer.py T004
```

Résultat attendu : La première commande finit par `OK T004 : contrôle réussi, rien n'a été écrit (1 fichier(s) à écrire).` La seconde finit par `OK T004 : 1 fichier(s) écrit(s).`

**Étape 2** - Retire le fichier de l'index, sans le supprimer du disque.

```bash
git ls-files --error-unmatch .specify/memory/constitution.md.bak-20260508-143829 >/dev/null 2>&1 && git rm --cached --quiet .specify/memory/constitution.md.bak-20260508-143829
git ls-files .specify/memory | grep -c "bak-"
git check-ignore .specify/memory/constitution.md.bak-20260508-143829
ls .specify/memory/constitution.md.bak-20260508-143829
```

Résultat attendu : `0`, puis deux fois le chemin `.specify/memory/constitution.md.bak-20260508-143829`.

**Ce que l'outil change** (pour relecture, ne pas retaper)

- `T004a` dans `.gitignore`. Avant :

~~~~text
/.specify/memory/user-layer.json
~~~~

  Après :

~~~~text
/.specify/memory/user-layer.json
/.specify/memory/*.bak-*
~~~~

**Pièges**

- N'utilise pas `git rm` sans `--cached` : le fichier doit rester sur le disque.

## T005 [US1] - Contrôler la user story 1 et committer

**But** : Vérifier les trois corrections et les enregistrer.

**Étape 1** - Contrôle.

```bash
grep -c "/Users/moi" README.md README.fr.md
ls docs/decisions | grep -c '^013-'
git ls-files .specify/memory | grep -c "bak-"
```

Résultat attendu : `README.md:0`, `README.fr.md:0`, `1`, `0`.

**Étape 2** - Coche cette tâche et les tâches précédentes de la user story dans `tasks.md`, puis committe. Le message est exactement celui-ci, sans aucune ligne en plus.

```bash
git add -- README.fr.md \
  .gitignore \
  docs/decisions/030-native-command-input.md \
  specs/155-consolidation-projet/tasks.md
git commit -m "docs(155): Nettoyer la documentation publique"
git status --short
```

Résultat attendu : `git commit` affiche une ligne qui contient le message. `git status --short` n'affiche rien.

**Pièges**

- Le renommage de T003 et le retrait de T004 sont déjà dans l'index : `git add` n'a pas besoin de l'ancien nom `013-native-command-input.md`.

## T006 [US2] - Ajouter les tests de l'identité du build (tests d'abord)

**But** : Poser les 4 tests qui décrivent le comportement attendu, avant le code.

**Étape 1** - Applique le changement préparé.

```bash
python3 -I -B specs/155-consolidation-projet/tools/appliquer.py T006 --check
python3 -I -B specs/155-consolidation-projet/tools/appliquer.py T006
```

Résultat attendu : La première commande finit par `OK T006 : contrôle réussi, rien n'a été écrit (1 fichier(s) à écrire).` La seconde finit par `OK T006 : 1 fichier(s) écrit(s).`

**Ce que l'outil change** (pour relecture, ne pas retaper)

- Copie `specs/155-consolidation-projet/gabarits/Spec155BuildIdentityTests.swift` (51 lignes) vers `Tests/RoadieDaemonTests/Spec155BuildIdentityTests.swift`.

**Pièges**

- Ne lance pas les tests maintenant. La compilation échoue jusqu'à la fin de T007 : c'est attendu.

## T007 [US2] - Lire le commit du build dans DaemonHealth.swift

**But** : `RoadieVersion` lit le commit du build dans `Info.plist` de l'application et l'ajoute à `daemon-status.json` (champ facultatif `buildCommit`).

**Étape 1** - Applique le changement préparé.

```bash
python3 -I -B specs/155-consolidation-projet/tools/appliquer.py T007 --check
python3 -I -B specs/155-consolidation-projet/tools/appliquer.py T007
```

Résultat attendu : La première commande finit par `OK T007 : contrôle réussi, rien n'a été écrit (1 fichier(s) à écrire).` La seconde finit par `OK T007 : 1 fichier(s) écrit(s).`

**Ce que l'outil change** (pour relecture, ne pas retaper)

- `T007a` dans `Sources/RoadieDaemon/DaemonHealth.swift`. Avant :

~~~~text
public enum RoadieVersion {
    public static let current = "0.13.0"
}
~~~~

  Après :

~~~~text
public enum RoadieVersion {
    public static let current = "0.13.0"

    /// Commit du build, lu une fois dans `Roadie.app/Contents/Info.plist` (clé `RoadieBuildCommit`).
    /// `nil` hors de l'application. Le chemin part de l'exécutable réel : `Bundle.main` rend `nil`
    /// quand `roadied` est lancé par le lien `~/.local/bin/roadied`.
    public static let buildCommit: String? = {
        guard let executable = Bundle.main.executableURL?.resolvingSymlinksInPath() else { return nil }
        let infoPlist = executable.deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Info.plist")
        return buildCommit(infoPlist: infoPlist)
    }()

    static func buildCommit(infoPlist url: URL) -> String? {
        guard let data = try? Data(contentsOf: url),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let commit = plist["RoadieBuildCommit"] as? String,
              !commit.isEmpty
        else { return nil }
        return commit
    }

    /// Version affichée : `0.13.0 (0b7de36b)` avec un commit connu, `0.13.0` sinon.
    public static func display(commit: String? = buildCommit) -> String {
        commit.map { "\(current) (\($0))" } ?? current
    }
}
~~~~

- `T007b` dans `Sources/RoadieDaemon/DaemonHealth.swift`. Avant :

~~~~text
    public var socketPath: String

    public init(
        pid: Int32,
~~~~

  Après :

~~~~text
    public var socketPath: String
    /// Commit du build. Absent du fichier quand il est inconnu.
    public var buildCommit: String?

    public init(
        pid: Int32,
~~~~

- `T007c` dans `Sources/RoadieDaemon/DaemonHealth.swift`. Avant :

~~~~text
        roadieVersion: String = RoadieVersion.current
    ) {
~~~~

  Après :

~~~~text
        roadieVersion: String = RoadieVersion.current,
        buildCommit: String? = RoadieVersion.buildCommit
    ) {
~~~~

- `T007d` dans `Sources/RoadieDaemon/DaemonHealth.swift`. Avant :

~~~~text
        self.socketPath = socketPath
    }

    /// Vrai si le process vit et que le battement a moins de 90 s.
~~~~

  Après :

~~~~text
        self.socketPath = socketPath
        self.buildCommit = buildCommit
    }

    /// Vrai si le process vit et que le battement a moins de 90 s.
~~~~

## T008 [US2] - Afficher le commit dans `roadied --version`

**But** : `roadied --version` affiche `roadied 0.13.0 (commit)` quand le commit est connu.

**Étape 1** - Applique le changement préparé.

```bash
python3 -I -B specs/155-consolidation-projet/tools/appliquer.py T008 --check
python3 -I -B specs/155-consolidation-projet/tools/appliquer.py T008
```

Résultat attendu : La première commande finit par `OK T008 : contrôle réussi, rien n'a été écrit (1 fichier(s) à écrire).` La seconde finit par `OK T008 : 1 fichier(s) écrit(s).`

**Étape 2** - Lance les tests de cette user story.

```bash
./scripts/test --no-parallel --filter Spec155BuildIdentityTests 2>&1 | grep -E "Test run with|recorded an issue|error:" | tail -5
```

Résultat attendu : Une ligne `Test run with 4 tests in 1 suite passed`.

**Ce que l'outil change** (pour relecture, ne pas retaper)

- `T008` dans `Sources/roadied/main.swift`. Avant :

~~~~text
    print("roadied \(RoadieVersion.current)")
~~~~

  Après :

~~~~text
    print("roadied \(RoadieVersion.display())")
~~~~

## T009 [US2] - Accepter le commit dans scripts/build-app-bundle

**But** : Le script reçoit un quatrième argument facultatif et l'écrit dans `Info.plist`.

**Étape 1** - Applique le changement préparé.

```bash
python3 -I -B specs/155-consolidation-projet/tools/appliquer.py T009 --check
python3 -I -B specs/155-consolidation-projet/tools/appliquer.py T009
```

Résultat attendu : La première commande finit par `OK T009 : contrôle réussi, rien n'a été écrit (1 fichier(s) à écrire).` La seconde finit par `OK T009 : 1 fichier(s) écrit(s).`

**Étape 2** - Contrôle de syntaxe.

```bash
bash -n scripts/build-app-bundle; echo "syntaxe=$?"
```

Résultat attendu : `syntaxe=0`.

**Ce que l'outil change** (pour relecture, ne pas retaper)

- `T009a` dans `scripts/build-app-bundle`. Avant :

~~~~text
# Usage : scripts/build-app-bundle <binaire-roadied> <chemin/Roadie.app> <version>
~~~~

  Après :

~~~~text
# Usage : scripts/build-app-bundle <binaire-roadied> <chemin/Roadie.app> <version> [commit]
# Le commit, facultatif, est écrit dans Info.plist (clé RoadieBuildCommit).
~~~~

- `T009b` dans `scripts/build-app-bundle`. Avant :

~~~~text
if [[ $# -ne 3 ]]; then
  echo "Usage : $0 <binaire-roadied> <chemin/Roadie.app> <version>" >&2
  exit 64
fi
roadied_binary="$1"
app_bundle="$2"
app_version="$3"
~~~~

  Après :

~~~~text
if [[ $# -lt 3 || $# -gt 4 ]]; then
  echo "Usage : $0 <binaire-roadied> <chemin/Roadie.app> <version> [commit]" >&2
  exit 64
fi
roadied_binary="$1"
app_bundle="$2"
app_version="$3"
build_commit="${4:-}"
~~~~

- `T009c` dans `scripts/build-app-bundle`. Avant :

~~~~text
</dict>
</plist>
PLIST
~~~~

  Après :

~~~~text
</dict>
</plist>
PLIST

if [[ -n "$build_commit" ]]; then
  plutil -insert RoadieBuildCommit -string "$build_commit" "$app_bundle/Contents/Info.plist"
fi
~~~~

## T010 [US2] - Transmettre le commit depuis scripts/install et scripts/package-dmg

**But** : Les deux scripts calculent le commit court (suffixe `-dirty` si un fichier est modifié ou non suivi). `package-dmg` lit la version dans le code au lieu de la répéter.

**Étape 1** - Applique le changement préparé.

```bash
python3 -I -B specs/155-consolidation-projet/tools/appliquer.py T010 --check
python3 -I -B specs/155-consolidation-projet/tools/appliquer.py T010
```

Résultat attendu : La première commande finit par `OK T010 : contrôle réussi, rien n'a été écrit (2 fichier(s) à écrire).` La seconde finit par `OK T010 : 2 fichier(s) écrit(s).`

**Étape 2** - Contrôle.

```bash
bash -n scripts/install; echo "install=$?"
bash -n scripts/package-dmg; echo "dmg=$?"
grep -rl '0\.13\.0' Sources scripts
```

Résultat attendu : `install=0`, `dmg=0`, puis une seule ligne : `Sources/RoadieDaemon/DaemonHealth.swift`.

**Ce que l'outil change** (pour relecture, ne pas retaper)

- `T010a` dans `scripts/install`. Avant :

~~~~text
  version="$(sed -n 's/.*static let current = "\(.*\)".*/\1/p' "$script_dir/../Sources/RoadieDaemon/DaemonHealth.swift")"
  "$script_dir/build-app-bundle" "$build_roadied" "$tmp_bundle" "${version:-0.0.0}"
~~~~

  Après :

~~~~text
  version="$(sed -n 's/.*static let current = "\(.*\)".*/\1/p' "$script_dir/../Sources/RoadieDaemon/DaemonHealth.swift")"
  # Commit du build, vide hors d'un dépôt Git ; « -dirty » si un fichier est modifié ou non suivi.
  local build_commit
  build_commit="$(git -C "$script_dir/.." rev-parse --short=8 HEAD 2>/dev/null || true)"
  if [[ -n "$build_commit" ]] && [[ -n "$(git -C "$script_dir/.." status --porcelain 2>/dev/null)" ]]; then
    build_commit="$build_commit-dirty"
  fi
  "$script_dir/build-app-bundle" "$build_roadied" "$tmp_bundle" "${version:-0.0.0}" "$build_commit"
~~~~

- `T010b` dans `scripts/package-dmg`. Avant :

~~~~text
app_version="${ROADIE_VERSION:-0.13.0}"
~~~~

  Après :

~~~~text
source_version="$(sed -n 's/.*static let current = "\(.*\)".*/\1/p' "$repo_root/Sources/RoadieDaemon/DaemonHealth.swift")"
app_version="${ROADIE_VERSION:-${source_version:-0.0.0}}"
# Commit du build, vide hors d'un dépôt Git ; « -dirty » si un fichier est modifié ou non suivi.
build_commit="$(git -C "$repo_root" rev-parse --short=8 HEAD 2>/dev/null || true)"
if [[ -n "$build_commit" ]] && [[ -n "$(git -C "$repo_root" status --porcelain 2>/dev/null)" ]]; then
  build_commit="$build_commit-dirty"
fi
~~~~

- `T010c` dans `scripts/package-dmg`. Avant :

~~~~text
"$script_dir/build-app-bundle" "$bin_dir/roadied" "$app_bundle" "$app_version"
~~~~

  Après :

~~~~text
"$script_dir/build-app-bundle" "$bin_dir/roadied" "$app_bundle" "$app_version" "$build_commit"
~~~~

**Pièges**

- Ne lance ni `scripts/install` ni `scripts/package-dmg` : action interdite (`quickstart.md`, point 8).

## T011 [US2] - Documenter le commit du build

**But** : Contrat du fichier d'état, guides CLI français et anglais, changelog.

**Étape 1** - Applique le changement préparé.

```bash
python3 -I -B specs/155-consolidation-projet/tools/appliquer.py T011 --check
python3 -I -B specs/155-consolidation-projet/tools/appliquer.py T011
```

Résultat attendu : La première commande finit par `OK T011 : contrôle réussi, rien n'a été écrit (4 fichier(s) à écrire).` La seconde finit par `OK T011 : 4 fichier(s) écrit(s).`

**Ce que l'outil change** (pour relecture, ne pas retaper)

- `T011a` dans `specs/016-roadie-stabilization/contracts/daemon-status.md`. Avant :

~~~~text
  "socketPath": "~/.roadies/roadied.sock"
}
```
~~~~

  Après :

~~~~text
  "socketPath": "~/.roadies/roadied.sock",
  "buildCommit": "0b7de36b"
}
```

`buildCommit` (ajout de la spec 155) est facultatif : le champ est absent quand le commit du build est inconnu. Un lecteur ancien l'ignore. Le champ `version` reste à 1.
~~~~

- `T011b` dans `docs/fr/cli.md`. Avant :

~~~~text
- `--version` : affiche la version. `roadied --version` fait de même pour le binaire du daemon.
~~~~

  Après :

~~~~text
- `--version` : affiche la version. `roadied --version` affiche aussi le commit du build quand il est connu, par exemple `roadied 0.13.0 (0b7de36b)`. Le même commit figure dans le champ `buildCommit` de `~/.roadies/daemon-status.json`.
~~~~

- `T011c` dans `docs/en/cli.md`. Avant :

~~~~text
- `--version`: prints the version. `roadied --version` does the same for the daemon binary.
~~~~

  Après :

~~~~text
- `--version`: prints the version. `roadied --version` also prints the build commit when it is known, for example `roadied 0.13.0 (0b7de36b)`. The same commit is in the `buildCommit` field of `~/.roadies/daemon-status.json`.
~~~~

- `T011d` dans `CHANGELOG.md`. Avant :

~~~~text
## Non publié
~~~~

  Après :

~~~~text
## Non publié

- Version : `roadied --version` et `~/.roadies/daemon-status.json` indiquent le commit du build
  installé, par exemple `roadied 0.13.0 (0b7de36b)`. Le DMG lit sa version dans le code.
~~~~

## T012 [US2] - Contrôler la user story 2 et committer

**But** : Prouver sur une application temporaire que le commit est écrit puis relu. Rien n'est installé.

**Étape 1** - Lance ce bloc en une seule commande (la variable `tmp` doit rester connue).

```bash
./scripts/with-xcode swift build 2>&1 | tail -3
tmp=$(mktemp -d /tmp/roadie155-bundle.XXXXXX)
./scripts/build-app-bundle .build/debug/roadied "$tmp/Roadie.app" 0.13.0 abc12345; echo "bundle=$?"
plutil -extract RoadieBuildCommit raw "$tmp/Roadie.app/Contents/Info.plist"
"$tmp/Roadie.app/Contents/MacOS/roadied" --version
.build/debug/roadied --version
rm -rf "$tmp"
```

Résultat attendu : `bundle=0` ; `abc12345` ; `roadied 0.13.0 (abc12345)` ; `roadied 0.13.0`.

**Étape 2** - Lance les tests des scripts.

```bash
python3 -I -B -m unittest discover -s scripts/tests 2>&1 | tail -3
```

Résultat attendu : `Ran 28 tests` puis `OK`.

**Étape 3** - Lance la suite complète.

```bash
./scripts/test --no-parallel > /tmp/roadie155-test.log 2>&1; echo "exit=$?"
grep -E "Test run with|recorded an issue" /tmp/roadie155-test.log | tail -5
```

Résultat attendu : `exit=0` et une ligne `Test run with 2527 tests in 384 suites passed`. Le critère est `exit=0` et le mot `passed`. Si seul le nombre diffère, note-le dans ton compte rendu et continue. Un échec isolé hors de la spec 155 : piège P3 de `quickstart.md`.

**Étape 4** - Coche cette tâche et les tâches précédentes de la user story dans `tasks.md`, puis committe. Le message est exactement celui-ci, sans aucune ligne en plus.

```bash
git add -- Sources/RoadieDaemon/DaemonHealth.swift \
  Sources/roadied/main.swift \
  Tests/RoadieDaemonTests/Spec155BuildIdentityTests.swift \
  scripts/build-app-bundle \
  scripts/install \
  scripts/package-dmg \
  specs/016-roadie-stabilization/contracts/daemon-status.md \
  docs/fr/cli.md \
  docs/en/cli.md \
  CHANGELOG.md \
  specs/155-consolidation-projet/tasks.md
git commit -m "feat(155): Inscrire le commit du build dans la version"
git status --short
```

Résultat attendu : `git commit` affiche une ligne qui contient le message. `git status --short` n'affiche rien.

**Pièges**

- Le bloc crée une application dans `/tmp` et la supprime. Il ne touche pas à l'application installée.
- `.build/debug/roadied --version` n'affiche pas de commit : ce binaire n'est pas dans une application. C'est le résultat attendu.

## T013 [US3] - Exposer la liste des clés connues

**But** : Ajouter `RoadieConfig.knownKeys()`, sur le modèle de `ineffectiveKeys()` juste au-dessus.

**Étape 1** - Applique le changement préparé.

```bash
python3 -I -B specs/155-consolidation-projet/tools/appliquer.py T013 --check
python3 -I -B specs/155-consolidation-projet/tools/appliquer.py T013
```

Résultat attendu : La première commande finit par `OK T013 : contrôle réussi, rien n'a été écrit (1 fichier(s) à écrire).` La seconde finit par `OK T013 : 1 fichier(s) écrit(s).`

**Ce que l'outil change** (pour relecture, ne pas retaper)

- `T013` dans `Sources/RoadieCore/Config.swift`. Avant :

~~~~text
    public static func ineffectiveKeys() -> [String: Set<String>] {
        ConfigValidationRules.ineffectiveKeys
    }
~~~~

  Après :

~~~~text
    public static func ineffectiveKeys() -> [String: Set<String>] {
        ConfigValidationRules.ineffectiveKeys
    }

    /// Clés acceptées par le validateur, par chemin de table (« » pour la racine).
    public static func knownKeys() -> [String: Set<String>] {
        ConfigValidationRules.knownKeys
    }
~~~~

## T014 [US3] - Ajouter les deux tests de garde

**But** : Deux tests échouent si un réglage de la configuration par défaut n'est pas déclaré au validateur.

**Étape 1** - Applique le changement préparé.

```bash
python3 -I -B specs/155-consolidation-projet/tools/appliquer.py T014 --check
python3 -I -B specs/155-consolidation-projet/tools/appliquer.py T014
```

Résultat attendu : La première commande finit par `OK T014 : contrôle réussi, rien n'a été écrit (1 fichier(s) à écrire).` La seconde finit par `OK T014 : 1 fichier(s) écrit(s).`

**Étape 2** - Lance les tests de cette user story.

```bash
./scripts/test --no-parallel --filter Spec155ConfigGuardTests 2>&1 | grep -E "Test run with|recorded an issue|error:" | tail -5
```

Résultat attendu : Une ligne `Test run with 2 tests in 1 suite passed`.

**Ce que l'outil change** (pour relecture, ne pas retaper)

- Copie `specs/155-consolidation-projet/gabarits/Spec155ConfigGuardTests.swift` (43 lignes) vers `Tests/RoadieDaemonTests/Spec155ConfigGuardTests.swift`.

**Pièges**

- Signal 11 (« outlined destroy ») au lancement des tests : piège P1 de `quickstart.md`.

## T015 [US3] - Écrire la recette « ajouter un réglage », contrôler et committer

**But** : Une page courte dit où déclarer un nouveau réglage. Puis contrôle et commit de la user story 3.

**Étape 1** - Applique le changement préparé.

```bash
python3 -I -B specs/155-consolidation-projet/tools/appliquer.py T015 --check
python3 -I -B specs/155-consolidation-projet/tools/appliquer.py T015
```

Résultat attendu : La première commande finit par `OK T015 : contrôle réussi, rien n'a été écrit (1 fichier(s) à écrire).` La seconde finit par `OK T015 : 1 fichier(s) écrit(s).`

**Étape 2** - Lance la suite complète.

```bash
./scripts/test --no-parallel > /tmp/roadie155-test.log 2>&1; echo "exit=$?"
grep -E "Test run with|recorded an issue" /tmp/roadie155-test.log | tail -5
```

Résultat attendu : `exit=0` et une ligne `Test run with 2529 tests in 385 suites passed`. Le critère est `exit=0` et le mot `passed`. Si seul le nombre diffère, note-le dans ton compte rendu et continue. Un échec isolé hors de la spec 155 : piège P3 de `quickstart.md`.

**Étape 3** - Coche cette tâche et les tâches précédentes de la user story dans `tasks.md`, puis committe. Le message est exactement celui-ci, sans aucune ligne en plus.

```bash
git add -- Sources/RoadieCore/Config.swift \
  Tests/RoadieDaemonTests/Spec155ConfigGuardTests.swift \
  docs/dev/ajouter-un-reglage.md \
  specs/155-consolidation-projet/tasks.md
git commit -m "test(155): Garder les réglages sous contrôle"
git status --short
```

Résultat attendu : `git commit` affiche une ligne qui contient le message. `git status --short` n'affiche rien.

**Ce que l'outil change** (pour relecture, ne pas retaper)

- Copie `specs/155-consolidation-projet/gabarits/ajouter-un-reglage.md` (69 lignes) vers `docs/dev/ajouter-un-reglage.md`.

## T016 [US4] - Déplacer le journal des sessions hors d'AGENTS.md

**But** : Les 366 lignes de journal partent vers `.specify/memory/sessions/journal.md`, sans changement.

**Étape 1** - Lance l'outil une seule fois, puis son contrôle.

```bash
test -e .specify/memory/sessions/journal.md || python3 -I -B specs/155-consolidation-projet/tools/deplacer_journal.py
python3 -I -B specs/155-consolidation-projet/tools/deplacer_journal.py --check
```

Résultat attendu : Première commande : `lignes_deplacees=366`, une ligne `journal=…` qui finit par `.specify/memory/sessions/journal.md`, puis `octets_agents=1916`. Seconde commande : `OK : 366 lignes de journal conservées, 0 restante dans AGENTS.md`.

**Pièges**

- Ne déplace aucune ligne à la main. Si l'outil affiche `ERREUR :`, règle R0.

## T017 [US4] - Ajouter les sections utiles dans AGENTS.md

**But** : Trois sections courtes : où est le journal, comment lancer les tests, les pièges connus.

**Étape 1** - Applique le changement préparé.

```bash
python3 -I -B specs/155-consolidation-projet/tools/appliquer.py T017 --check
python3 -I -B specs/155-consolidation-projet/tools/appliquer.py T017
```

Résultat attendu : La première commande finit par `OK T017 : contrôle réussi, rien n'a été écrit (1 fichier(s) à écrire).` La seconde finit par `OK T017 : 1 fichier(s) écrit(s).`

**Ce que l'outil change** (pour relecture, ne pas retaper)

- `T017a` dans `AGENTS.md`. Avant :

~~~~text
<!-- SPECKIT START -->
~~~~

  Après :

~~~~text
## Journal des sessions

Le bilan de chaque session livrée est dans `.specify/memory/sessions/journal.md`.
Ajoute le bilan d'une nouvelle session à la fin de ce fichier, pas ici.

## Tests

- Suite complète : `./scripts/test --no-parallel` (environ 80 secondes). Sans `--no-parallel`,
  des tests sensibles au temps échouent quand la machine est chargée.
- Un groupe de tests : `./scripts/test --no-parallel --filter NomDeLaSuite`.
- Tests des scripts : `python3 -I -B -m unittest discover -s scripts/tests`.
- Un test hors de ton périmètre échoue une fois : relance-le seul. S'il échoue deux fois de
  suite, arrête et signale-le avec la commande et le message.
- Ajouter un réglage : suivre `docs/dev/ajouter-un-reglage.md`.

## Pièges connus

- **Signature** : `make install` signe avec le certificat `roadied-cert`. Une autre signature
  fait perdre la permission Accessibilité.
- **Build de test périmé** : après l'ajout d'un champ à une structure de `RoadieCore`, les
  tests peuvent planter au signal 11 (« outlined destroy »). Remède : supprimer
  `.build/arm64-apple-macosx/debug/RoadieTilerTests.build`, puis relancer les tests.
- **Symbole introuvable à l'édition de liens** (« Undefined symbols … TargetModeConfig.init ») :
  `touch Sources/RoadieDaemon/OverviewController.swift`, puis relancer.
- **Processus enfants** : `roadied` ignore SIGTERM et un enfant en hérite. Rétablir les
  signaux par défaut au lancement de l'enfant.
- **Audit V15** : le lancer sur un checkout hors de `.worktrees`.
- **Avertissement sans gravité** : `scripts/test` utilise un dossier personnel temporaire ;
  SwiftPM affiche « failed loading cached manifest … Not a directory ». Ce n'est pas une erreur.
- **Commits** : nommer les fichiers (`git add -- <fichiers>`), jamais `git commit -a`.

<!-- SPECKIT START -->
~~~~

**Pièges**

- T017 exige T016 terminée.

## T018 [US4] - Contrôler la user story 4 et committer

**But** : Vérifier la taille d'AGENTS.md et la conservation du journal.

**Étape 1** - Contrôle.

```bash
wc -c AGENTS.md
grep -c "SPECKIT" AGENTS.md
python3 -I -B specs/155-consolidation-projet/tools/deplacer_journal.py --check
```

Résultat attendu : Un nombre inférieur à 8000 (attendu : environ 3736) ; `4` ; `OK : 366 lignes de journal conservées, 0 restante dans AGENTS.md`.

**Étape 2** - Coche cette tâche et les tâches précédentes de la user story dans `tasks.md`, puis committe. Le message est exactement celui-ci, sans aucune ligne en plus.

```bash
git add -- AGENTS.md \
  .specify/memory/sessions/journal.md \
  specs/155-consolidation-projet/tasks.md
git commit -m "docs(155): Alléger les consignes des agents"
git status --short
```

Résultat attendu : `git commit` affiche une ligne qui contient le message. `git status --short` n'affiche rien.

## T019 [US5] - Contrôler le type avant la conversion d'un élément AX

**But** : Une réponse d'accessibilité d'un type inattendu rend `nil` au lieu de faire planter Roadie.

**Étape 1** - Applique le changement préparé.

```bash
python3 -I -B specs/155-consolidation-projet/tools/appliquer.py T019 --check
python3 -I -B specs/155-consolidation-projet/tools/appliquer.py T019
```

Résultat attendu : La première commande finit par `OK T019 : contrôle réussi, rien n'a été écrit (1 fichier(s) à écrire).` La seconde finit par `OK T019 : 1 fichier(s) écrit(s).`

**Ce que l'outil change** (pour relecture, ne pas retaper)

- `T019` dans `Sources/RoadieDaemon/AppTargetQueryService.swift`. Avant :

~~~~text
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let value
        else { return nil }
        return (value as! AXUIElement)
~~~~

  Après :

~~~~text
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let value,
              CFGetTypeID(value) == AXUIElementGetTypeID()
        else { return nil }
        return (value as! AXUIElement)
~~~~

## T020 [US5] - Contrôler le type des valeurs de position et de taille

**But** : Même garde pour les deux valeurs `AXValue`.

**Étape 1** - Applique le changement préparé.

```bash
python3 -I -B specs/155-consolidation-projet/tools/appliquer.py T020 --check
python3 -I -B specs/155-consolidation-projet/tools/appliquer.py T020
```

Résultat attendu : La première commande finit par `OK T020 : contrôle réussi, rien n'a été écrit (1 fichier(s) à écrire).` La seconde finit par `OK T020 : 1 fichier(s) écrit(s).`

**Ce que l'outil change** (pour relecture, ne pas retaper)

- `T020` dans `Sources/RoadieDaemon/AppTargetQueryService.swift`. Avant :

~~~~text
              let positionValue = positionRef,
              let sizeValue = sizeRef
        else { return nil }
~~~~

  Après :

~~~~text
              let positionValue = positionRef,
              let sizeValue = sizeRef,
              CFGetTypeID(positionValue) == AXValueGetTypeID(),
              CFGetTypeID(sizeValue) == AXValueGetTypeID()
        else { return nil }
~~~~

## T021 [US5] - Contrôler la user story 5, noter le changement et committer

**But** : Changelog, contrôle et commit de la user story 5.

**Étape 1** - Applique le changement préparé.

```bash
python3 -I -B specs/155-consolidation-projet/tools/appliquer.py T021 --check
python3 -I -B specs/155-consolidation-projet/tools/appliquer.py T021
```

Résultat attendu : La première commande finit par `OK T021 : contrôle réussi, rien n'a été écrit (1 fichier(s) à écrire).` La seconde finit par `OK T021 : 1 fichier(s) écrit(s).`

**Étape 2** - Contrôle.

```bash
grep -c "CFGetTypeID" Sources/RoadieDaemon/AppTargetQueryService.swift
```

Résultat attendu : `5`.

**Étape 3** - Lance la suite complète.

```bash
./scripts/test --no-parallel > /tmp/roadie155-test.log 2>&1; echo "exit=$?"
grep -E "Test run with|recorded an issue" /tmp/roadie155-test.log | tail -5
```

Résultat attendu : `exit=0` et une ligne `Test run with 2529 tests in 385 suites passed`. Le critère est `exit=0` et le mot `passed`. Si seul le nombre diffère, note-le dans ton compte rendu et continue. Un échec isolé hors de la spec 155 : piège P3 de `quickstart.md`.

**Étape 4** - Coche cette tâche et les tâches précédentes de la user story dans `tasks.md`, puis committe. Le message est exactement celui-ci, sans aucune ligne en plus.

```bash
git add -- Sources/RoadieDaemon/AppTargetQueryService.swift \
  CHANGELOG.md \
  specs/155-consolidation-projet/tasks.md
git commit -m "fix(155): Contrôler le type des réponses d'accessibilité"
git status --short
```

Résultat attendu : `git commit` affiche une ligne qui contient le message. `git status --short` n'affiche rien.

**Ce que l'outil change** (pour relecture, ne pas retaper)

- `T021a` dans `CHANGELOG.md`. Avant :

~~~~text
## Non publié
~~~~

  Après :

~~~~text
## Non publié

- Cibles à l'écran : une réponse d'accessibilité d'un type inattendu est maintenant ignorée.
~~~~

## T022 [US6] - Retirer l'événement `drag.real_press`

**But** : Roadie n'écrit plus la position de chaque clic gauche dans son journal d'événements.

**Étape 1** - Applique le changement préparé.

```bash
python3 -I -B specs/155-consolidation-projet/tools/appliquer.py T022 --check
python3 -I -B specs/155-consolidation-projet/tools/appliquer.py T022
```

Résultat attendu : La première commande finit par `OK T022 : contrôle réussi, rien n'a été écrit (1 fichier(s) à écrire).` La seconde finit par `OK T022 : 1 fichier(s) écrit(s).`

**Ce que l'outil change** (pour relecture, ne pas retaper)

- `T022` dans `Sources/RoadieDaemon/DropPreviewController.swift`. Avant :

~~~~text
        if type == .leftMouseDown {
            let pressDetails = ["hadPending": String(pending != nil), "x": String(Double(event.location.x)),
                "y": String(Double(event.location.y)), "observedAt": String(ProcessInfo.processInfo.systemUptime)]
            let events = events
            Task { @MainActor in events.append(RoadieEvent(type: "drag.real_press", details: pressDetails)) }
            pointerSequence &+= 1
~~~~

  Après :

~~~~text
        if type == .leftMouseDown {
            pointerSequence &+= 1
~~~~

## T023 [US6] - Retirer l'événement `drag.real_router_press`

**But** : Même retrait dans le contrôleur du rail.

**Étape 1** - Applique le changement préparé.

```bash
python3 -I -B specs/155-consolidation-projet/tools/appliquer.py T023 --check
python3 -I -B specs/155-consolidation-projet/tools/appliquer.py T023
```

Résultat attendu : La première commande finit par `OK T023 : contrôle réussi, rien n'a été écrit (1 fichier(s) à écrire).` La seconde finit par `OK T023 : 1 fichier(s) écrit(s).`

**Ce que l'outil change** (pour relecture, ne pas retaper)

- `T023` dans `Sources/RoadieDaemon/RailController.swift`. Avant :

~~~~text
    private func handleMouseDown(at screenPoint: CGPoint, fromGlobalMonitor: Bool = false) {
        events.append(RoadieEvent(type: "drag.real_router_press", details: ["x": String(Double(screenPoint.x)),
            "y": String(Double(screenPoint.y)), "global": String(fromGlobalMonitor)]))
        FrameTransitionRuntime.shared.cancel()
~~~~

  Après :

~~~~text
    private func handleMouseDown(at screenPoint: CGPoint, fromGlobalMonitor: Bool = false) {
        FrameTransitionRuntime.shared.cancel()
~~~~

## T024 [US6] - Contrôler la user story 6, noter le changement et committer

**But** : Changelog, contrôle et commit de la user story 6.

**Étape 1** - Applique le changement préparé.

```bash
python3 -I -B specs/155-consolidation-projet/tools/appliquer.py T024 --check
python3 -I -B specs/155-consolidation-projet/tools/appliquer.py T024
```

Résultat attendu : La première commande finit par `OK T024 : contrôle réussi, rien n'a été écrit (1 fichier(s) à écrire).` La seconde finit par `OK T024 : 1 fichier(s) écrit(s).`

**Étape 2** - Contrôle.

```bash
grep -rn "drag.real_press\|drag.real_router_press" Sources/; echo "rc=$?"
```

Résultat attendu : Aucune ligne trouvée, puis `rc=1`.

**Étape 3** - Lance la suite complète.

```bash
./scripts/test --no-parallel > /tmp/roadie155-test.log 2>&1; echo "exit=$?"
grep -E "Test run with|recorded an issue" /tmp/roadie155-test.log | tail -5
```

Résultat attendu : `exit=0` et une ligne `Test run with 2529 tests in 385 suites passed`. Le critère est `exit=0` et le mot `passed`. Si seul le nombre diffère, note-le dans ton compte rendu et continue. Un échec isolé hors de la spec 155 : piège P3 de `quickstart.md`.

**Étape 4** - Coche cette tâche et les tâches précédentes de la user story dans `tasks.md`, puis committe. Le message est exactement celui-ci, sans aucune ligne en plus.

```bash
git add -- Sources/RoadieDaemon/DropPreviewController.swift \
  Sources/RoadieDaemon/RailController.swift \
  CHANGELOG.md \
  specs/155-consolidation-projet/tasks.md
git commit -m "fix(155): Ne plus journaliser la position des clics"
git status --short
```

Résultat attendu : `git commit` affiche une ligne qui contient le message. `git status --short` n'affiche rien.

**Ce que l'outil change** (pour relecture, ne pas retaper)

- `T024a` dans `CHANGELOG.md`. Avant :

~~~~text
## Non publié
~~~~

  Après :

~~~~text
## Non publié

- Journal : Roadie n'écrit plus la position de chaque clic gauche (`drag.real_press`,
  `drag.real_router_press`).
~~~~

## T025 [US7] - Ajouter les tests de la complétion (tests d'abord)

**But** : Poser les 4 tests de `roadie completion zsh` avant le code.

**Étape 1** - Applique le changement préparé.

```bash
python3 -I -B specs/155-consolidation-projet/tools/appliquer.py T025 --check
python3 -I -B specs/155-consolidation-projet/tools/appliquer.py T025
```

Résultat attendu : La première commande finit par `OK T025 : contrôle réussi, rien n'a été écrit (1 fichier(s) à écrire).` La seconde finit par `OK T025 : 1 fichier(s) écrit(s).`

**Ce que l'outil change** (pour relecture, ne pas retaper)

- Copie `specs/155-consolidation-projet/gabarits/Spec155ShellCompletionTests.swift` (49 lignes) vers `Tests/RoadieDaemonTests/Spec155ShellCompletionTests.swift`.

**Pièges**

- Ne lance pas les tests maintenant. La compilation échoue jusqu'à la fin de T027 : c'est attendu.

## T026 [US7] - Ajouter le générateur de complétion

**But** : `ShellCompletion.swift` écrit le script zsh à partir de la table des commandes.

**Étape 1** - Applique le changement préparé.

```bash
python3 -I -B specs/155-consolidation-projet/tools/appliquer.py T026 --check
python3 -I -B specs/155-consolidation-projet/tools/appliquer.py T026
```

Résultat attendu : La première commande finit par `OK T026 : contrôle réussi, rien n'a été écrit (1 fichier(s) à écrire).` La seconde finit par `OK T026 : 1 fichier(s) écrit(s).`

**Ce que l'outil change** (pour relecture, ne pas retaper)

- Copie `specs/155-consolidation-projet/gabarits/ShellCompletion.swift` (63 lignes) vers `Sources/RoadieDaemon/ShellCompletion.swift`.

## T027 [US7] - Brancher `roadie completion zsh` dans le routeur

**But** : Une ligne dans la table des commandes et un cas dans l'aiguillage.

**Étape 1** - Applique le changement préparé.

```bash
python3 -I -B specs/155-consolidation-projet/tools/appliquer.py T027 --check
python3 -I -B specs/155-consolidation-projet/tools/appliquer.py T027
```

Résultat attendu : La première commande finit par `OK T027 : contrôle réussi, rien n'a été écrit (1 fichier(s) à écrire).` La seconde finit par `OK T027 : 1 fichier(s) écrit(s).`

**Étape 2** - Lance les tests de cette user story.

```bash
./scripts/test --no-parallel --filter Spec155ShellCompletionTests 2>&1 | grep -E "Test run with|recorded an issue|error:" | tail -5
```

Résultat attendu : Une ligne `Test run with 4 tests in 1 suite passed`.

**Ce que l'outil change** (pour relecture, ne pas retaper)

- `T027a` dans `Sources/RoadieDaemon/CLICommandRouter.swift`. Avant :

~~~~text
        CLICommandSpec(usage: "--version"),
~~~~

  Après :

~~~~text
        CLICommandSpec(usage: "--version"),
        CLICommandSpec(usage: "completion zsh"),
~~~~

- `T027b` dans `Sources/RoadieDaemon/CLICommandRouter.swift`. Avant :

~~~~text
        case "--version", "version":
            out("roadie \(RoadieVersion.current)")
        case nil:
~~~~

  Après :

~~~~text
        case "--version", "version":
            out("roadie \(RoadieVersion.current)")
        case "completion":
            guard args.count == 2, args[1] == "zsh" else { return usageError() }
            out(ShellCompletion.zsh(specs: Self.commandTable))
        case nil:
~~~~

## T028 [US7] - Ajouter `make coverage`

**But** : Le script `scripts/coverage`, la cible du Makefile et la règle `.gitignore` des relevés.

**Étape 1** - Applique le changement préparé.

```bash
python3 -I -B specs/155-consolidation-projet/tools/appliquer.py T028 --check
python3 -I -B specs/155-consolidation-projet/tools/appliquer.py T028
```

Résultat attendu : La première commande finit par `OK T028 : contrôle réussi, rien n'a été écrit (3 fichier(s) à écrire).` La seconde finit par `OK T028 : 3 fichier(s) écrit(s).`

**Étape 2** - Contrôle.

```bash
bash -n scripts/coverage; echo "syntaxe=$?"
test -x scripts/coverage; echo "executable=$?"
grep -c '^coverage:' Makefile
```

Résultat attendu : `syntaxe=0`, `executable=0`, `1`.

**Ce que l'outil change** (pour relecture, ne pas retaper)

- Copie `specs/155-consolidation-projet/gabarits/coverage` (37 lignes) vers `scripts/coverage`, rendu exécutable.

- `T028a` dans `Makefile`. Avant :

~~~~text
events config dmg package-dmg clean
~~~~

  Après :

~~~~text
events config dmg package-dmg clean coverage
~~~~

- `T028b` dans `Makefile`. Avant :

~~~~text
test:
	./scripts/test
~~~~

  Après :

~~~~text
test:
	./scripts/test

coverage:
	./scripts/coverage
~~~~

- `T028c` dans `.gitignore`. Avant :

~~~~text
/.specify/memory/*.bak-*
~~~~

  Après :

~~~~text
/.specify/memory/*.bak-*
*.profraw
~~~~

**Pièges**

- T028 exige T004 terminée (même fichier `.gitignore`).

## T029 [US7] - Documenter la complétion et la couverture

**But** : README français et anglais, guides CLI, changelog.

**Étape 1** - Applique le changement préparé.

```bash
python3 -I -B specs/155-consolidation-projet/tools/appliquer.py T029 --check
python3 -I -B specs/155-consolidation-projet/tools/appliquer.py T029
```

Résultat attendu : La première commande finit par `OK T029 : contrôle réussi, rien n'a été écrit (5 fichier(s) à écrire).` La seconde finit par `OK T029 : 5 fichier(s) écrit(s).`

**Ce que l'outil change** (pour relecture, ne pas retaper)

- `T029a` dans `README.md`. Avant :

~~~~text
make test
make build
~~~~

  Après :

~~~~text
make test
make coverage
make build
~~~~

- `T029b` dans `README.fr.md`. Avant :

~~~~text
make test
make build
~~~~

  Après :

~~~~text
make test
make coverage
make build
~~~~

- `T029c` dans `docs/fr/cli.md`. Avant :

~~~~text

## Fenetres et focus
~~~~

  Après :

~~~~text

## Complétion zsh

```bash
roadie completion zsh
```

La commande écrit un script de complétion pour zsh. Le script propose les commandes de `roadie` et le premier mot qui suit. Pour l'activer, ajoute cette ligne dans `~/.zshrc`, après `compinit` :

```zsh
source <(roadie completion zsh)
```

Le script vient de la table des commandes : une nouvelle commande y apparaît sans autre réglage. Les options comme `--json` ne sont pas proposées.

## Fenetres et focus
~~~~

- `T029d` dans `docs/en/cli.md`. Avant :

~~~~text

## Windows And Focus
~~~~

  Après :

~~~~text

## Zsh Completion

```bash
roadie completion zsh
```

The command writes a completion script for zsh. The script suggests the `roadie` commands and the first word after them. To turn it on, add this line to `~/.zshrc`, after `compinit`:

```zsh
source <(roadie completion zsh)
```

The script comes from the command table: a new command appears in it with no other change. Options such as `--json` are not suggested.

## Windows And Focus
~~~~

- `T029e` dans `CHANGELOG.md`. Avant :

~~~~text
## Non publié
~~~~

  Après :

~~~~text
## Non publié

- Terminal : `roadie completion zsh` écrit la complétion des commandes pour zsh. Mise en service :
  `source <(roadie completion zsh)` dans `~/.zshrc`, après `compinit`.
  Développement : `make coverage` mesure la couverture des tests.
~~~~

## T030 [US7] - Contrôler la user story 7 et committer

**But** : Vérifier le script de complétion, la suite, puis la mesure de couverture.

**Étape 1** - Construis, puis contrôle la complétion.

```bash
./scripts/with-xcode swift build 2>&1 | tail -3
.build/debug/roadie completion zsh | zsh -n; echo "zsh=$?"
.build/debug/roadie completion bash >/dev/null 2>&1; echo "bash=$?"
```

Résultat attendu : `zsh=0` et `bash=64`.

**Étape 2** - Lance la suite complète.

```bash
./scripts/test --no-parallel > /tmp/roadie155-test.log 2>&1; echo "exit=$?"
grep -E "Test run with|recorded an issue" /tmp/roadie155-test.log | tail -5
```

Résultat attendu : `exit=0` et une ligne `Test run with 2533 tests in 386 suites passed`. Le critère est `exit=0` et le mot `passed`. Si seul le nombre diffère, note-le dans ton compte rendu et continue. Un échec isolé hors de la spec 155 : piège P3 de `quickstart.md`.

**Étape 3** - Mesure la couverture (environ 3 minutes), puis retire le relevé laissé à la racine.

```bash
make coverage > /tmp/roadie155-coverage.log 2>&1; echo "coverage=$?"
tail -4 /tmp/roadie155-coverage.log
rm -f default.profraw
```

Résultat attendu : `coverage=0`, puis une ligne `coverage : lignes NN.NN% | fonctions NN.NN% | régions NN.NN%` (repère : lignes proches de 71 %).

**Étape 4** - Coche cette tâche et les tâches précédentes de la user story dans `tasks.md`, puis committe. Le message est exactement celui-ci, sans aucune ligne en plus.

```bash
git add -- Sources/RoadieDaemon/ShellCompletion.swift \
  Sources/RoadieDaemon/CLICommandRouter.swift \
  Tests/RoadieDaemonTests/Spec155ShellCompletionTests.swift \
  Makefile \
  scripts/coverage \
  .gitignore \
  README.md \
  README.fr.md \
  docs/fr/cli.md \
  docs/en/cli.md \
  CHANGELOG.md \
  specs/155-consolidation-projet/tasks.md
git commit -m "feat(155): Ajouter la complétion zsh et la mesure de couverture"
git status --short
```

Résultat attendu : `git commit` affiche une ligne qui contient le message. `git status --short` n'affiche rien.

**Pièges**

- Lance la suite avant `make coverage`. Après `make coverage`, les binaires de `.build/debug` écrivent un fichier `default.profraw` à chaque lancement : piège P4.
- `make coverage` rend 0 même si un test échoue pendant la mesure. Le résultat de la suite fait foi.

## T031 [US8] - Ajouter le workflow GitHub à la demande

**But** : Un fichier de workflow qui lance les tests seulement quand quelqu'un le demande.

**Étape 1** - Applique le changement préparé.

```bash
python3 -I -B specs/155-consolidation-projet/tools/appliquer.py T031 --check
python3 -I -B specs/155-consolidation-projet/tools/appliquer.py T031
```

Résultat attendu : La première commande finit par `OK T031 : contrôle réussi, rien n'a été écrit (1 fichier(s) à écrire).` La seconde finit par `OK T031 : 1 fichier(s) écrit(s).`

**Ce que l'outil change** (pour relecture, ne pas retaper)

- Copie `specs/155-consolidation-projet/gabarits/tests.yml` (22 lignes) vers `.github/workflows/tests.yml`.

## T032 [US8] - Contrôler la user story 8 et committer

**But** : Vérifier que le workflow n'a aucun déclencheur automatique.

**Étape 1** - Contrôle.

```bash
grep -c "workflow_dispatch" .github/workflows/tests.yml
grep -cE '^[[:space:]]*(push|pull_request|schedule):' .github/workflows/tests.yml
```

Résultat attendu : `1`, puis `0`.

**Étape 2** - Coche cette tâche et les tâches précédentes de la user story dans `tasks.md`, puis committe. Le message est exactement celui-ci, sans aucune ligne en plus.

```bash
git add -- .github/workflows/tests.yml \
  specs/155-consolidation-projet/tasks.md
git commit -m "ci(155): Ajouter les tests à la demande sur GitHub"
git status --short
```

Résultat attendu : `git commit` affiche une ligne qui contient le message. `git status --short` n'affiche rien.

**Pièges**

- Ne lance pas le workflow et ne pousse pas la branche : la CI automatique est la décision D5.

## T033 [US9] - Sortir ReplayableSnapshotProvider de LayoutMaintainer.swift

**But** : Une classe de 69 lignes part dans son propre fichier. Le code déplacé ne change pas.

**Étape 1** - Lance l'outil une seule fois, puis son contrôle.

```bash
test -e Sources/RoadieDaemon/ReplayableSnapshotProvider.swift || python3 -I -B specs/155-consolidation-projet/tools/extraire_fournisseur.py
python3 -I -B specs/155-consolidation-projet/tools/extraire_fournisseur.py --check
```

Résultat attendu : Première commande : `lignes_deplacees=69`, `lignes_restantes=4392`, puis une ligne `fichier=…` qui finit par `Sources/RoadieDaemon/ReplayableSnapshotProvider.swift`. Seconde commande : `OK : 69 lignes déplacées sans changement, 4392 lignes restent dans Sources/RoadieDaemon/LayoutMaintainer.swift`.

**Pièges**

- Ne déplace aucune ligne à la main et ne modifie pas le code déplacé.

## T034 [US9] - Contrôler la user story 9 et committer

**But** : Vérifier la taille du fichier et l'absence de régression.

**Étape 1** - Contrôle.

```bash
wc -l Sources/RoadieDaemon/LayoutMaintainer.swift
```

Résultat attendu : `4392 Sources/RoadieDaemon/LayoutMaintainer.swift`.

**Étape 2** - Lance la suite complète.

```bash
./scripts/test --no-parallel > /tmp/roadie155-test.log 2>&1; echo "exit=$?"
grep -E "Test run with|recorded an issue" /tmp/roadie155-test.log | tail -5
```

Résultat attendu : `exit=0` et une ligne `Test run with 2533 tests in 386 suites passed`. Le critère est `exit=0` et le mot `passed`. Si seul le nombre diffère, note-le dans ton compte rendu et continue. Un échec isolé hors de la spec 155 : piège P3 de `quickstart.md`.

**Étape 3** - Coche cette tâche et les tâches précédentes de la user story dans `tasks.md`, puis committe. Le message est exactement celui-ci, sans aucune ligne en plus.

```bash
git add -- Sources/RoadieDaemon/LayoutMaintainer.swift \
  Sources/RoadieDaemon/ReplayableSnapshotProvider.swift \
  specs/155-consolidation-projet/tasks.md
git commit -m "refactor(155): Sortir ReplayableSnapshotProvider de LayoutMaintainer"
git status --short
```

Résultat attendu : `git commit` affiche une ligne qui contient le message. `git status --short` n'affiche rien.

## T035 [US10] - Écrire la décision d'architecture 031

**But** : Roadie fait son premier appel réseau. L'ADR 031 dit pourquoi, quand et avec quelles limites.

**Étape 1** - Applique le changement préparé.

```bash
python3 -I -B specs/155-consolidation-projet/tools/appliquer.py T035 --check
python3 -I -B specs/155-consolidation-projet/tools/appliquer.py T035
```

Résultat attendu : La première commande finit par `OK T035 : contrôle réussi, rien n'a été écrit (1 fichier(s) à écrire).` La seconde finit par `OK T035 : 1 fichier(s) écrit(s).`

**Ce que l'outil change** (pour relecture, ne pas retaper)

- Copie `specs/155-consolidation-projet/gabarits/031-premier-appel-reseau.md` (28 lignes) vers `docs/decisions/031-premier-appel-reseau.md`.

## T036 [US10] - Ajouter les tests de la vérification de version (tests d'abord)

**But** : Poser les 5 tests de `roadie update check` avant le code.

**Étape 1** - Applique le changement préparé.

```bash
python3 -I -B specs/155-consolidation-projet/tools/appliquer.py T036 --check
python3 -I -B specs/155-consolidation-projet/tools/appliquer.py T036
```

Résultat attendu : La première commande finit par `OK T036 : contrôle réussi, rien n'a été écrit (1 fichier(s) à écrire).` La seconde finit par `OK T036 : 1 fichier(s) écrit(s).`

**Ce que l'outil change** (pour relecture, ne pas retaper)

- Copie `specs/155-consolidation-projet/gabarits/Spec155ReleaseCheckTests.swift` (44 lignes) vers `Tests/RoadieDaemonTests/Spec155ReleaseCheckTests.swift`.

**Pièges**

- Ne lance pas les tests maintenant. La compilation échoue jusqu'à la fin de T037 : c'est attendu.

## T037 [US10] - Ajouter ReleaseCheck.swift

**But** : Le code qui demande à GitHub la dernière version publiée, avec un délai de 5 secondes.

**Étape 1** - Applique le changement préparé.

```bash
python3 -I -B specs/155-consolidation-projet/tools/appliquer.py T037 --check
python3 -I -B specs/155-consolidation-projet/tools/appliquer.py T037
```

Résultat attendu : La première commande finit par `OK T037 : contrôle réussi, rien n'a été écrit (1 fichier(s) à écrire).` La seconde finit par `OK T037 : 1 fichier(s) écrit(s).`

**Ce que l'outil change** (pour relecture, ne pas retaper)

- Copie `specs/155-consolidation-projet/gabarits/ReleaseCheck.swift` (117 lignes) vers `Sources/RoadieDaemon/ReleaseCheck.swift`.

## T038 [US10] - Brancher `roadie update check` dans le routeur

**But** : Une ligne dans la table des commandes et un cas dans l'aiguillage.

**Étape 1** - Applique le changement préparé.

```bash
python3 -I -B specs/155-consolidation-projet/tools/appliquer.py T038 --check
python3 -I -B specs/155-consolidation-projet/tools/appliquer.py T038
```

Résultat attendu : La première commande finit par `OK T038 : contrôle réussi, rien n'a été écrit (1 fichier(s) à écrire).` La seconde finit par `OK T038 : 1 fichier(s) écrit(s).`

**Étape 2** - Lance les tests de cette user story.

```bash
./scripts/test --no-parallel --filter Spec155ReleaseCheckTests 2>&1 | grep -E "Test run with|recorded an issue|error:" | tail -5
```

Résultat attendu : Une ligne `Test run with 5 tests in 1 suite passed`.

**Ce que l'outil change** (pour relecture, ne pas retaper)

- `T038a` dans `Sources/RoadieDaemon/CLICommandRouter.swift`. Avant :

~~~~text
        CLICommandSpec(usage: "completion zsh"),
~~~~

  Après :

~~~~text
        CLICommandSpec(usage: "completion zsh"),
        CLICommandSpec(usage: "update check"),
~~~~

- `T038b` dans `Sources/RoadieDaemon/CLICommandRouter.swift`. Avant :

~~~~text
            out(ShellCompletion.zsh(specs: Self.commandTable))
        case nil:
~~~~

  Après :

~~~~text
            out(ShellCompletion.zsh(specs: Self.commandTable))
        case "update":
            guard args.count == 2, args[1] == "check" else { return usageError() }
            let outcome = ReleaseCheck.evaluate(current: RoadieVersion.current) { ReleaseCheck.fetchLatestRelease() }
            if let text = outcome.stdout { out(text) }
            if let text = outcome.stderr { err(text) }
            return outcome.exitCode
        case nil:
~~~~

**Pièges**

- T038 exige T027 terminée : son texte « avant » est le texte ajouté par T027.

## T039 [US10] - Documenter `roadie update check`

**But** : Guides CLI français et anglais, changelog.

**Étape 1** - Applique le changement préparé.

```bash
python3 -I -B specs/155-consolidation-projet/tools/appliquer.py T039 --check
python3 -I -B specs/155-consolidation-projet/tools/appliquer.py T039
```

Résultat attendu : La première commande finit par `OK T039 : contrôle réussi, rien n'a été écrit (3 fichier(s) à écrire).` La seconde finit par `OK T039 : 3 fichier(s) écrit(s).`

**Ce que l'outil change** (pour relecture, ne pas retaper)

- `T039a` dans `docs/fr/cli.md`. Avant :

~~~~text

## Fenetres et focus
~~~~

  Après :

~~~~text

## Mises à jour

```bash
roadie update check
```

La commande demande à GitHub le numéro de la dernière version publiée et le compare à la version installée. Elle ne télécharge rien et n'installe rien. C'est le seul appel réseau de Roadie : il part seulement quand tu lances cette commande. Aucune donnée personnelle n'est envoyée.

- Code 0 : la version installée est à jour, ou une version plus récente existe. Dans ce cas, la commande affiche son numéro et son adresse.
- Code 1 : la vérification a échoué (pas de réseau, délai de 5 secondes dépassé, réponse inattendue).

## Fenetres et focus
~~~~

- `T039b` dans `docs/en/cli.md`. Avant :

~~~~text

## Windows And Focus
~~~~

  Après :

~~~~text

## Updates

```bash
roadie update check
```

The command asks GitHub for the latest published version and compares it with the installed version. It downloads nothing and installs nothing. It is the only network call Roadie makes: it runs only when you type this command. No personal data is sent.

- Code 0: the installed version is up to date, or a newer version exists. In that case, the command prints its number and its address.
- Code 1: the check failed (no network, 5-second timeout, unexpected response).

## Windows And Focus
~~~~

- `T039c` dans `CHANGELOG.md`. Avant :

~~~~text
## Non publié
~~~~

  Après :

~~~~text
## Non publié

- Mises à jour : `roadie update check` indique si une version plus récente est publiée.
  C'est le seul appel réseau de Roadie ; il part seulement quand tu lances la commande.
  Rien n'est téléchargé ni installé.
~~~~

## T040 [US10] - Contrôler la user story 10 et committer

**But** : Un seul appel réel à GitHub, puis la suite et le commit.

**Étape 1** - Construis, puis lance la commande une fois. C'est le seul appel réseau autorisé.

```bash
./scripts/with-xcode swift build 2>&1 | tail -3
rm -f default.profraw
time .build/debug/roadie update check; echo "code=$?"
.build/debug/roadie update >/dev/null 2>&1; echo "usage=$?"
rm -f default.profraw
```

Résultat attendu : Réponse en 6 secondes au plus. `code=0` avec un message sur la version (par exemple `Roadie is up to date (0.13.0).`), ou `code=1` avec un message d'échec si le réseau manque. Puis `usage=64`.

**Étape 2** - Lance la suite complète.

```bash
./scripts/test --no-parallel > /tmp/roadie155-test.log 2>&1; echo "exit=$?"
grep -E "Test run with|recorded an issue" /tmp/roadie155-test.log | tail -5
```

Résultat attendu : `exit=0` et une ligne `Test run with 2538 tests in 387 suites passed`. Le critère est `exit=0` et le mot `passed`. Si seul le nombre diffère, note-le dans ton compte rendu et continue. Un échec isolé hors de la spec 155 : piège P3 de `quickstart.md`.

**Étape 3** - Coche cette tâche et les tâches précédentes de la user story dans `tasks.md`, puis committe. Le message est exactement celui-ci, sans aucune ligne en plus.

```bash
git add -- docs/decisions/031-premier-appel-reseau.md \
  Sources/RoadieDaemon/ReleaseCheck.swift \
  Sources/RoadieDaemon/CLICommandRouter.swift \
  Tests/RoadieDaemonTests/Spec155ReleaseCheckTests.swift \
  docs/fr/cli.md \
  docs/en/cli.md \
  CHANGELOG.md \
  specs/155-consolidation-projet/tasks.md
git commit -m "feat(155): Ajouter roadie update check"
git status --short
```

Résultat attendu : `git commit` affiche une ligne qui contient le message. `git status --short` n'affiche rien.

**Pièges**

- `code=1` sans réseau est un résultat correct : note-le. Ne relance pas la commande en boucle.
- Le message est en anglais ou en français selon la langue de macOS.

## T041 [US11] - Écrire l'inventaire des images et diaporamas publiés

**But** : Lister les fichiers visibles sur le dépôt public. Aucun fichier n'est retiré.

**Étape 1** - Lance l'outil.

```bash
python3 -I -B specs/155-consolidation-projet/tools/inventaire.py
```

Résultat attendu : `OK : 26 image(s) et 21 diaporama(s) listés dans …/validation/inventaire-publications.md`.

**Pièges**

- Ne supprime aucune image : le retrait est la décision D8.

## T042 [US11] - Committer l'inventaire

**But** : Enregistrer l'inventaire.

**Étape 1** - Coche cette tâche et les tâches précédentes de la user story dans `tasks.md`, puis committe. Le message est exactement celui-ci, sans aucune ligne en plus.

```bash
git add -- specs/155-consolidation-projet/validation/inventaire-publications.md \
  specs/155-consolidation-projet/tasks.md
git commit -m "docs(155): Inventorier les images et diaporamas publiés"
git status --short
```

Résultat attendu : `git commit` affiche une ligne qui contient le message. `git status --short` n'affiche rien.

## T043 [Polish] - Contrôle final complet

**But** : Relancer toute la suite et les tests des scripts sur l'état final.

**Étape 1** - Lance la suite complète.

```bash
./scripts/test --no-parallel > /tmp/roadie155-test.log 2>&1; echo "exit=$?"
grep -E "Test run with|recorded an issue" /tmp/roadie155-test.log | tail -5
```

Résultat attendu : `exit=0` et une ligne `Test run with 2538 tests in 387 suites passed`. Le critère est `exit=0` et le mot `passed`. Si seul le nombre diffère, note-le dans ton compte rendu et continue. Un échec isolé hors de la spec 155 : piège P3 de `quickstart.md`.

**Étape 2** - Lance les tests des scripts.

```bash
python3 -I -B -m unittest discover -s scripts/tests 2>&1 | tail -3
```

Résultat attendu : `Ran 28 tests` puis `OK`.

## T044 [Polish] - Remplir le reçu de validation

**But** : Écrire dans `validation.md` la valeur observée de chaque critère.

**Étape 1** - Applique le changement préparé.

```bash
python3 -I -B specs/155-consolidation-projet/tools/appliquer.py T044 --check
python3 -I -B specs/155-consolidation-projet/tools/appliquer.py T044
```

Résultat attendu : La première commande finit par `OK T044 : contrôle réussi, rien n'a été écrit (1 fichier(s) à écrire).` La seconde finit par `OK T044 : 1 fichier(s) écrit(s).`

**Étape 2** - Pour chaque ligne du tableau, lance la commande de la colonne « Commande » et écris le résultat dans la colonne « Observé ». Pour SC-003, relance le bloc de T012. Pour SC-009 et SC-010, tu peux reprendre la valeur de T030 et de T040 en écrivant « observé en T030 » ou « observé en T040 ». Remplis aussi les sections « Tâches non terminées » et « Non vérifié ».

```bash
grep -c "À REMPLIR" specs/155-consolidation-projet/validation.md
```

Résultat attendu : `0`.

**Ce que l'outil change** (pour relecture, ne pas retaper)

- Copie `specs/155-consolidation-projet/gabarits/validation.md` (40 lignes) vers `specs/155-consolidation-projet/validation.md`.

**Pièges**

- N'écris jamais une valeur que tu n'as pas observée. Écris « non vérifié » et la raison.
- Ne relance pas `appliquer.py T044` après avoir rempli le fichier.

## T045 [Polish] - Consigner la session et committer

**But** : Ajouter le bilan à la fin du journal des sessions et faire le dernier commit.

**Étape 1** - Dans le bloc ci-dessous, remplace `NN`, `TTTT` et `SSS` par les valeurs observées, puis lance-le.

```bash
cat >> .specify/memory/sessions/journal.md <<'EOF'

Session 155 implémentée, non installée : NN tâches sur 45 cochées. Documentation publique nettoyée,
commit du build dans la version, garde-fou des réglages, consignes des agents allégées, lectures
d'accessibilité contrôlées, clics retirés du journal, complétion zsh, mesure de couverture, tests
GitHub à la demande, ReplayableSnapshotProvider sorti de LayoutMaintainer, `roadie update check`,
inventaire des images publiées. TTTT tests / SSS suites et 28 tests de scripts réussis.
Aucune installation, aucun push, aucune release. Décisions en attente : D1 à D5 et D8.
Reçu : specs/155-consolidation-projet/validation.md.
EOF
tail -3 .specify/memory/sessions/journal.md
```

Résultat attendu : Les trois dernières lignes du journal sont celles du bilan.

**Étape 2** - Coche cette tâche et les tâches précédentes de la user story dans `tasks.md`, puis committe. Le message est exactement celui-ci, sans aucune ligne en plus.

```bash
git add -- specs/155-consolidation-projet/validation.md \
  .specify/memory/sessions/journal.md \
  specs/155-consolidation-projet/tasks.md
git commit -m "docs(155): Consigner la validation de la consolidation"
git status --short
```

Résultat attendu : `git commit` affiche une ligne qui contient le message. `git status --short` n'affiche rien.

**Pièges**

- Ne change pas le statut de `spec.md`. Ne pousse rien. L'installation, la revue et la livraison sont faites plus tard par le responsable.
