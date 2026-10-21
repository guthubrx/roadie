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
