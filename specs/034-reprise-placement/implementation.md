# Implémentation

## Diagnostic et reproduction

Le cas initial combine une fenêtre CG visible, rattachée au groupe externe, et une
résolution AX indisponible. Deux appels échouent avant de créer une entrée au registre.
Le compteur local atteint deux ; les passes suivantes acceptent un cadre resté sur
l’autre écran. Les voisines ont déjà été réduites.

Le test final échoue sans correctif sur 15 assertions. Il reproduit les cadres
incohérents et l’absence de reprise même après disponibilité, sans activation.

## Correction

Le mainteneur vérifie la lecture AX des fenêtres sans écriture connue, visibles sur
un autre écran que leur groupe. Si une lecture échoue, seul ce groupe attend ; ses
voisines restent en place. Le maintien de sécurité existant reprend la vérification.
Aucune boucle rapide ni nouvelle génération de placement n’est ajoutée.

Lors du retour de disponibilité, les échecs de résolution précédant tout appel AX
ne consomment plus le compteur local. Le registre conserve la limite de deux écritures
AX réelles par fenêtre et par génération. Attente et disponibilité sont journalisées
une seule fois par transition.

Les positions de masquage, les cadres hors de tout écran présent, les épinglages et
le plein écran natif restent dans leurs chemins existants. La suite complète initiale
avait détecté cinq assertions sur des restaurations cachées ; le filtre des positions
visibles a corrigé ce périmètre sans modifier ni assouplir ces tests.

## Validation

Trois scénarios : disponibilité retardée, indisponibilité persistante avec fermeture,
et résolution perdue après une première lecture. Cent passes de sécurité vérifient
l’absence de boucle. L’autre écran continue de placer ses fenêtres.

Suite isolée finale : 1 484 tests réussis dans 162 suites.
Tests ciblés de frontière et restauration : 12 tests réussis, dont les trois cas de
la nouvelle régression. Suite combinée finale : 1 551 tests réussis dans 169 suites. Installation signée et redémarrage vérifiés.

Revue locale : un seul fichier de production modifié, aucun moteur ni dépendance,
aucune modification de configuration, aucun changement des raccourcis ou des groupes.

## Livraison et test sur le Mac

Version combinée installée, UUID 2B510D42-C812-384F-952E-59E17AA95A6C.
Certificat conservé. Ancien PID 34131 ; nouveau PID 15020. Quatre contrôles santé OK.
Les neuf fenêtres communes conservent leurs groupes ; configuration inchangée.
Les 46 fichiers suivis dans le worktree parallèle restent identiques.

L’application de contrôle expose sa fenêtre CG sur l’interne et retarde sa fenêtre
AX de trois secondes. Elle est rattachée à la stage 4 de l’externe, sous la souris.
Trois relevés à 0,42, 1,24 et 2,43 secondes montrent les voisines inchangées.
Un événement d’attente, puis un événement de disponibilité après 3 089 ms ; ensuite
une passe de 98,6 ms place la fenêtre et sa voisine, sans échec. Stabilité à 216 ms.
Après la fermeture automatique, les neuf fenêtres communes retrouvent leurs cadres.

Le premier lanceur de contrôle avait créé deux instances NSApplication ; il a été
corrigé en utilisant le singleton de la sous-classe. Un essai sur le même écran ne
validait pas le scénario croisé. Ces essais locaux ne sont pas comptés comme preuve.
Le contrôle final croisé ci-dessus est celui retenu pour la livraison.

Limite du périmètre : l’attente concerne une fenêtre visible sur un autre écran présent,
sans écriture AX connue. Les réponses de taille déjà enregistrées et les restaurations
cachées gardent leurs mécanismes existants.
