# Modèle 093

## AlfredBridge.Order
`search`, `trigger`, `setConfiguration`, `removeConfiguration`, `reload`, `reveal`, `version`,
`activate`, `quit` ; `untranslated(String)` pour une forme reconnue dont l'ordre ne l'est pas.

## Réglages gardés
`~/.roadies/workflows-settings/<identifiant>.json` : objet JSON `{ "clé": "valeur" }`. Identifiant :
`bundleid`, sinon le nom du dossier. Fusionné après `prefs.plist` (priorité aux réglages gardés).

## AlfredCompatibilityReport (étendu)
`orders: [String]` (ordres traduits trouvés), `untranslated: [String]` ; `mentionsAlfred` vaut
« au moins un ordre ».

## Commande `roadie workflow alfred`
| Ordre | Arguments | Effet |
|---|---|---|
| search | TEXTE | barre rouverte (démon) |
| trigger | WORKFLOW NOM [ARGUMENT] | déclencheur externe (démon) |
| set | WORKFLOW CLÉ VALEUR | réglage gardé |
| remove | WORKFLOW CLÉ | réglage retiré |
| reload | WORKFLOW | sans écriture : l'index compare déjà les dates à chaque lecture (research R4) ; ordre journalisé |
| reveal | WORKFLOW | dossier montré dans le Finder |
