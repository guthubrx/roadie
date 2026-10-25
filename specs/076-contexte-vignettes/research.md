# Recherche 076

## R1 Où placer le contexte dans l'ordre
`LauncherList.before` compare : usages exacts, usages préfixes, score, fréquence-récence. Placer la
fréquence-récence de la stage avant le score ferait remonter un appariement faible ; la placer
juste après ne départage que des appariements de même qualité (cas typique : une seule lettre,
tous les débuts de mot à égalité). Les usages exacts de la stage passent avant les usages
globaux : ce que l'on choisit ici l'emporte sur ce que l'on choisit ailleurs.

## R2 Identité de la stage
Nom si la stage est nommée (unique dans tout Roadie depuis SPEC-067, survit aux déplacements),
sinon `display/desktop/stage`. Une stage anonyme déplacée perd sa mémoire : acceptable, rare.

## R3 Compatibilité du fichier
`Entry` est `Codable` synthétisé ; un champ optionnel absent se décode à nil, un champ inconnu
est ignoré par le décodeur 073 (`JSONDecoder` ignore les clés en trop). Aucune migration.

## R4 Vignettes
`RailThumbnailStore.shared` (MainActor) garde `detailed` (vue d'ensemble, nette) et `images` (rail,
sélecteur). `hasCapturedImage` distingue une capture d'une icône de repli. Le renderer est
MainActor : lecture directe, sans copie. L'image n'est pas mise dans le cache d'icônes du renderer
(elle change).
