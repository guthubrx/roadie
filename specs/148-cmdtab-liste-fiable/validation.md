# Validation148

Base389b3f59f1510b7ac4ad24d78472b6a50236a645. Diagnostic initial puis correctif : deux tests rouges,105tests ciblés verts,7tests148 verts,2438tests/365suites en séquentiel et28tests de scripts verts. Le testUI attend la fin du fondu de fermeture ; aucune modification des animations.

Version Release signée installée et chargée : UUIDA7AED9D8-6D65-334C-A58F-8C4FE15EDDA9, PID73795, santé5/5. Configuration TOML inchangée ; identité stable78a75e8032f190a20072eb91cc2919aac344ef78 conservée.526empreintes Sources/Tests identiques au build.

Avant :20combinaisons natives Cmd+Tab/Échap via pilote signé (trusted/tap/post_access vrais),13acquisitions distinctes :6indisponibles,7valides à12entrées. Premier pilote cliclick sans effet :16gestes,0acquisition, explicitement exclus. Après :16sessions distinctes au même profil,16acquisitions valides à12entrées,0indisponible,15panneaux visibles aux instants CG mesurés. Première session absente à l’instant de mesure, mais son acquisition valide est bien journalisée. Dernière capture réelle inspectée : cartes présentes. Aucune activation intentionnelle de fenêtre ni modification du profil pendant la série, Échap annule avant relâchement.

La série après n’a pas invalidé de snapshot : la récupération sous invalidation est vérifiée dans le test rouge/vert avec le véritable readerSnapshot, puis dans le contrôleur/panneau natifs avec fournisseur fictif. Les pas en attente et le relâchement pendant acquisition restent couverts par les tests existants de session. Pas de benchmark, de taux de panne généralisé ni promesse « jamais d’échec système ». La cause précise de chaque rejet de snapshot n’est pas instrumentée ; le défaut confirmé est son interprétation comme liste vide au premier chargement.

Preuves : diaporama vérifié,5étapes/2captures fictives issues des panneaux natifs de production. Elles montrent l’échec borné et la reprise par le chemin de navigation ; les essais clavier sur les fenêtres réelles sont distingués et décrits par leurs traces. Leurs captures contenant des documents privés restent hors Git. La capture utilisateur initiale reste aussi privée. Aucun clic ni curseur inventé : parcours clavier. Contrôles suivant/précédent, lecture/pause et dernière étape vérifiés dans html_preview ; journal CONTROLES148 OK.
Fichier : /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/025-settings-readability/preuves-corrections/2026-11-01-148-cmdtab-liste-fiable/preuves.html
Bruts, manifestes, logs et rollback : /Users/moi/.local/state/roadies/validation/2026-11-01-148

Revue indépendante refusée, signalée à bridge1016 ; détails et reçu dans analysis.md. Aucune tâche de substitution ni grade d’audit indépendant inventé. Relecture locale des trois propriétaires et des tests faite.
