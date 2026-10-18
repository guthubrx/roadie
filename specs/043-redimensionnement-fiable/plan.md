# Plan technique

Swift 6, AppKit, Swift Testing ; réutiliser BSPTree, SnapshotService, WindowCommandService/StageStore et les mécanismes de geste existants. Aucun nouvel accès AX dans les événements mouseDragged : calculer la cible sur le modèle, passer par le point d’écriture et les budgets existants.

## Répartition T3 (même worktree, fichiers exclusifs)
1. Agent poignées : géométrie des séparations et mutation de ratio BSP, nouveau SplitResizeController AppKit et tests dédiés. Propriété BSPTree.swift et nouveaux fichiers SplitResize*/BSPDivider*. Le parent possède le raccordement au runtime et le service de persistance/application ; fournir un contrat simple de callbacks de début/déplacement/fin et la géométrie en coordonnées AX.
2. Agent historique : WrittenFrameRegistry.swift, AXWindowEventObserver.swift et leurs tests ; aucun fichier du daemon. Détecter l’interaction souris à la frontière système de façon injectable. Fournir une API compatible aux appelants actuels.
3. Agent refus : LayoutMaintainer.swift et nouveaux tests Spec043Refusal* uniquement. Prouver puis corriger l’écrasement d’une intention récente et/ou la répétition des refus ; ne pas modifier le registre AX possédé par l’autre agent. Décrire le cas démontré et la correction.
Parent : artefacts, configuration/catalogue/README, service de séparation et raccordement runtime, tests d’intégration, build, installation, preuves et livraison Git. Aucun agent ne commit, ne pousse ou n’installe. Un seul build/test Swift à la fois par parent ; les agents rendent leurs tests à lancer.

## Contrats et garanties
Un identifiant de séparation = scope + chemin de branches BSP. Le modèle fournit rectangle de prise, orientation et ratio ; le callback reçoit une position AX absolue. Les résultats d’un scope obsolète sont rejetés. Réutiliser les ratios bornés et les minimums. La persistance est transactionnelle ; les événements et générations suivent les commandes existantes. L’historique a une borne stricte (32), donc coût borné par événement, sans recherche globale.

## Validation
Tests Swift ciblés par périmètre, puis suite complète et scripts existants. Build Release signé avec certificat conservé. Essais réels sur fenêtres dédiées si l’accès au bureau existe, sans perturber les fenêtres utilisateur ; produire les preuves selon le skill. Si le bureau est inaccessible, préciser la limite et installer le résultat concret pour validation. Pas de benchmark.

