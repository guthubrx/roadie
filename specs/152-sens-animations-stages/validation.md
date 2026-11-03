# Validation152 — version active et vérifiée

Le3novembre2026. Installation signée active, UUID D4E23DD7-5D40-3E0B-AB46-FB88A8AA0318, PID29858 au contrôle. Santé5/5, certificat SHA-1 78a75e8032f190a20072eb91cc2919aac344ef78 conservé. Configuration utilisateur inchangée à l'octet près.537 empreintes Sources/Tests conformes avant et après activation. Pas de nouvelle release publique.

## Résultat natif

Deux applications AppKit fictives, une fenêtre par stage sur l'écran interne. Navigation Option+flèche injectée via CGEvent ; BTT exécute les raccourcis existants. Captures natives limitées au bandeau fictif, sans retouche ni clic souris ajouté. Descente : A se déplace vers le bas et B arrive du haut. Remontée : B sort par le haut et A arrive du bas. L'origine du parking x5351 n'est plus un trajet visible. Les vraies fenêtres reçoivent une seule cible finale ; deux images transitoires sont animées par les couches graphiques.

Dix bascules de mesure : neuf animations complètes entre293,9 et356,0ms, médiane313,6ms. Une bascule directe lors du dépassement du délai. Source acceptée :30,2–67,0ms, médiane44,6ms ; cible :25,5–60,7ms, médiane28,3ms. Le délai source est120ms, contrôlé au plus un tick33ms après l'échéance ; la préparation cible est bornée à200ms et se déroule pendant le mouvement. Les images ne restent pas affichées en attendant indéfiniment une application.

CPU du processus roadied :1,46seconde sur9,62secondes pendant dix bascules, soit15,2% d'un cœur. Repos adjacent :0,13seconde sur5,01secondes, soit2,6%. Cela inclut le fonctionnement normal du daemon ; ce n'est pas une attribution exclusive aux effets. GPU et WindowServer non mesurés séparément. La mémoire résidente de la série finale part de131328Kio et finit à133504Kio. Cette série courte ne prouve pas l'absence de fuite. Deux images de2millions de pixels maximum représentent environ16Mo RGBA, hors surfaces et allocations système ; leurs références sont explicitement libérées à la fermeture.

Six changements rapides alternés,110ms entre injections : dernière stage conservée, A au cadre(150,32), B au parking(5351,32). Les deux clients fictifs se terminent proprement. Les deux stages temporaires sont supprimées. La stage interne6, observée avant cette série, est restaurée ; l'écran externe est refocalisé sans changer sa stage choisie entre-temps.

## Tests et revue

2497tests /378suites verts en64,184s. Après l'ajustement final du focus et la libération explicite des images :25tests ciblés /5suites verts en4,267s. Cas couverts : ordre non numérique, bouclage, parking déclaré visible, effets désactivés, capture absente ou tardive, annulation avant/après départ, placement unique du runtime, retarget de scène, masque avec stationnaires chevauchants. Le focus est nul pendant le mouvement et exécuté une fois après la fin.

Deux revues indépendantes en lecture seule, sans tests exécutés par les relecteurs. Leurs constats sont traités dans revue.md : écrans observés explicites, métadonnées chaudes hors bascule, origine CG courante, tests du runtime et diagnostic des captures. Aucun défaut bloquant prouvé par lecture. Les corrections issues des mesures natives sont validées par le responsable ; aucun nouveau verdict indépendant inventé.

## Essais exclus et limites

Avant : traces natives x5351→x150 dans les deux sens. La première correction AX seule reste bloquée au bord supérieur. L'utilisateur a accepté une capture temporaire. Huit mesures SDK initiales :54,6–131,3ms ; le premier budget40ms était trop court. Le mouvement commence maintenant dès la source ; le focus attend la fin pour éviter un appel AX bloquant pendant le rendu.

Les séries interrompues par des clics, les captures contenant une fenêtre utilisateur et une première série finale sans événement d'animation sont exclues des preuves et mesures finales. Aucune cause de cette dernière série n'est affirmée sans observation du garde concerné. Le wrapper BTT annonce une échéance10s pour les longues séries ; les résultats durables des scripts confirment leur fin, sans rejeu automatique d'une opération inconnue. Les premiers contrôles IPC juste après restart ont précédé l'ouverture du socket ; santé5/5 relue après disponibilité.

Une fenêtre non gérée absente du relevé peut apparaître figée dans la scène. Les métadonnées froides, une permission absente ou une capture occupée donnent une bascule directe. Aucun gain général CPU/GPU ni fréquence d'images garantie n'est revendiqué. Les préférences macOS restent inchangées ; les réglages Roadie gardent le contrôle des animations.

Preuves : diaporama vérifié, navigation, lecture/pause, zoom et dernière étape contrôlés par html_preview. Original des captures, manifestes, empreintes, journaux et reçus hors Git : /Users/moi/.local/state/roadies/validation/2026-11-03-152. Diaporama autonome : preuves-corrections/2026-11-03-152-sens-animations-stages/preuves.html.

Intégration et nettoyage Git : à consigner après vérification du commit distant.
