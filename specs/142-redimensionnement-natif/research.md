# Recherche et décisions

Le code actuel bloque les passes pendant un bouton enfoncé, puis applique les fences dans LayoutMaintainer.applyGesture. Les poignées emploient un chemin séparé à 20 Hz. Le writer est Sendable, injectable et partagé avec le registre : le réutiliser en arrière-plan plutôt que recréer un setter AX. L’observateur lit les cadres depuis sa callback MainActor ; le resize doit éviter ces lectures pendant le geste.

Choix : laisser la cible native sous contrôle de macOS ; adapter seulement les voisines. Une prise de contrôle globale par interception des événements changerait les gestes, les modificateurs et les comportements propres aux applications : rejetée. Un simple retrait de la garde souris ferait réappliquer l’ancien arbre : rejeté. Augmenter la cadence du maintainer complet multiplierait les acquisitions et la persistance : rejeté.

CADisplayLink synchronise l’ordonnancement, sans garantie de rythme d’acceptation AX. Les résultats sont invalidés par session et génération. Un appel AX déjà engagé ne peut pas être supposé annulable ; vérifier avant chaque attribut et refuser toute suite obsolète.

Sources Apple et analyse de référence conservées dans les notes de recherche de cette conversation. Aucun code tiers copié. Outil Sequential Thinking absent du catalogue chargé ; arbitrage écrit ici avant codage.

Source de frame choisie : CGWindowListCopyWindowInfo(.optionIncludingWindow, id) avec identité CG/PID stricte. La vérification finale conserve la dernière observation WindowServer ; la relecture AX et les refus des voisines restent au point commun d’écriture. Le runtime ne consomme pas takeGesture ; il clôt le seul geste confirmé après sauvegarde.
