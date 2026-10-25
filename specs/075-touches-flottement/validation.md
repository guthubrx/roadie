# Validation 075

## Tests
- `Spec075KeysTests` (8 tests) : variantes par objet et touche (⌘ nouvelle stage et suivi,
  ⌥ amener ici sauf stage déjà active, ⌃ recherche web, cibles à l'écran inchangées), encodage
  de l'adresse web, verbes de flottement selon l'état, règle unique par application (affinité et
  flottement conservés l'un sans l'autre, règle vide supprimée), ⌘1 à ⌘9 (rangée et pavé), Retour
  avec ⌥/⌃, → en fin de saisie sur le vrai panneau AppKit.
- Suite complète `scripts/test --no-parallel` : 1 983 tests / 260 suites réussis.
- `SettingsCatalogTests` : 200 réglages simples, `actions_hotkey` avec capture native.

## Essai réel
- Installation signée roadied-cert, PID 93278 puis réinstallée avec le journal
  `target_mode.actions_started` ; santé 5/5.
- `roadie targets actions` deux fois : événements `focusedWindowID 19149, subject window` ; la barre
  montre les verbes de Microsoft Teams, dont « Toujours faire flotter Microsoft Teams », avec
  ⌘2 à ⌘8 et le champ « Verbe ou destination… ». Captures locales supprimées (contenu privé).
- Rendu de la variante tenue et des rappels ⌘n vérifié sur données fictives.

## Limites
- Délai d'affichage de la variante (critère 16 ms) non mesuré : l'annonce est redessinée à
  l'événement `flagsChanged`, sans attente.
- Un premier appel, avant l'ajout du journal, a montré la liste normale ; non reproduit en deux
  essais suivants. Le journal `target_mode.actions_started` permettra de le diagnostiquer.
- Variantes, ⌘n et flottement durable non essayés au clavier par l'utilisateur.
- Tuiler « juste cette fenêtre » quand macOS la fait flotter par nature n'est pas proposé.
- Preuves : diaporama non produit, les écrans réels contiennent des conversations privées.

## Incident de build
Signal 11 dans `RoadieTilerTests` (« outlined destroy of RoadieConfig ») : objets de test
périmés après l'ajout de deux champs à `TargetModeConfig`. Supprimer
`.build/arm64-apple-macosx/debug/RoadieTilerTests.build` a suffi ; aucune modification de code.
