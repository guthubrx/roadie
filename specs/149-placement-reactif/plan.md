# Plan 149

## Diagnostic
Sur la plage 05h10–11h08 CET : 38 tentatives finales échouées dans effects.frames_completed ; layout_apply ne voit que les résultats différés. LayoutMaintainer.record et appendItemEvents ignorent deferred et ne reçoivent pas les résultats finaux. Le compteur d’échecs ne protège donc pas ce parcours.
38 passes live_tick journalisées dépassent 1 s, 10 dépassent 2 s, maximum 5,53 s. L’échantillonnage natif du PID73795 confirme le relevé AX du producteur sur le fil principal. Une session de barre indique max_stall 2,102 s ; ce compteur ne désigne pas une cause unique. startTargetsSearch utilise également snapshot synchrone.

## Changements
1. Faire remonter uniquement les résultats finaux courants des transitions au maintainer ; réutiliser record et les événements par fenêtre. Ne pas compter les images intermédiaires.
2. Réutiliser le mécanisme d’acquisition asynchrone du SnapshotService pour le producteur. Sérialiser les passes via TickScheduler ; vérifier configuration, état, révision, génération et blocages après attente. Préserver les demandes arrivées pendant la lecture et le rejeu du relevé pendant une passe.
3. Passer l’ouverture de la barre par la même acquisition asynchrone ; annulation et jeton d’ouverture. Ajouter seulement les métriques nécessaires au contrôle avant/après.
4. Tests ciblés rouges/verts, suite et revue indépendante sur source publiée ; installation signée, santé et parcours natifs ; intégrer/pousser et nettoyer les seuls temporaires inutiles.

## Limites
Aucune promesse de réponse immédiate d’Excel ou Thunderbird. L’attente doit être isolée de l’interface et les erreurs ne doivent pas créer de boucle. Les métriques historiques sont des événements sélectionnés, pas un taux global.

## Relecture avant activation
Le fournisseur rejouable transmet explicitement focusedWindowReader au fournisseur de base : capture AppKit sur MainActor, puis lecture AX en arrière-plan. Le compteur AX est remis à zéro avant l’acquisition, et non après, pour conserver les applications lentes dans les diagnostics. Un test de régression supplémentaire couvre le focus à travers le rejeu.

## Notifications AX
L’essai natif de réponse lente a isolé un second passage bloquant dans AXWindowEventObserver. Réutiliser watchedWindowIDs pour les identités connues, déplacer les lectures de cadre en tâches bornées par fenêtre et conserver le filtrage d’écho sur MainActor. La génération du registre est vérifiée après l’attente ; une destruction ou l’arrêt annule le retour.
