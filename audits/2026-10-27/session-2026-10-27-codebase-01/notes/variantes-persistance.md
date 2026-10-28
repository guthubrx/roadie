# Variantes — lecture puis écriture séparées

Avant correction, le test `Spec093PersistenceSafetyTests` a atteint ses assertions : deux mutations concurrentes de la mémoire du lanceur ne conservaient qu'une clé ; un fichier JSON volontairement illisible était remplacé dans les magasins d'historique, mémoire, abréviations et projets. Le test d'origine et sa sortie sont conservés dans `runs/20261027T052611780366Z/`.

Recherche de variantes : `rg -n -B 4 -A 5 'JSONPersistence\.write(Throwing)?\(' Sources --glob '*.swift'`, puis recherche des séquences `var ... = load()`. Le classement du lanceur présentait la même séquence ; il est corrigé et ajouté au test de fichier illisible. Les appels `writeThrowing` restants écrivent un état complet de santé ou de restauration, sans lecture-modification-écriture au même endroit : ils ne sont pas assimilés à cette course sans preuve supplémentaire.

Correction : les cinq magasins utilisent les transactions exclusives `JSONPersistence.mutate` ou `mutateChecked`. Le verrou couvre la lecture, la modification et l'écriture. Ces transactions refusent aussi de remplacer un état illisible. La mémoire avant correction est conservée dans `notes/original/`.

Après revue, les actions explicites d'effacement de l'historique, d'enregistrement d'abréviation et de sauvegarde ou suppression de projet utilisent `mutateChecked`. Les tests vérifient que ces opérations lèvent une erreur sur fichier illisible. L'écriture automatique des visites et de la mémoire continue à journaliser ses erreurs. L'enregistrement d'un projet reste asynchrone : un accusé de réception immédiat ne constitue pas une confirmation de persistance ; un échec ultérieur émet un événement et une notification locale.
