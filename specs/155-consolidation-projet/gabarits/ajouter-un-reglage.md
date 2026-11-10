# Ajouter un réglage

Un réglage de Roadie se déclare à plusieurs endroits. Si un endroit manque, le réglage est
ignoré sans message, ou la fenêtre des paramètres ne le montre pas. Cette page donne les
étapes dans l'ordre, puis les tests qui signalent un oubli.

Exemple suivi : `calc_opens_calculator` (session 110), un booléen de la table
`[experimental.target_mode]`. Pour retrouver chaque endroit :

```bash
grep -rn "calcOpensCalculator\|calc_opens_calculator" Sources Tests docs
```

## Étapes

Dans `Sources/RoadieCore/Config.swift`, sur la structure de la table concernée
(ici `TargetModeConfig`) :

1. **La propriété** : `public var calcOpensCalculator: Bool`.
2. **Le paramètre de l'initialiseur, avec sa valeur par défaut** :
   `calcOpensCalculator: Bool = false,` puis `self.calcOpensCalculator = calcOpensCalculator`.
3. **La clé TOML** dans `CodingKeys` : `case calcOpensCalculator = "calc_opens_calculator"`.
4. **La lecture** dans `init(from:)`, avec la même valeur par défaut :
   `calcOpensCalculator: try c.decodeIfPresent(Bool.self, forKey: .calcOpensCalculator) ?? false,`.
   Toujours `decodeIfPresent` : un fichier sans la clé doit rester valide.
5. **La clé connue du validateur** : ajouter `"calc_opens_calculator"` à la liste de la
   table `"experimental.target_mode"` dans `ConfigValidationRules.knownKeys`. Sans cela,
   `roadie config validate` signale une clé inconnue.

Ensuite :

6. **Le descripteur des paramètres** dans `Sources/RoadieDaemon/SettingsCatalog.swift` :
   une ligne `entry(.recherche, "experimental.target_mode", "calc_opens_calculator", tr("…", "…"), …)`.
   Les deux textes de `tr(fr, en)` sont obligatoires.
7. **Le compteur du catalogue** dans `Tests/RoadieDaemonTests/SettingsCatalogTests.swift`,
   test `catalogMatchesTheScalarKeysKnownByTheValidator` : augmenter de 1 la valeur de
   `#expect(expected.count == …)` pour chaque réglage simple ajouté (texte, nombre, booléen).
8. **Un test du réglage** : valeur par défaut, lecture depuis un fichier TOML, effet.
   Modèle : `Tests/RoadieDaemonTests/Spec110CalcCalculatorTests.swift`.
9. **La documentation**, en français et en anglais : `docs/fr/features.md` et
   `docs/en/features.md`, puis `CHANGELOG.md`, section « Non publié ».

## Tests qui signalent un oubli

Lancer `./scripts/test --no-parallel`.

| Oubli | Test en échec | Message |
|-------|---------------|---------|
| Étape 5 (clé absente du validateur) | `Spec155ConfigGuardTests.everyDefaultSettingIsKnownByTheValidator` | « réglages encodés mais absents de knownKeys » |
| Nouvelle table absente du validateur | le même test | « tables encodées mais absentes de knownKeys » |
| Étape 4 (valeur par défaut différente à la lecture) | `Spec155ConfigGuardTests.anEmptyFileGivesTheDefaultConfiguration` | les deux configurations diffèrent |
| Étape 6 (pas de descripteur) | `SettingsCatalogTests.catalogMatchesTheScalarKeysKnownByTheValidator` | « clés du validateur sans descripteur » |
| Étape 5 oubliée mais étape 6 faite | le même test | « descripteurs sans clé connue du validateur » |
| Étape 7 (compteur) | le même test | le nombre attendu diffère |

## Limites des gardes

- Un réglage facultatif dont la valeur par défaut est `nil` n'est pas encodé : le premier
  test ne le voit pas. Le test du catalogue reste actif pour lui.
- Les tableaux de tables vides (`[[rules]]`, `[[shortcuts]]`) ne sont pas parcourus.
- Aucun test ne vérifie la documentation (étape 9).

## Pièges

- Après l'ajout d'un champ à une structure de `RoadieCore`, les tests peuvent planter au
  signal 11 (« outlined destroy »). Remède : supprimer
  `.build/arm64-apple-macosx/debug/RoadieTilerTests.build`, puis relancer les tests.
- Erreur d'édition de liens « Undefined symbols … TargetModeConfig.init » :
  `touch Sources/RoadieDaemon/OverviewController.swift`, puis relancer.
