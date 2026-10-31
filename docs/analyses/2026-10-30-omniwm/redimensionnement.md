# Comment OmniWM redimensionne les fenêtres

Étude du 31 octobre 2026. Lecture ciblée de la version **v0.7.6**, commit `3c0783954604eaa9110d0bdb61fa29f953e738ee`. Comparaison avec Roadie au commit `b223718ff9bedc101035cfd5fb0edc0d8704763f`.

Le code d’OmniWM est public, en Swift, sous licence GPL-2.0-only : https://github.com/OmniNull/OmniWM. L’analyse décrit le code lu. Elle ne mesure pas la fluidité de l’application native. Les tests mentionnés ont été lus, pas exécutés.

## Ce qui explique probablement la fluidité

### 1. Un chemin direct pendant le geste

`MouseEventHandler.updateManagedResize` reçoit la position du pointeur. Il modifie la géométrie du moteur Niri ou Dwindle. Si cette géométrie change, il appelle immédiatement `renderInteractiveResize` ou `renderDwindleInteractiveResize`.

Ce chemin construit une disposition pour le workspace concerné. Il évite le parcours normal de rafraîchissement complet. Dans le chemin Dwindle, les contraintes sont actualisées au début du geste ; les passages suivants utilisent explicitement `resolveConstraints: false`.

**Conséquence probable :** moins de travail entre le mouvement et l’envoi des nouvelles tailles. Cela ne garantit aucune fréquence précise.

Sources :
- [Mouvement et rendu](https://github.com/OmniNull/OmniWM/blob/3c0783954604eaa9110d0bdb61fa29f953e738ee/Sources/OmniWM/Core/Controller/MouseEventHandler%2BManagedDrag.swift#L164).
- [Entrée directe du rendu](https://github.com/OmniNull/OmniWM/blob/3c0783954604eaa9110d0bdb61fa29f953e738ee/Sources/OmniWM/Core/Controller/LayoutRefreshController%2BRequests.swift#L63).
- [Rendu Dwindle sans nouvelle résolution des contraintes](https://github.com/OmniNull/OmniWM/blob/3c0783954604eaa9110d0bdb61fa29f953e738ee/Sources/OmniWM/Core/Controller/DwindleLayoutHandler%2BOnDemandFrames.swift#L10).

### 2. Les écritures lentes sont isolées par application

Les nouvelles géométries sont regroupées par PID. Chaque application possède un contexte Accessibility avec son propre fil d’exécution (`OmniWM-AX-…`). Les appels qui demandent réellement aux applications de changer de taille passent sur ces fils.

**Conséquence probable :** une application lente ne bloque pas directement le fil principal ni le fil AX des autres applications. Les fenêtres d’une même application partagent toutefois leur fil. Une requête AX déjà engagée peut encore prendre du temps.

Sources : [regroupement et envoi](https://github.com/OmniNull/OmniWM/blob/3c0783954604eaa9110d0bdb61fa29f953e738ee/Sources/OmniWM/Core/Ax/AXManager%2BFrameBatching.swift), [création du fil par application](https://github.com/OmniNull/OmniWM/blob/3c0783954604eaa9110d0bdb61fa29f953e738ee/Sources/OmniWM/Core/Ax/AppAXContext%2BCreation.swift).

### 3. La dernière taille remplace les anciennes en attente

La boîte d’envoi conserve une seule demande en attente par fenêtre (`pendingByWindowId`). Une demande plus récente remplace la précédente. Des numéros de génération permettent aussi d’écarter les demandes devenues anciennes avant leur écriture.

Exemple pédagogique : une écriture est en cours. Le pointeur demande ensuite 610, 620 puis 630 points. La boîte conserve 630 pour cette fenêtre. Elle n’a pas à rejouer successivement les trois tailles. Elle n’interrompt pas magiquement un appel AX déjà commencé.

**Conséquence probable :** le retard ne s’accumule pas comme dans une file qui conserve tous les mouvements.

Sources : [remplacement des demandes](https://github.com/OmniNull/OmniWM/blob/3c0783954604eaa9110d0bdb61fa29f953e738ee/Sources/OmniWM/Core/Ax/AppAXFrameMailbox.swift#L157), [contrôles de génération](https://github.com/OmniNull/OmniWM/blob/3c0783954604eaa9110d0bdb61fa29f953e738ee/Sources/OmniWM/Core/Ax/AppAXFrameBatchWriter.swift).

### 4. Le geste prend la priorité sur les animations

Au début d’un redimensionnement accepté, le contrôleur arrête les animations du moteur concerné. Le moteur conserve une position de départ et calcule les changements depuis cette base.

Niri modifie une largeur de colonne ou un poids de fenêtre. Dwindle modifie les rapports des séparations qui contrôlent les bords concernés. Les calculs bornent les tailles selon les contraintes connues. Niri compense aussi le décalage de la vue lors d’un redimensionnement par le bord de tête, puis maintient la sélection visible à la fin du geste.

**Conséquence probable :** la souris et une animation précédente ne commandent pas des tailles concurrentes. Le calcul ne dépend pas d’une succession de petites tailles relues dans l’application.

Sources : [prise en charge du geste](https://github.com/OmniNull/OmniWM/blob/3c0783954604eaa9110d0bdb61fa29f953e738ee/Sources/OmniWM/Core/Controller/MouseEventHandler%2BInteractionBegin.swift), [calcul Niri](https://github.com/OmniNull/OmniWM/blob/3c0783954604eaa9110d0bdb61fa29f953e738ee/Sources/OmniWM/Core/Layout/Niri/NiriLayoutEngine%2BResizeUpdate.swift), [calcul Dwindle](https://github.com/OmniNull/OmniWM/blob/3c0783954604eaa9110d0bdb61fa29f953e738ee/Sources/OmniWM/Core/Layout/Dwindle/DwindleLayoutEngine%2BInteractiveResize.swift).

### 5. Les transitions suivent le rythme de l’écran

Les animations utilisent un `CADisplayLink` par écran et échantillonnent leur état à `targetTimestamp`. Le lien est retiré quand il n’a plus de travail. Les courbes de ressort et de décélération interviennent notamment dans le déplacement de la vue.

**Distinction essentielle :** le redimensionnement manuel étudié suit directement les événements d’entrée. Il n’est pas démontré qu’il passe à chaque mouvement par ce `CADisplayLink`. Le code ne justifie donc pas une annonce « resize à 120 images/s ».

Les images intermédiaires des animations peuvent éviter la relecture de vérification (`verify: !isAnimationTick`). Le rendu manuel étudié n’est pas marqué comme image d’animation : sa vérification reste demandée. Il serait incorrect de résumer leur méthode par « ils ne vérifient les fenêtres qu’à la fin ».

Sources : [rythme de l’écran](https://github.com/OmniNull/OmniWM/blob/3c0783954604eaa9110d0bdb61fa29f953e738ee/Sources/OmniWM/Core/Controller/LayoutRefreshController%2BDisplayLink.swift), [politique de vérification](https://github.com/OmniNull/OmniWM/blob/3c0783954604eaa9110d0bdb61fa29f953e738ee/Sources/OmniWM/Core/Controller/LayoutDiffExecutor.swift#L108).

### 6. Des écritures plus courtes et des refus mémorisés

Le setter choisit l’ordre position/taille selon la géométrie actuelle : position puis taille en cas d’agrandissement, taille puis position sinon. Les composants permettent aussi d’envoyer uniquement une position quand cela suffit.

Autour du lot, OmniWM tente de désactiver temporairement `AXEnhancedUserInterface` s’il est actif, puis de le rétablir. Le fait est vérifié dans le code. Le gain exact de cette opération n’est pas mesuré ici.

Le registre évite des écritures déjà appliquées, regroupe les demandes identiques et conserve certains refus terminaux. L’évaluation des échecs distingue aussi les tailles imposées qui restent stables. Cela limite certains cycles de correction inutiles ; cela n’élimine pas tous les refus d’application.

Sources : [setter](https://github.com/OmniNull/OmniWM/blob/3c0783954604eaa9110d0bdb61fa29f953e738ee/Sources/OmniWM/Core/Ax/AXWindowService%2BFrameWrites.swift), [Enhanced UI](https://github.com/OmniNull/OmniWM/blob/3c0783954604eaa9110d0bdb61fa29f953e738ee/Sources/OmniWM/Core/Ax/AppAXEnhancedUIWriteScope.swift), [registre](https://github.com/OmniNull/OmniWM/blob/3c0783954604eaa9110d0bdb61fa29f953e738ee/Sources/OmniWM/Core/Ax/AXFrameApplicationLedger.swift), [évaluation des refus](https://github.com/OmniNull/OmniWM/blob/3c0783954604eaa9110d0bdb61fa29f953e738ee/Sources/OmniWM/Core/Ax/AXFrameFailureAssessment.swift).

## Différences concrètes avec les poignées de Roadie

Lecture ciblée du chemin des poignées. Ne pas généraliser ce constat à tous les modes de redimensionnement natif ou aux commandes.

- Roadie possède déjà une seule cible en attente. Il réutilise un inventaire figé pendant le geste et protège les générations. Ce ne sont donc pas des idées absentes.
- `DividerResizeRuntime.begin` déclenche un minuteur de **50 ms**, soit **20 applications/s au plus**. Le retard du minuteur peut être supérieur sous charge. À titre de comparaison temporelle, un rafraîchissement dure environ 16,7 ms à 60 Hz et 8,3 ms à 120 Hz ; cela ne constitue pas un relevé de performance.
- `DividerResizeCoordinator.flush` passe par une mutation persistante de l’arbre, puis applique la disposition de manière synchrone depuis ce chemin `@MainActor`. Ce travail constitue une piste à mesurer.
- Le setter Roadie regroupe les fenêtres par PID, mais parcourt ces groupes de manière séquentielle dans le chemin lu. Il utilise normalement trois écritures, taille/position/taille, puis une relecture. OmniWM emploie deux attributs dans son setter complet et distribue les demandes sur des fils par application. Le double réglage de taille Roadie répond aussi à une protection pour les changements d’écran : ne pas le retirer sans validation.
- Roadie possède déjà le contournement `AXEnhancedUserInterface` et des protections contre les refus répétés. Il ne faut pas présenter leur simple ajout comme la solution.

Fichiers Roadie étudiés :

- /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/025-settings-readability/Sources/RoadieDaemon/DividerResizeRuntime.swift
- /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/025-settings-readability/Sources/RoadieDaemon/DaemonSnapshot.swift
- /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/025-settings-readability/Sources/RoadieDaemon/StageStore.swift
- /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/025-settings-readability/Sources/RoadieAX/SystemSnapshotProvider.swift

## Piste à retenir pour Roadie

La première piste est un chemin interactif isolé : géométrie temporaire en mémoire, envoi asynchrone par application, dernière cible conservée, puis état durable et contrôle final. Une cadence adaptée à l’écran peut ensuite être évaluée. Augmenter seulement la fréquence du minuteur risquerait d’augmenter les appels AX et le travail synchrone.

Cette piste reste une proposition. Aucun code de production n’a été modifié. Pour confirmer son intérêt, il faut mesurer le délai pointeur→cadre visible, le délai des écritures AX, les images manquées et la stabilité sous charge, avec des applications rapides et lentes.

Tests OmniWM lus comme contrats complémentaires : `NiriResizeAnimationTakeoverTests`, `DwindleInteractiveResizeTests`, `NiriFittedResizeTests`. Ils couvrent notamment la prise de priorité sur les animations, les séparations pilotées, les tailles minimales et les choix manuels conservés. Ils ne prouvent pas une latence native.
