# Recherche : Parking et restauration des stages d'écrans

## Décision : conserver les scopes absents au lieu de les migrer implicitement

**Décision** : `StateAudit` et `SnapshotService` ne doivent plus supprimer ou fusionner les scopes dont le display n'est pas actuellement visible. Ces scopes deviennent la source d'origine pour le parking et la restauration.

**Rationale** : le bug observé vient précisément d'une correction trop agressive : Roadie voyait un écran absent, choisissait un fallback, puis mélangeait ou réassignait des fenêtres sans savoir si l'écran allait revenir. Un scope absent n'est pas forcément corrompu ; c'est souvent un écran temporairement débranché.

**Alternatives considérées** :

- Supprimer les scopes stale dans `heal` : rejeté, destructif.
- Migrer immédiatement vers l'écran restant : rejeté, perd l'origine.
- Garder les scopes absents avec un niveau d'audit `warn` : retenu, car non destructif et observable.

## Décision : créer un état explicite de stage rapatriée

**Décision** : chaque stage rapatriée porte une origine explicite : écran logique d'origine, display ID précédent, desktop, position, stage ID original, date de parking et écran hôte courant.

**Rationale** : une stage rapatriée doit être utilisable comme une stage normale tout en restant restaurable. Il faut donc séparer son identité fonctionnelle courante de son origine historique.

**Alternatives considérées** :

- Utiliser seulement le nom de stage : rejeté, collisions possibles et pas fiable.
- Utiliser seulement l'ancien `DisplayID` : rejeté, macOS peut changer l'identifiant.
- Ajouter un wrapper de métadonnées dans `PersistentStage` : retenu, compatible avec l'état existant et les opérations de stage.

## Décision : reconnaître les écrans avec une empreinte conservatrice

**Décision** : introduire une empreinte d'écran logique construite depuis les champs disponibles : nom, taille, visible frame, position relative, index, indicateur main, et dernier display ID connu. La restauration automatique exige un match clair.

**Rationale** : le rebranchement peut changer l'identifiant système. Il faut reconnaître le même écran sans prendre le risque de déplacer des stages vers un autre écran similaire.

**Alternatives considérées** :

- Match strict sur `DisplayID` : trop fragile.
- Match permissif nom uniquement : trop risqué avec deux écrans identiques.
- Scoring conservateur multi-champs : retenu. Si le score est ambigu, Roadie ne restaure pas automatiquement.

## Décision : débouncer les changements d'écran côté daemon

**Décision** : `roadied` attend une période de stabilisation avant de lancer parking/restauration, et suspend les ticks de maintenance pendant cette fenêtre.

**Rationale** : macOS peut émettre plusieurs notifications pendant que les frames, visible frames et IDs se stabilisent. Agir à chaque notification produit des layouts intermédiaires, des oscillations et des fenêtres déplacées au mauvais endroit.

**Alternatives considérées** :

- Réagir immédiatement : rejeté, cause visible de clignotements et d'états faux.
- Attendre un délai fixe sans annuler le précédent : rejeté, plusieurs transitions peuvent quand même s'empiler.
- Debounce annulable avec dernier état stable : retenu.

## Décision : rapatrier les stages non vides comme stages distinctes

**Décision** : chaque stage non vide d'un écran disparu devient une stage distincte sur l'écran hôte choisi. Les stages vides sont mémorisées mais ne doivent pas forcément apparaître dans le navrail.

**Rationale** : l'utilisateur ne veut pas retrouver toutes les fenêtres dans une seule stage. La granularité utile est la stage, pas l'écran complet.

**Alternatives considérées** :

- Une seule stage "Écran débranché" : rejeté, trop de mélange.
- Recréer toutes les stages, vides incluses, dans le navrail : rejeté, clutter inutile.
- Rapatrier les non vides et conserver les vides en métadonnées : retenu.

## Décision : restaurer l'état courant, pas une copie ancienne

**Décision** : pendant l'absence de l'écran, la stage rapatriée reste la source d'autorité. Au rebranchement, Roadie déplace cette stage courante vers l'écran restauré.

**Rationale** : l'utilisateur peut renommer, réordonner, fermer, ajouter ou déplacer des fenêtres pendant que l'écran est absent. Restaurer une ancienne copie ferait perdre son travail.

**Alternatives considérées** :

- Snapshot au moment du débranchement puis restauration de ce snapshot : rejeté, perte de modifications.
- État courant marqué par origine : retenu.

## Décision : exposer un diagnostic lisible

**Décision** : ajouter des événements et/ou une sortie CLI indiquant les stages natives, rapatriées, restaurées, ambiguës et les raisons de no-op.

**Rationale** : les bugs de topologie sont difficiles à comprendre visuellement. Il faut pouvoir répondre vite à "où sont mes stages ?" sans lire `stages.json` à la main.

**Alternatives considérées** :

- Logs internes uniquement : insuffisant pour support utilisateur.
- UI complète dédiée : hors scope.
- Événements + formatters CLI : retenu.
