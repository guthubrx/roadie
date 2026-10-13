# Session 019 — Maximisation en laissant la place au navrail

Date : 2026-10-12. Branche : 019-navrail-maximization.
Statut de l'implémentation : Implémentée, 22/22 tâches cochées.

## Résultat

Commande toggle maximize et action de menu ciblée. Réservation du panneau visible ; plein cadre utile lorsque le rail est replié en auto-hide. Pin et survol redimensionnent la fenêtre sans quitter le zoom ; restauration par arbre ou placements sauvegardés ; compatibilité des anciens intents ; plans et maintien recalculent le cadre. Protection contre les refus et le focus natif. Capture des nouvelles voisines et reprise après fermeture de la cible.

## Vérification

846 tests dans 91 suites passent après les corrections de placement. La version précédente passait 827 tests dans 90 suites après intégration de la session 018. La correction du 2026-10-13 couvre le repli, pin, survol, resize/overlay et les quatre moteurs. L’audit initial portait sur 820 tests dans 89 suites. Audit v14 : A ; quatre défauts de fiabilité trouvés, corrigés et testés. Observation non bloquante : la bascule commune dépasse 50 lignes ; pas de refactor cosmétique ni de couche supplémentaire. Convergence manuelle exigence par exigence ; livraison Git/disque/runtime et nettoyage contrôlés séparément après intégration.

## Réutilisation et charge future

Aucun nouveau fichier de production, aucun nouveau service/store/type partagé, aucune dépendance. Deux champs optionnels dans LayoutIntent ; calcul de cadre réservé et restauration communs aux chemins existants. Masquage, stockage atomique, mémoire des refus et plans par scope réutilisés. Les tests initiaux ont révélé un accès privé ; les vérifications ciblées ont révélé et confirmé les pertes de métadonnées avant correction.


## Correction de placement — 2026-10-13

Les déplacements automatiques vers une stage inactive et leurs échos ne suppriment plus l’intent comme un resize. Les vrais gestes restent actifs et les signaux d’adoption multiécran restent séparés. Une activation confirmée de voisine visible sort du zoom avant masque ; un repli mémorisé AX=nil ne le fait pas. La lecture du focus existante est partagée et le repli de centrage reste réservé aux fenêtres réellement cachées.

Préflight AXFullScreen frais avant écriture ; native=true et cannotComplete n’atteignent pas les écritures ni leur budget. Diagnostics du registre existant par phase, demande et génération, sans titres/applications. La date optionnelle shutdownRequestedAt distingue arrêt demandé et restauration complète ; reprises failed>0 conservées, natifs préservés et IDs des refus signalés.

Reproductions rouges sur le code initial, puis 60 tests ciblés dans 7 suites et 846 tests complets dans 91 suites verts. Deux angles de focus révélés par les tests corrigés après observation des données de fixtures (centrage visible et focus mémorisé). Identité/cause exacte des refus AX historiques non démontrée ; aucune promesse de forcer une application qui refuse les attributs.


Convergence sur plusieurs passes : le test AX=nil/mémorisé a révélé une sortie différée au deuxième passage. Garde de focus réel étendue à toute restauration de voisine d’un zoom, visible ou cachée. CmdTab caché détecté au poll garde son effet avec un ID réel ; restauration cachée sans zoom conservée. Trois passages stables vérifiés, puis suite 846/91 verte. T022 ajoutée et exécutée ; convergence au deuxième passage final.
