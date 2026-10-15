# Implémentation 036

## Cause
Le relevé CG limité aux fenêtres à l’écran perd huit fenêtres encore ouvertes lorsqu’un Space plein écran s’active sur l’écran interne. Le filtre du rail expire après 15 secondes ; le membre peut aussi être retiré après 30 minutes.

## Correction
Un inventaire CG ID/PID distinct confirme uniquement les membres persistants absents du relevé courant. La conservation des membres et la projection du rail l’utilisent. Une observation non tilable, un PID différent et une fermeture confirmée restent prioritaires. Le relevé de placement et l’adoption sont inchangés. Les menus de la base combinée sont raccordés à la même présence.

## Tests
Avant : trois assertions échouent après une heure simulée, sur la conservation du membre et sa carte. Après : 1 490 tests isolés dans 163 suites et 1 557 tests combinés dans 170 suites réussissent. Les variantes contrôlent fermeture AX récente, entrée CG fermée ou incertaine, PID différent ou absent, indisponibilité de l’inventaire, fenêtre exclue, non-adoption et conservation des groupes.

## Livraison
Le socle installé de 264 fichiers a été vérifié. Cinq sources produit et un test modifiés ; 265 empreintes dans le reçu. Le patch isolé se réapplique exactement. Les autres travaux parallèles restent identiques. Les corrections de l’audit 035 ne font pas partie de cette livraison.

Signature stable roadied-cert conservée. Nouveau processus installé : 53642. Quatre contrôles de santé OK. UUID : 3DCADF8B-8F1B-3C30-918F-E039AC922EC6.

## Récupération des données
La référence Outlook 614 avait disparu avant l’installation, mais CG confirmait encore le même ID et PID 69726. Récupération depuis la sauvegarde de l’incident sous le verrou du fichier d’état. Sa destination initiale étant occupée par un nouveau groupe, création d’une stage Outlook séparée, ajoutée en fin de liste. Aucun groupe actuel fusionné.

## Vérification visible
Avant correction : après 22 secondes de plein écran natif réel du témoin, le rail externe ne montre plus que la pile T3. Après installation : ses cartes restent présentes à 22 secondes. Fermeture du témoin et retour au bureau normal vérifiés. Les actions natives ne simulent aucun clic ; aucune position de curseur inventée.

Les captures et données brutes restent hors Git. Le diaporama autonome est versionné dans preuves-corrections/2026-10-15-036-stages-plein-ecran/preuves.html.
