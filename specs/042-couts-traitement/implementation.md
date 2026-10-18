# Journal de validation

## T002 — BSP et recherche
- Parcours de remplacement en une passe, sans rééquilibrage ni changement des ratios.
- Textes préparés par cible, alignés lors de la fusion des lots ; partition stable des résultats.
- Relecture du diff : suppression des recherches récursives répétées et des normalisations par frappe. Aucune dépendance ajoutée. Cache borné à 500 éléments.
- Tests ciblés BSPTree et TargetSearchModel exécutés avec deux tâches de compilation, sans benchmark. Équivalence sur chaîne de 80 feuilles, suppression, cible absente et lots avec identifiants répétés.
- Limite : pas de mesure de gain temporel sur la machine chargée.

## T003 — Secours AX
- Cache lié à l’index du lot, y compris les lectures indisponibles. Réinitialisé à la réénumération.
- Cadre actualisé par la relecture après écriture, supprimé si l’écriture échoue. Titres lus par l’interface injectable existante.
- 17 tests AX passent. Quatre cibles absentes et trois candidats : trois lectures de cadre et trois de titre, aucune écriture. Test distinct : un cadre modifié ne peut plus résoudre une autre cible par son ancienne position.
- Relecture : unicité, candidats réservés et quarantaine conservés. O(k·m) comparaisons en mémoire restent possibles ; les échanges AX sont bornés à O(m+k). Aucun cache permanent ajouté.

## T004 — Acquisition des lecteurs
- Acquisition AX asynchrone, partagée par fichier d’état. Écrans et réconciliation restent sur MainActor. Aucun allongement du cache.
- Contrôles de révision, configuration, fichier et écrans avant réconciliation. Les acquisitions invalidées sont abandonnées ; un relevé récent du producteur reste prioritaire.
- Inventaire CG conservé dans le relevé. Les lecteurs ne le redemandent plus.
- 47 tests dans cinq suites réussis : lecteurs concurrents, aucun scan sur le fil principal, une seule lecture d’inventaire, invalidation et mutation d’état pendant le relevé, producteur partagé, bordure et présence hors Space.
- Relecture : un seul traitement en vol par contrôleur, annulation au stop du rail, geste et déplacement de souris recontrôlés après attente. Pas de nouveau verrou couvrant les appels AX.
- Limite explicite : le tiler et les commandes restent synchrones (ADR 013). Une acquisition de lecteur déjà démarrée peut coïncider avec un producteur ; son résultat devenu ancien est écarté.

## T005 — Préparation et invalidation du rail
- Cache du contenu par écran ; comparaison des entrées et contrôle de la visibilité à chaque cycle, y compris expiration des membres absents.
- Révisions de miniatures par fenêtre et signatures de rendu par écran. Les panneaux inchangés restent en place. Les réglages globaux invalident tous les écrans.
- 16 tests dans quatre suites réussis : réutilisation du contenu, expiration à 15 secondes, renommage, nettoyage, écran unique changé et retrait d’écran.
- Relecture : budgets de captures et protections DRM conservés. Pas d’arrêt des contrôles de fraîcheur ; les comparaisons linéaires et l’entretien des captures restent nécessaires.

## T006 — Réordonnancement
- Seuils, rangs et tolérance préparés au début du geste. Les mouvements comparent les seuils sans reconstruire les tableaux.
- Copies conservées pendant tout le geste ; seules leur position et leur légende changent. Les originaux restent les cibles des clics.
- 19 tests dans trois suites réussis, dont les 12 combinaisons de modes et d’alignements. Les identités des copies sont identiques après changement de destination. Le retour du test franchit la zone d’hystérésis, comme un geste réel.
- Relecture : sortie, dépôt et rendu effacent le cache du geste ; noms personnalisés, stages cachées, opacité et ordre conservés. Aucune lecture AX ni nouvelle capture ajoutée.

## Revue — protections complémentaires
- Risque confirmé de publication AX périmée : générations vérifiées dans les deux caches partagés. Un scan récent, une invalidation ou une réénumération d’écrivain empêche un ancien remplacement.
- Contexte NSWorkspace capturé sur MainActor après l’inventaire, lecture AX du focus hors fil principal. NSRunningApplication est documenté comme thread-safe.
- Horodatage à la fin effective de l’acquisition, pas au réveil du lecteur. Une acquisition devenue trop ancienne dans la file principale est abandonnée.
- 61 tests dans sept suites passent. Nouveaux scénarios : cache ancien après scan récent, invalidation, réénumération ; capture du contexte focus sur MainActor et lecture AX hors MainActor.
- Relecture ciblée : garder la mutualisation plutôt que lancer des scans supplémentaires après un délai. Les limites AX existantes restent actives.
