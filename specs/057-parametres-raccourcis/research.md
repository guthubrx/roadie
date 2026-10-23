# Recherche et réemploi
Diagnostic: SettingsView regroupe une catégorie en une seule carte; SettingsCollectionEditor expose tous les champs en lignes génériques. Réutiliser SettingsService et les protections d'écriture concurrente. SettingsViewModel porte déjà polices, filtres et observation.
AltTab distingue focus/hold/search et profils. Source 2d4f4c8fab1eeb3ec08f32abdf541713b68d89d0 étudiée dans les analyses; aucun code importé.
Apple NSEvent expose keyCode/modifierFlags. Un tap clavier temporaire existe dans TargetOverlayPresenter et peut être adapté à la capture d'un raccourci réservé, avec les permissions du daemon.
Sources: https://developer.apple.com/design/human-interface-guidelines/settings ; https://developer.apple.com/documentation/appkit/nsevent ; https://alt-tab.app/features
BTT: API AppleScript officielle, raw script dans BTTShellTaskActionScript, wrapper dans Config; keycode Tab48, caractère réel plutôt qu'un libellé. Vérification physique indispensable après configuration.
Pas d'outil Sequential Thinking exposé dans le catalogue de cette session: arbitrages explicités dans ce plan et l'ADR avant code. Mémoire projet Roadie MEMORY.md non trouvée dans les répertoires usuels; artefacts projet relus.

