# Variantes

## F1 (sauvegarde puis remise du presse-papiers)
Recherche : `rg -n "changeCount|clearContents\(\)|string\(forType: .string\)" Sources/RoadieDaemon`.
11 écritures du presse-papiers : copies voulues par l'utilisateur (⌘C de la barre, verbes Copier,
Copy to Clipboard d'un workflow, chemins d'un lot, abréviation) ; une seule sauvegarde-remise :
`selectedText` (corrigée). Aucune autre variante.

## F2 (processus enfants du démon)
Recherche : `rg -n "Process\(\)|posix_spawn" Sources/RoadieDaemon`. Enfants à commande fixe
(osascript des navigateurs, qlmanage, say, shortcuts, open, curl et ditto de `tasks update`, mdfind
du filtre de fichiers) ou scripts de workflows installés par l'utilisateur. Seuls ces derniers
exécutent du code tiers : couverts par F2.
