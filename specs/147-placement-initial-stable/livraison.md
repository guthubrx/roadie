# Livraison147 — nouvelles fenêtres iTerm2

Code6423057bff18261c822efaaa1636d96ec589e8e5 intégré en fast-forward dans main et poussé vers https://github.com/guthubrx/roadie.git ; SHA distant vérifié identique. Ce reçu est une clôture documentaire distincte, sans modification de Sources/Tests.

Correction active : la fenêtre neuve rejoint d'abord la destination, puis le writer ajuste la taille en gardant ses réparations historiques. Le diagnostic a écarté le retour prématuré à l'animation sur les cas reproduits ; le défaut venait du resize effectué sur l'écran de naissance. Fenêtres connues, animations et budgets conservés.

Validation : deux tests rouges avant correction ; 47 tests ciblés,2431tests/364suites et28scripts réussis. Dix CmdN natifs après installation, dont quatre vers une grande tuile ; aucun resize observé à l'origine, dix cadres finaux égaux à leurs cibles, stabilité mesurée au moins7,308s par fenêtre. Pas de gain de latence généralisé : charge et dispositions différentes entre séries.

Version Release signée chargée, UUID703A4229-EBC7-3114-A08F-8A998776135E, PID90574, santé5/5 après nettoyage. UUID du binaire construit et installé identique ;525empreintes Sources/Tests identiques entre le checkout construit et main. Certificat78a75e8032f190a20072eb91cc2919aac344ef78 et configuration TOML conservés. Aucun nouveau tag ou release publique.

Preuves : diaporama vérifié,6étapes/3captures, contrôles de navigation et lecture/pause vérifiés dans le navigateur T3 ; parcours réel au clavier explicite, aucun clic inventé. Les captures fixes montrent les résultats ; les relevés CG établissent les séquences. La première surface macOS peut rester visible avant notification à Roadie, et de courts ajustements de taille persistent à destination. Échantillonnage environ120Hz, pas un film exhaustif. Détail et outils dans validation.md.
Fichier : /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/025-settings-readability/preuves-corrections/2026-10-31-147-placement-initial-stable/preuves.html
Bruts et rollback : /Users/moi/.local/state/roadies/validation/2026-10-31-147

Revue indépendante demandée via /Users/moi/.codex/skills/bridget/SKILL.md ; refus routing_candidate_unavailable (capability_unavailable et workspace_diverged). Aucune tâche créée, aucun changement de base, hôte, droits ou compte pour contourner le refus. Relecture locale documentée, sans verdict indépendant ou auditV15 inventé.

Nettoyage : fenêtres, programmes et helpers propres arrêtés, stage de validation vide supprimée, quatre fenêtres ouvertes pendant les essais remises dans la stage3 externe sans fermeture ; état utilisateur global non restauré. Signature et TOML vérifiés après ces actions. Enregistrement LaunchServices temporaire retiré. Cache de compilation nettoyé après fin des builds. Branche146 intégrée supprimée sans force ; worktree attaché au fil et branche147 conservés, deux dossiers d'analyses étrangers préservés. Captures et manifestes originaux conservés hors Git.

Début annoncé vers18h22, clôture vers19h01, estimation30–60min respectée. Périmètre147 terminé, aucune tâche non cochée ; livraison activée et vérifiée. Le push de cette clôture est contrôlé avant le bilan final.
