# Mesures — session 024

## Conditions

- Même machine, fixtures Swift déterministes, 50/100/200/400 fenêtres.
- Compilation debug, chaîne d'outils Xcode utilisée par `scripts/test`, quatre jobs de build.
- Mesures dans un seul test sérialisé. Une exécution de chauffe puis cinq échantillons ;
  médiane du temps par opération. Aucune assertion de durée dépendante de la machine.
- PERF-010 : appels historiques répétés à `assignWindow` comparés au remplissage groupé.
- PERF-011 : collecte historique des scopes comparée à la collecte dédupliquée ;
  les deux appellent le vrai `hasValidLayoutIntent` sur le même intent validé.
- PERF-012 : le vrai `reconcileWindowIDs` est exécuté avec le fichier StageStore du
  commit `d2e7daf0`, puis avec sa version corrigée. Les autres sources et les fixtures
  restent identiques. La référence algorithmique des tests n'est pas utilisée pour
  calculer le gain de cette correction.

Le runner de référence conserve le fichier corrigé, compile la version précédente,
exécute le microbenchmark puis restaure le fichier corrigé dans un bloc `finally`.
Aucun daemon ni fenêtre réelle n'est utilisé.

## Limites

Ces microbenchmarks isolent les chemins corrigés. Ils ne mesurent ni la latence
de l'interface, ni un tick complet, ni la consommation mémoire. Les temps dépendent
de la compilation et de la charge de la machine. Les rapports publieront les médianes
et les limites, sans garantir une accélération identique sur toutes les données.

Le rapprochement indexé fini a un pire cas linéaire par requête, donc quadratique
global, auquel s'ajoute la construction O(Σ g log² g). Le repli historique pour
géométrie non finie garde son tri O(g log g) par requête : O(M × W log W) au pire.
Les boîtes géométriques et les deux meilleurs scores permettent d'élaguer les groupes
ambigus testés. Les candidats déjà adoptés sont retirés avant tout index.
Les index sans ancien membre admissible ne sont pas construits.

## Résultats

| Scénario, 400 fenêtres | Avant (ms) | Après (ms) | Rapport |
|---|---:|---:|---:|
| Appartenances du snapshot | 15,399 | 0,443 | ×34,7 |
| Validation des scopes | 6 622,379 | 17,085 | ×387,6 |
| Rapprochement homonyme ambigu | 117,742 | 16,076 | ×7,3 |
| Candidats déjà adoptés | 32,862 | 2,323 | ×14,1 |
| Aucun ancien membre | 1,976 | 1,918 | Comparable ; aucun gain revendiqué |

Les tailles 50, 100, 200 et 400 et les mesures brutes se trouvent dans
`measurements/comparison.json`, `before.json` et `after.json`.
La revue indépendante valide les mesures et la clôture ciblée des trois HIGH.
