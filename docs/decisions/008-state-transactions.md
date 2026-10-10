# ADR-008 : Transactions sur les fichiers d'état et fichier illisible

## Statut

Accepté. Mis en oeuvre par la SPEC-016 (décisions R1 et R2 de `specs/016-roadie-stabilization/research.md`).

## Contexte

Roadie garde l'état des stages, des intentions de layout et du rail dans des fichiers JSON. Plusieurs processus et plusieurs fils d'exécution les lisent et les écrivent. Le schéma était : lire le fichier, modifier en mémoire, réécrire le fichier. Le rename atomique garantissait un fichier complet, mais pas l'absence de mises à jour perdues. Deux écrivains pouvaient lire le même état, puis le deuxième écrasait le travail du premier.

Un fichier JSON illisible était aussi traité comme un fichier absent. Roadie repartait alors d'un état vide et le réécrivait. Les stages de l'utilisateur disparaissaient sans trace.

## Décision

1. **Transaction sous verrou.** `JSONPersistence` fournit `mutate(url:type:default:_:)`. Cette primitive prend le verrou exclusif existant (`FileLock`, fichier `.lock`) pendant tout le cycle lecture, modification, écriture. `StageStore`, `LayoutIntentStore` et `RailRuntimeStateStore` exposent `mutate { inout state in ... }`.
2. **Pas de réécriture inutile.** L'écriture compare les octets encodés au fichier existant. S'ils sont identiques, elle ne réécrit pas.
3. **Lectures sans verrou.** Une lecture simple n'attend pas le verrou. Le rename atomique garantit un fichier complet. Cela évite la famine déjà observée avec un verrou partagé en lecture.
4. **Snapshot hors verrou.** `SnapshotService.snapshot()` énumère les fenêtres par Accessibility sans tenir le verrou. Il applique ensuite la réconciliation dans `mutate`, sur l'état relu sous verrou. La réconciliation est une fonction pure de (état, fenêtres vivantes) : la recalculer sous verrou est correct et rapide.
5. **Fichier illisible.** `JSONPersistence.loadResult` distingue `.missing`, `.loaded` et `.corrupt`. Pour `.corrupt`, Roadie copie le fichier en `<nom>.corrupt-<horodatage>`, signale l'erreur sur stderr et par l'événement `state.load_failed`, puis refuse d'écrire jusqu'à un chargement réussi.

## Conséquences positives

- Les mises à jour perdues entre le daemon et ses commandes disparaissent sur les chemins chauds (snapshot, stages, intentions).
- Un fichier corrompu n'efface plus l'état de l'utilisateur : une copie reste disponible pour l'analyse ou la reprise.
- Pas de nouvelle dépendance et pas de migration de format.

## Conséquences négatives

- Les écritures sur ces fichiers passent par un verrou : un écrivain lent bloque les autres brièvement.
- Les chemins qui appellent encore `.save(` directement ne profitent pas de la garantie. Ils sont à migrer vers `mutate` au fil des modifications.
- Le mode « écriture refusée » après un fichier corrompu demande une action de l'utilisateur pour reprendre.

## Alternatives rejetées

- Verrou partagé en lecture : famine déjà observée.
- Base SQLite : nouvelle dépendance et migration lourde.
- Numéro de version avec réessai : plus complexe, sans gain réel ici.
- Repartir d'un état vide en cas de fichier illisible : c'est le comportement qui perdait les données.

## Garde-fous

- Ne jamais tenir le verrou pendant une opération Accessibility ou réseau.
- Ne jamais écrire un état dérivé d'un fichier `.corrupt` avant un chargement réussi.
