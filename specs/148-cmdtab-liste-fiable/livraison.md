# Livraison148 — Cmd+Tab sans fausse liste vide

Code747e812288653bc1ca61e59bc7e84083d739fa22 intégré en fast-forward sur main et poussé vers https://github.com/guthubrx/roadie.git ; commit distant vérifié identique. Ce reçu est une clôture documentaire distincte, sans autre changement de Sources/Tests. Aucun tag ou nouvelle release publique.

Le défaut reproduit est une acquisition invalidée présentée comme zéro fenêtre à l’ouverture. Le rechargement reprenait déjà ce cas, l’ouverture non. Les reprises sont maintenant réunies dans le service commun (quatre essais au plus, trois pauses100ms annulables). En cas d’échec durable : message d’indisponibilité, Tab pour réessayer ; aucune ancienne liste écrasée par un faux vide. Même profil, mêmes exclusions, même machine de sélection au relâchement.

Deux tests rouges,105tests ciblés verts puis7tests148 et2438tests/365suites séquentiels,28scripts verts. Avant sur Mac réel :13acquisitions pour20gestes,6indisponibles et7valides. Après :16sessions distinctes,16acquisitions à12entrées,0indisponible ;15panneaux visibles aux instants échantillonnés et capture finale remplie inspectée. Aucun taux généralisé ni absence universelle d’échec système promis. La série après n’a pas subi d’invalidation ; le parcours de reprise est vérifié avec readerSnapshot réel et fournisseur de test contrôlé. Détail dans validation.md.

Version Release signée active : UUIDA7AED9D8-6D65-334C-A58F-8C4FE15EDDA9, PID73795, santé5/5 avant/après nettoyage. UUID construit/installé identique et526empreintes Sources/Tests identiques au checkout principal. Configuration TOML et certificat stable78a75e8032f190a20072eb91cc2919aac344ef78 conservés.

Preuves : diaporama vérifié,5étapes/2captures natives à données fictives et relevés du parcours Cmd+Tab réel explicitement distingués. Captures utilisateur/réelles avec documents privés gardées hors Git. Aucun clic ou curseur inventé, parcours clavier. Contrôles de navigation et lecture/pause vérifiés dans html_preview ; diffusion html_render au bilan.
Fichier : /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/025-settings-readability/preuves-corrections/2026-11-01-148-cmdtab-liste-fiable/preuves.html
Bruts et dernier rollback : /Users/moi/.local/state/roadies/validation/2026-11-01-148

Revue indépendante refusée par Bridget (routing_candidate_unavailable, capability_unavailable/workspace_diverged, aucun taskID). Aucun contournement. Signalement automatique autorisé envoyé à bridge1016 ; id8cac53e7-c08e-4b4a-a1b2-2d9d9314f997, delivery1d7100bc-ef8c-4485-bc7f-9c32c1e51edf, état in_flight. Pas d’accusé de lecture ou de réparation inventé, pas de rappels. Relecture locale décrite dans analysis.md, sans grade d’audit ou verdict indépendant favorable inventé.

Nettoyage effectué : pilote natif arrêté par sa commande de fin, sortie du PID47438 vérifiée ; désenregistrement LaunchServices temporaire et réenregistrement de l’application installée. Helpers exécutables et leurs copies d’archives retirés, sources conservées. Ancien rollback147 remplacé par le rollback148 utile. Cache Swift propre supprimé après contrôle du checkout de dépendance et des fichiers ouverts. Neuf éléments supprimés,1475968350octets de fichiers (pas une mesure des blocs APFS libérés). Ancienne branche147 intégrée supprimée sans force ; worktree/branche148 attachés au fil conservés. Preuves originales, configuration, installation et ancienne stash non intégrée conservées.

Début vers04h37CET, activation/essais/intégration/nettoyage vers05h04CET. Toutes les tâches cochées, livraison active et vérifiée ; push du présent reçu contrôlé avant le bilan final.
