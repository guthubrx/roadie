# Plan

Réutiliser DividerResizeCoordinator, SplitResizeController, le réglage existant et les fixtures 043. Corriger uniquement le test d'occupation en reconnaissant les fenêtres sans titre ni AX du processus de décoration borders ; ne pas ignorer toutes les fenêtres flottantes/illisibles. Ajouter une reproduction avec deux/quatre fenêtres, un contre-exemple d'application normale et la bascule du réglage.

Comparer à données identiques le traitement d'un bord natif par LayoutMaintainer et celui d'une séparation par DividerResizeCoordinator. Mesurer séparément les acquisitions et écritures, et éventuellement le temps logiciel avec un test opt-in court. Le système AX simulé et l'absence des délais d'événements interdisent une conclusion sur la vitesse ressentie. Documenter le protocole réel restant à faire.

Tests ciblés puis contrôles nécessaires, Release, installation signée, santé. Preuves du parcours natif si le bureau devient accessible ; sinon préciser la limite. Aucun nouveau réglage ni dépendance. Coût du filtre inchangé O(h × w), hors mouseDragged.
