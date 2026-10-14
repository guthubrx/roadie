# Contrat de travail — version 1

## Catalogue et valeurs

Conserver SettingKind et SettingValue scalaires. Ajouter à SettingDescriptor
`collection: CollectionSpec? = nil` ; les douze entrées ont readOnlyReason nil.

Types publics dans un nouveau fichier détenu par la configuration :

```swift
CollectionSpec {
    shape: Shape
    defaultValue: CollectionValue
}
Shape.list(element: SettingKind, suggestions: [String], minCount: Int,
           unique: Bool, sorted: Bool)
Shape.rows(table: String, fields: [CollectionFieldSpec], uniqueKey: String?,
           oneOf: [[String]])
Shape.advanced(table: String)
CollectionFieldSpec { path: [String], label: String, help: String,
                      kind: SettingKind, required: Bool, defaultValue: SettingValue }
CollectionValue.list([SettingValue])
CollectionValue.rows([CollectionRow])
CollectionValue.advanced(String)
CollectionRow { fields: [String: SettingValue], sourceIndex: Int? }
```

Tous les types sont Equatable et Sendable, avec des init accessibles.
La clé d'un champ de ligne est path joint par un point. sourceIndex est facultatif
et vaut nil pour une nouvelle ligne ; il sert à conserver le bloc source et ses
champs inconnus lors d'un déplacement. Une lecture après succès actualise ces indices.

## Service

```swift
collection(of descriptor: SettingDescriptor) -> Result<CollectionValue, SettingsFileError>
collection(of descriptor: SettingDescriptor, in text: String) -> Result<CollectionValue, SettingsFileError>
validateCollection(_ descriptor: SettingDescriptor, value: CollectionValue) -> [String: String]
setCollection(_ id: String, _ value: CollectionValue,
              expected: CollectionValue? = nil) -> SettingChangeResult
resetCollection(_ id: String) -> SettingChangeResult
replaceConfigText(_ text: String, expectedOriginal: String) -> SettingChangeResult
```

Le résultat existant reste scalaire : old/new sont des résumés, pas le fichier entier.
value(of:) donne un résumé et l'indicateur de défaut pour les collections afin de
conserver isDefault/Reset. reset(id) peut déléguer resetCollection pour ces descripteurs.
L'interface appelle collection après une écriture réussie. Une collection modifiée
depuis sa lecture est refusée via expected ; le fichier complet utilise expectedOriginal.

Réutiliser convert pour la saisie scalaire. Ne pas différer les textes valides
jusqu'à Retour : la demande utilisateur exige leur application pendant la saisie.
Une chaîne ou une couleur incomplète reste en brouillon, sans écriture invalide.

## Écriture et notification

Réutiliser la transaction atomique de SettingsService via transformation du texte.
TOMLKit existant sert à lire et vérifier ; ConfigFileEditor conserve les lignes.
Préserver les commentaires, y compris ceux d'une liste multiligne : ils peuvent
être conservés comme lignes de commentaire proches, mais ne doivent pas disparaître.
Conserver champs inconnus et sous-tables lors des edits et déplacements de lignes.
Le rail exige des blocs canoniques [[fx.rail.preview.stage_overrides]].

Notification publique roadieSettingsDidChange : userInfo `configPath` et `settingID`.
Les identifiants sont ceux du catalogue, sans fx. ni experimental. ; une édition
complète envoie `*`. Les transformations sans changement ne notifient pas.

## Polices et limites

SettingsFontFamilyPicker(fontSize: Double, selection: Binding<String>).
SettingsCatalog.fontFamilyDescriptors contient deux .text, à ajouter au catalogue :
target_mode.search_font_family et target_mode.command_font_family, défaut system.

L'éditeur signals.hooks explique que cette structure connue n'est pas exécutée
par Roadie actuellement ; cette session ajoute l'édition, pas un exécuteur nouveau.
Ne pas inventer de plafonds arbitraires 400 points ou ratio 3 ; reprendre les
contraintes effectives du modèle et du validateur existants.
