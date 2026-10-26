# Recherche 087

## R1 Analyseur du calcul
`NSExpression(format:)` lève une exception Objective-C sur une saisie invalide (`12*`), que Swift ne
peut pas rattraper : le démon planterait à chaque frappe d'un calcul en cours. Décision : petit
analyseur à descente récursive (expression → terme → facteur → puissance → unaire → primaire),
`Double`, sans allocation de nœuds. Résultat non fini (division par zéro, `ln(-1)`) : pas de ligne.
Alternative écartée : JavaScriptCore (dépendance lourde, sémantique JS de `^`).

## R2 Nombres
Entrée : `,` et `.` acceptés comme séparateur décimal (aucun séparateur de milliers en entrée, pas
de fonction à deux arguments : pas d'ambiguïté). Sortie : `NumberFormatter` en langue courante,
`maximumSignificantDigits = 12`, sans groupement ; `-0` rendu `0`. Copie = texte affiché (collable
dans un tableur français).

## R3 `/` : commande ou chemin
Commandes et alias du mode commande (`SlashCommandCatalog.commands`) : move, swap, resize, full,
max, stage/s, screen, send, desktop/d, layout, balance, split, bm/b, grid, letters, doctor, heal,
reload, restart, settings, set. Éléments de `/` : Applications, Library, System, Users, Volumes,
bin, cores, dev, etc, opt, private, sbin, tmp, usr, var. Collisions par début : `/s` (stage…,
System, sbin), `/d` (desktop, dev), `/b` (bm, bin), `/l` (letters, Library) → la commande garde la
priorité tant qu'un second `/` n'est pas tapé ; `/Us`, `/App`, `/Vol`, `/tmp`, `/opt` → chemin.
`/` seul → commande.

## R4 Lecture d'un dossier
`FileManager.contentsOfDirectory(at:includingPropertiesForKeys: [.isDirectoryKey])` hors du fil
principal (file `userInitiated`), numéro de génération pour ignorer une réponse périmée. Coût
mesuré attendu : quelques millisecondes pour 200 éléments ; un dossier réseau lent n'arrête que sa
propre réponse. Plafond de 5 000 éléments parcourus, 200 gardés après filtrage.

## R5 Tab
Dans la barre, Tab arrive en `.next` avec `navigationSource == .tab` et → en `.actions`. En mode
chemin, Tab remplace la saisie (et le champ natif) ; → garde l'entrée dans les verbes du fichier.
