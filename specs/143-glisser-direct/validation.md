# Validation en cours — session 143

Base : 415f6804. Nouvelle option active par défaut ; aucune release demandée.

## Vérifications logicielles
8 nouveaux tests comportementaux réussis, puis 28 tests ciblés (réglages, nouveau runtime et dépôts historiques) réussis. Suite finale : **2 383 tests / 356 suites réussis en 61,135 s**. **28 tests de scripts réussis**.

Première suite : trois attentes de compte de réglages à actualiser et test historique synchrone devenu asynchrone. L'adaptation a ensuite exposé une mutation concurrente du double PowerUserWriter ; dictionnaires et snapshot du double protégés par verrou. Le cas de destruction périmée a révélé la différence réelle entre arbre avant acquisition [75411,614,140] et après [75411,140]. La garde utilise maintenant l'état après acquisition, tandis que la visée conserve le contexte original. Le dépôt existant rétracte cette destruction comme avant. Les deux variantes historiques passent ; aucun diagnostic provisoire conservé dans le code.

## Parcours natif avant
Trois fenêtres AppKit fictives, stage temporaire validation143, source A tirée par son titre via l'API officielle BetterTouchTool. Clic effectivement observé dans AppKit. Pendant l'appui, A passe de (3509,303,1837,1052) à (2670,-245,1837,1052), B et C restent inchangées. Captures sans document privé visualisées. Premier déplacement BTT sans durée n'avait pas atteint la cible : geste refusé avant appui ; la durée explicite et la position réelle sont désormais vérifiées.

Diaporama partiel dans preuves-corrections/2026-10-31-143-glisser-direct/preuves.html. Originaux et manifestes hors Git. Après installation, option et annulation restent à vérifier. Aucune latence native revendiquée.

## Self-review
Moteur de visée figé conservé, pas d'autre calcul de dépôt ni writer. Aucune persistance dans l'aperçu. Coalescence et révocation communes à la session 142. Clôture bornée, pas de remise à zéro visible au dépôt. Complexité ajoutée linéaire par cible ; minuteur temporaire de contrôle du contexte uniquement pendant le geste. Abstraction justifiée : même propriétaire pour titres et rail, aucune dépendance.
