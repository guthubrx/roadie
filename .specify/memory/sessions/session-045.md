# Session 045 — Capture fiable du redimensionnement natif

Date : 18 octobre 2026. Correction autorisée après l'essai réel de 043/044.
Branche : session-045-capture-redimensionnement. Specs : specs/045-capture-redimensionnement/.

Le clic natif était rejeté dans la zone prévue d'une poignée avant son acceptation ; les décorations borders pouvaient aussi masquer la cible. Suppression de la garde géométrique, arbitrage à l'acceptation effective et critère de décoration partagé avec le picker natif. Les minimums des applications restent respectés.

Reproduction avant/après ; 1 693 tests / 199 suites réussis après revue et ajout du test d'enchaînement. Test de temporisation rendu indépendant de la souris réelle. Release installée et relancée, UUID 60B2AD40-0F27-3EB6-BA6D-08570FEF5290, PID 65772, quatre contrôles santé OK. Configuration et signature inchangées.

Contrôle réel assisté : gestes identifiés dans les journaux, tailles conservées ; confirmation utilisateur « La nouvelle taille reste ». Preuves visuelles incomplètes : bureau inaccessible. Détails et limites de conservation des traces : specs/045-capture-redimensionnement/validation.md.

Correction f0c39696 intégrée et poussée sur main. Branche de travail supprimée,
fichiers de compilation et recette temporaire d'installation retirés. Worktree de
la conversation conservé détaché de main ; diagnostics conservés hors Git.
