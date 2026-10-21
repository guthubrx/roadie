# Session 053 - Dépôt fidèle dans le rail

Le 21 octobre, l'utilisateur signale un dépôt à une mauvaise position dans le rail,
entre écrans puis sur le même écran. Il confirme que son point de dépôt prévaut :
haut, interstice et bas. Le tri automatique occupées/vides est donc retiré.

Les cartes et leurs cibles restent figées pendant le geste. Un emplacement libre
porte l'identifiant de la carte suivante ou la fin de liste ; cette intention est
résolue dans la transaction d'affectation. Une place occupée/renommée ou une ancre
disparue fait échouer sans mutation. Aucun repli vers le rail d'un autre écran.
Le repère « Nouvelle stage » et les coordonnées journalisées rendent la cible
vérifiable. Aucun nouveau paquet ni relevé AX par mouvement.

Reproduction avant/après : neuf assertions initiales, puis huit avec changement
concurrent du store. 95 tests ciblés et 1 758 tests / 210 suites réussis. Revue
indépendante en lecture seule traitée ; diff et tests vérifiés par le responsable.
Capture et CUA restent indisponibles, aucun geste utilisateur simulé à l'aveugle.
Reçu : specs/053-depot-rail/validation.md.

Release installée, UUID 458CF5AB-3B7E-3F5A-9B09-656E7B0FF331, PID 81466,
cinq contrôles santé OK. Configuration, certificat et 303 empreintes de fichiers
Sources/Tests inchangés. Essai utilisateur des trois positions proposé.
Correction cffaf5c6 fusionnée et poussée sur main. Branche et compilation retirées ;
worktree de la conversation conservé détaché, diagnostics hors Git.

## Complément après retour utilisateur

Plusieurs dépôts fonctionnent ; un trou visuel correspond à « Perso » devenue vide.
Le repère d'une stage vide ne disparaît plus avec les libellés : contour discret,
nom/numéro et mention « Vide ». Stages anonymes vides toujours masquées.
Rendu/clics testés sur carte courte ou longue, numéro futur du fantôme conservé.
1 760 tests / 210 suites réussis, revue indépendante traitée, santé 5/5.
UUID DAF8ED16-F7D6-30AE-A800-A338ACEF5027, PID 27951, signature/config inchangées.
Capture utilisateur du symptôme disponible ; résultat réel non capturé, CUA indisponible.
