# Livraison145 — vraie destination entre écrans

Demande conservée : afficher la vraie fenêtre et son contenu remis en page à sa destination pendant l’appui, y compris vers l’autre écran. Aucun repli de principe lié à l’écran. Réglages et geste existants conservés. Le cadrage a distingué cadre AX correct et surface effectivement visible.

Pipeline : synchronisation/cadrage et SpecKit repris ; plan, recherche comparative et reuse-audit PASS ; Analyze manuel, implémentation, Converge CONVERGED en un passage, auditV15 passé, intégration/push, activation et nettoyage. Pas de release GitHub nouvelle. Aucun service/dépendance/timer nouveau ; cinq propriétaires étendus et marqueur local de fin native, dispatcher et persistance repris.

Code : edd99a41b228ad35f41079dddc5860401a6c1441. Base90703f0962c66952d4beaee04bf7b0ed0be72f41. Branche session-145-apercu-entre-ecrans intégrée fast-forward dans main. Push origin/main vers https://github.com/guthubrx/roadie.git ; ls-remote a confirmé le même SHA. Le reçu de clôture sera un commit documentaire distinct. Aucun trailer ni changement d’identitéGit.

Disque et runtime : build release signé installé avec la procédure existante. UUID833B2A78-2083-37FB-9355-4F14B488010F identique au build testé, certificat78a75e8032f190a20072eb91cc2919aac344ef78 inchangé, PID85334, santé5/5. Les519fichiers Swift Sources/Tests de main ont les mêmes empreintes que le checkout construit. Configuration utilisateur identique à la sauvegarde avant installation. Aucun gain CPU/GPU ou de latence physique affirmé.

Tests :64ciblés/10suites,2420tests/362suites en69,287s,28tests de scripts réussis. Parking : assertion rouge avant garde, verte après. Huit parcours natifs réussis sur AppKit/Chrome : deux sens, annulation, dépôt et maintien immobile2s ; nouvel essai après code final. Captures de région vérifiées, contenu réel et reflow. Les deux fenêtres adoptées involontairement par l’ancien masque animé ont été remises dans leur scope exact ; stables au parking après second redémarrage. Aucune application/document utilisateur fermé.

Limites : premier essai intégré sans contexte en échec, conservé ; un essai final refusé avant clic car cadres pas encore stables, puis succès. Le bouton de fermeture de fenêtre Chrome n’a pas été rejoué ; onglet+ etX, titre/double clic et filtres de qualification vérifiés comme détaillé dans validation.md. Toutes les applications/combinaisons d’écrans ne sont pas certifiées. Revue contradictoire demandée deux fois à Bridget, refus routing_candidate_unavailable : aucun agent d’autre fournisseur joignable, aucun verdict inventé. Auto-relecture locale déclarée non indépendante.

Audit : session145, quatorze contrôles dont treize applicables, pass/release_blocked=false avant intégration. Semgrep, fichiersGitleaks sur copie SHA hors .worktrees, historique borné après v0.4.0, OSV du verrou et scripts exécutés avec runner. Les douze premiers signaux d’historique étaient les empreintes du précédent audit, recalculées sur leurs commits et réfutées. Les notes de qualité sont distinctes de la gate et restent limitées par les mesures/revue absentes. Une clôture figée du reçu suit ; aucun changement de moteur ou règle.

Preuves : diaporama vérifié,10étapes/3clics natifs/8images uniques,453087octets ; lecture/pause, suivant et dernière étape contrôlés. Fichier autonome :
/Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/025-settings-readability/preuves-corrections/2026-10-31-145-apercu-entre-ecrans/preuves.html
Bruts, manifestes, logs et rollback conservés avec empreintes dans :
/Users/moi/.local/state/roadies/validation/2026-10-31-145

Nettoyage : fixture, probe et pilote propres arrêtés ; enregistrements LaunchServices temporaires retirés, Roadie installé réenregistré. Deux stages145 supprimées par API après reconnaissance des fermetures. Stage144 occupée par une fenêtre étrangère conservée. Branche144 intégrée/poussée supprimée sans force. Worktree et branche145 attachés au fil conservés ; analyses préexistantes hors périmètre préservées. Caches de compilation du worktree retirables par commande projet après clôture ; rollback et preuves conservés.

ETA :60–120min annoncées initialement, recalibrées à30–60min restantes vers15h58, fin visée17h. Début vers14h30 ; activation et intégration vérifiées vers16h15, soit environ105min (+17% au milieu de fourchette initiale90min, dans la borne120min). Le diagnostic du rattachement de surface et la correction de masquage expliquent l’essentiel de la durée. L’heure précise de clôture figure dans la note finale d’audit.

Statut implémentation : Implemented, tâches vérifiées ; première tâche non cochée : aucune. Statut pipeline : livré une fois clôture et dernier push du reçu vérifiés. Aucune activation utilisateur restante.
