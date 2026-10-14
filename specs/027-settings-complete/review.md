# Revue — session 027

## Tour 1

- Élevé : le signal local ne traverse pas les processus du mode modulaire.
  Corrigé : publication et réception distribuées, doublons idempotents.
  Un vrai processus enfant vérifie le relais, le rechargement et les noms de stages.
- Moyen : le changement de géométrie retirait la grâce du redimensionnement manuel.
  Corrigé : délai conservé et précision en attente pendant les 0,35 s de grâce.
- Affichage : une collection validée restait marquée comme brouillon.
  Corrigé ; tests de suivi externe et de conservation des brouillons ajoutés.
- Risque de coût par frappe : mesure sur une copie du fichier réel, environ 61 ms
  de travail synchrone par valeur valide. Voir performance.md pour les limites.
- Les contrôles de validation, remplacement atomique, chemins, familles absentes
  et avertissement sur les hooks n'ont pas révélé de défaut bloquant.

## Tour 2

- Le relais inter-processus et ses protections ne présentent plus de blocage relevé.
- Moyen : un texte scalaire déjà enregistré pouvait écraser une modification
  externe lors de la perte du focus. Le modèle distingue maintenant ce texte
  des vrais brouillons. Il relit sans réécrire lors de la sortie du champ.
- Précision : une première écriture ignorée pouvait être classée comme appliquée
  dans la tolérance de 2 points. Le test de diagnostic a confirmé une seule tentative
  et le cadre ancien. La correction prévoit une vérification réelle et une reprise
  bornée, sans modifier la tolérance AX ordinaire ni créer de boucle.

Les tests de saisie externe et de reprise bornée passent dans la suite complète.

## Tour 3

- Moyen : une commande filtrée avant écriture pouvait consommer la précision.
  Corrigé : le suivi par fenêtre distingue une tentative réelle d'une demande
  bloquée par une garde ou un budget. La demande attend sans boucle d'écriture.
  Les tests couvrent le délai après échec et un budget déjà consommé.
- Bas : une reprise d'un scope devenu inactif pouvait effacer son intent.
  Corrigé : le nettoyage attend que le scope soit actif et autorisé. Le test
  A→B→A vérifie la conservation de l'intent et la reprise bornée.
- La garde de génération est conservée. Une modification de géométrie crée une
  nouvelle génération ; le test de budget protège aussi le cas d'une garde active.
- Les couleurs seules rafraîchissent les bordures sans retuilage. Le coût
  synchrone final reste proche de 61 ms en médiane ; voir performance.md.

## Vérifications complémentaires

- Les règles sont validées avec les règles générées, selon le chemin logique du
  fichier actif. Expressions invalides et conflits sont rejetés avant écriture.
- Modifier une autre valeur conserve les critères déjà vides dans une règle.
- Les actions de règle `layout` et `gap_override`, déjà sans effet géométrique,
  sont signalées dans les éditeurs et la documentation.
- La suite finale passe : **1 439 tests, 154 suites, 6,601 s**.

## Tour 4

La lecture confirme les correctifs, les tests, la validation des règles et la
conservation des critères vides. Aucun défaut bloquant n'est prouvé par la revue.

Le scénario d'échéance passée est reproduit avant correction : les quatre
variantes BSP/arbre persistant × stage vide/zoomé échouent. La correction retire
ces scopes des reprises exécutables et garde leur demande pour le retour.
Le zoom réservant le rail conserve sa mise à jour. Les tests vérifient une seconde
sans réveil répété, puis le retour et la limite de deux écritures.

Les 12 tests runtime ciblés passent. La suite finale passe : **1 440 tests,
154 suites, 6,943 s**. Aucun constat de revue ne reste sans réponse ou test.

La version finale est installée et redémarrée, PID 47508, avec quatre contrôles de
santé OK. Elle inclut la correction de transition du quatrième tour.
Validation utilisateur : « Oui, tout fonctionne » pour les trois parcours demandés.
