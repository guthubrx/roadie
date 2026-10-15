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
la nouvelle régression. Suite combinée finale : 1 551 tests réussis dans 169 suites. Installation et redémarrage en cours.

Revue locale : un seul fichier de production modifié, aucun moteur ni dépendance,
aucune modification de configuration, aucun changement des raccourcis ou des groupes.
