# Corrections après révision zéro

L’exécution complète a révélé un test d’overview qui attendait une disparition synchrone, alors que les fondus sont maintenant activés dans la configuration utilisée. Contrat corrigé : clavier rendu immédiatement, surface fermée après un délai borné ; aucune nouvelle Space.

La revue du changement de politique a révélé un effet en cours qui conservait son ancienne durée après coupure. Reproduction : turningEffectsOffFinishesActiveTargetsWithoutRetiling échoue avant correction (disable-red.log, assertion atteinte). Correction : fin aux cibles exactes par SettingsLiveApplyController et EffectAnimator existants. La suite ciblée passe après correction (disable-green.log).

Le retour utilisateur révèle aussi le contour sur Firefox et T3 malgré real activé. Sur T3, la bande vide est AXGroup sans action et de cadre égal à la fenêtre. Les groupes interactifs sont plus petits et ont des actions ; la qualification les garde exclus. Un journal différé de décision et un journal de qualification permettent d’observer le cas Firefox. T034 n’est pas encore clos.

Scanner : Gitleaks dir sur un chemin absolu contenant .worktrees est exclu par les règles figées et scanne zéro octet. OSV marche aussi sur zéro source à cause de la racine ignorée. Ces résultats ne sont pas des succès de couverture. La prochaine révision conserve ces tentatives et utilise une copie SHA identique hors .worktrees pour Gitleaks, et le verrou Package.resolved explicite pour OSV. Les règles ne sont pas modifiées.
