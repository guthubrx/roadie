# Observations154

Journaux disponibles :7 novembre2026 15:41:47UTC au10 novembre2026 08:53:18UTC au début de l'analyse. Les archives ne couvrent plus le3 au7 novembre matin. Les observations suivantes concernent cette fenêtre, avant les essais154.

- 32 reprises de glisser natif ;18 dépôts journalisés. Les autres fins ne sont pas assez détaillées pour être toutes classées comme échecs.
- 97 refus de placement pour fenêtreAX absente ou en quarantaine ;5 refus d'écriture/lectureAX. Ces compteurs ne prouvent pas102 défauts distincts.
- 24 refus de focus du sélecteur, surtout PowerPoint. Les refus d'application/AX sont explicites, sans preuve suffisante d'une cause nouvelle dans le déplacement.
- 233 captures de pointeur prêtes,3 absentes ; les replis de capture de scène apparaissent dans les raisons deadline/source_late/target_late.
- Une garde du suivi direct exigeait l'absence de zoom dans chaque portée ; elle annulait donc un glisser issu d'un zoom initial. Le test154 échoue sur la base avec isActive=false, puis passe corrigé.
- Dans le transfert fictif initial vers l'écran interne, un appuiCGEvent observé a produit deux entrées AppKit au routeur. Le filtre doit reconnaître l'identité de l'événement avant toute invalidation de l'aperçu.

- Après chargement, le relevé réel montre Notification Center36, fond1512×982 sans sous-rôle, devant l'application. Le glisser avec modificateur le filtrait déjà ; les pickers de titre/bord/focus ne le filtraient pas. Le test échoue sur ces trois entrées avant la réutilisation du même critère strict.

Les journaux bruts, titres et captures originales sont conservés hors Git dans /Users/moi/.local/state/roadies/validation/2026-11-10-154.

- Validation supplémentaire Ctrl : la comparaison intégrale de DisplaySnapshot annulait un geste pour un changement de isMain lié au focus. Régression rouge reproduite, comparaison limitée aux identifiants et géométries ; raisons de rejet détaillées.
