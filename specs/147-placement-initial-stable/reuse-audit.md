# Réutilisation147 — PASS

Propriétaires existants : FrameTransitionRuntime, SnapshotService.apply et AXWindowFrameWriter.write. WrittenFrameRegistry reste unique et son critère146 n’est pas remplacé : les données ne montrent pas de retour prématuré à l’animation sur la série reproduite. Aucun dictionnaire, service, observateur, minuteur ou paquet nouveau.

Réutiliser ApplyCommand et WindowFrameUpdate pour porter le seul indicateur d’ordre position/taille à travers le dispatcher existant. Valeur par défautfalse et décodage ancien compatible. Le runtime marque les commandes de première disposition ; l’écriture directe sans runtime tient aussi compte des IDs initiaux. Le writer garde ses budgets, génération, refus et phases historiques et préfixe une position uniquement dans ce cas.

Tests : étendre SpyAXFrameIO pour constater l’emplacement au moment d’un resize, et Drag143Backend pour observer les métadonnées du lot. Ces deux doublures existent ; pas de nouvelle infrastructure de test. La nouvelle suite147 réutilise la fixture143. Les fichiers de preuves/specs sont les artefacts attendus du processus.
