# Data Model: Boîte de commandes et fenêtre de réglages

Types Swift prévus, tous dans `RoadieDaemon` sauf mention. Les types « purs » n'importent ni AppKit ni SwiftUI.

## SlashCommand (pur, `SlashCommandCatalog.swift`)

| Champ | Type | Rôle |
|---|---|---|
| `name` | `String` | nom sans `/` (`stage`) |
| `aliases` | `[String]` | `s` pour `stage`, `d` pour `desktop`, `b` pour `bm` |
| `summary` | `String` | description courte affichée dans la liste |
| `usage` | `String` | forme attendue, affichée en cas d'erreur (`/stage N\|nom\|new\|rename NOM\|send N`) |
| `parse` | `([String]) -> Result<SlashInvocation, SlashError>` | transforme les arguments |

`SlashCommandCatalog.all: [SlashCommand]` : 19 commandes + `/settings` et `/set` (21 entrées). `suggestions(for input: String) -> [SlashSuggestion]` : filtre en O(c), insensible à la casse et aux accents, les noms qui commencent par la saisie d'abord, puis ceux qui la contiennent.

## SlashInvocation (pur)

```text
enum SlashInvocation {
  case router(argv: [String])                 // CLICommandRouter.run
  case routerDeferred(argv: [String])         // après fermeture de la boîte (grille, lettres, restart)
  case openSettings(category: String?)
  case setting(SettingRequest)                // lire, écrire, rétablir
}
enum SettingRequest { case read(name), write(name, rawValue), reset(name) }
struct SlashError { message: String; usage: String }
```

Règles :
- Les directions sont normalisées : `gauche`→`left`, `droite`→`right`, `haut`→`up`, `bas`→`down`, et les mots anglais sont acceptés tels quels.
- `/stage nom` et `/stage new` ont besoin de l'état des stages : `parse` renvoie `.router` avec un marqueur de résolution (`StageRef.byName(String)` / `.next`) que le lanceur résout avant l'appel (R11).

## SlashCommandModel (pur, `SlashCommandModel.swift`)

| Champ | Type | Rôle |
|---|---|---|
| `input` | `String` | texte saisi, sans le `/` initial |
| `suggestions` | `[SlashSuggestion]` | liste filtrée (commandes, ou arguments après le premier espace) |
| `selected` | `Int?` | suggestion en surbrillance |
| `history` | `[String]` | 50 au plus, ancienne → récente |
| `historyCursor` | `Int?` | position pendant le parcours |
| `message` | `SlashMessage?` | `.info(lines)` ou `.error(text, usage)` |

Opérations : `type(_:)`, `deleteBackward()`, `complete()` (Tab), `nextSuggestion()`, `previousSuggestion()`, `historyUp()`, `historyDown()`, `submit() -> SlashSubmission`. Un message s'efface à la frappe suivante. Effacer le `/` rend la main à `TargetSearchModel`.

`SlashSuggestion` : `text` (à insérer), `detail` (description), `kind` (`.command`, `.argument`, `.setting`).

Sources des arguments : noms de stage et de bookmark (R1/R9, cibles `.stage` et `.bookmark` déjà présentes dans `model.targets`), noms de réglage (`SettingsCatalog`), catégories, directions, dispositions.

## CommandHistoryStore (`SlashCommandRunner.swift`)

Fichier `~/.local/state/roadies/command-history.json` : `["stage 2", "screen droite", …]`. Chargé par `JSONPersistence.load`, écrit par `JSONPersistence.write`. 50 entrées au plus ; un doublon consécutif est ignoré.

## SlashCommandRunner (`@MainActor`)

`run(_ invocation: SlashInvocation, settings: SettingsService, openSettings: (String?) -> Void) -> SlashOutcome`

```text
enum SlashOutcome {
  case done(message: [String])        // la boîte se ferme
  case failed(SlashError)             // la boîte reste ouverte
  case deferred(argv: [String])       // la boîte se ferme, l'action part au tour suivant
  case info([String])                 // résultat affiché dans la boîte (/set nom, /doctor)
}
```

`/doctor` renvoie `.info` (la boîte reste ouverte sur le résultat). `/set nom valeur` réussi renvoie `.info(["nom = valeur"])`.

## SettingDescriptor (pur, `SettingsCatalog.swift`)

| Champ | Type | Rôle |
|---|---|---|
| `id` | `String` | `catégorie.clé` (`grille.rows`) |
| `category` | `SettingCategory` | catégorie de la fenêtre |
| `tablePath` | `String` | table TOML (`experimental.target_grid`) |
| `key` | `String` | clé TOML (`rows`) |
| `label` | `String` | libellé français |
| `help` | `String` | description courte |
| `kind` | `SettingKind` | `.bool`, `.int(range)`, `.double(range)`, `.choice([String])`, `.text`, `.color` |
| `defaultValue` | `SettingValue` | valeur par défaut |
| `readOnlyReason` | `String?` | présent pour les listes et tableaux de tables |

```text
enum SettingCategory: CaseIterable { general, tuilage, stages, lettres, grille, recherche, rail, bordures, focus, regles, avance }
enum SettingValue: Equatable { bool(Bool), int(Int), double(Double), string(String), unset }
```

`SettingsCatalog.all: [SettingDescriptor]` (167 réglages simples + entrées en lecture seule), `find(id:)`, `search(_ query: String)` (nom, libellé, description ; insensible à la casse et aux accents), `byCategory`. L'ordre dans une catégorie = l'ordre de la table du fichier.

## SettingsService (`SettingsService.swift`)

| Opération | Entrée | Sortie |
|---|---|---|
| `value(of:)` | descripteur | valeur du fichier, ou défaut si la clé est absente (`isDefault`) |
| `set(_:to:)` | id, texte brut | `.applied(old, new)` ou `.rejected(reason)` |
| `reset(_:)` | id | retire la ligne du fichier (retour au défaut) ou écrit le défaut si la table n'est pas gérée |
| `describe(_:)` | id | « valeur (défaut X, de A à B) » |
| `validity()` | — | état du fichier (valide, erreurs, chemin) pour la catégorie Général |

Conversion et contrôle : texte brut → `SettingValue` selon `kind` (plage, liste de choix, forme `#RRGGBB` ou `#RRGGBBAA`), puis `ConfigFileEditor`, puis validation (R5). Après écriture : `ConfigReloadService.shared.currentConfig()` applique la valeur ; `EventLog` reçoit `settings.changed`.

## ConfigFileEditor (pur côté texte, `ConfigFileEditor.swift`)

`static func edit(_ text: String, table: String, key: String, value: String?) -> Result<String, ConfigEditError>` : renvoie le nouveau texte. `value == nil` retire la ligne de la clé. `ConfigEditError` : `.multilineValue(line)`, `.ambiguousTable`. Un second niveau gère l'E/S : lecture, validation du texte, sauvegarde `roadies.toml.bak-<horodatage>` à la première écriture de la session, écriture atomique.

## TargetOverlayStyle (modifié)

Nouveau champ `labelFontSize: CGFloat` (défaut 13) et propriété calculée `scale = labelFontSize / 13`. Utilisée par `TargetOverlayView` pour : police du badge, hauteur (24) et largeur minimale (28), rayon (8), `gap` (10), `inset` (6), pas de placement (6), marge d'évitement (4), marge de bord (4).

## Configuration (modifiée)

`TargetModeConfig.labelFontSize: Double` et `TargetGridConfig.labelFontSize: Double`, défaut 13, clamp 8…48, validation « hors plage » dans `validateTargetMode` et `validateTargetGrid`, clé ajoutée à `knownKeys` et à `examples/roadies.toml`.
