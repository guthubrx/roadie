#148 — Cmd+Tab sans fausse liste vide
Statut : In Progress. Base389b3f59f1510b7ac4ad24d78472b6a50236a645.

Utilisateur : Cmd+Tab affiche régulièrement « No windows here » malgré des fenêtres visibles ; pattern inconnu. Capture fournie.
FR1 : distinguer relevé indisponible et liste réellement vide.
FR2 : une invalidation transitoire pendant acquisition ne doit pas figer une session vide. Reprises bornées, hors fil principal pour AX, annulation et session gardées.
FR3 : conserver périmètre du profil, recherche, exclusions et sélection au relâchement pendant acquisition. Aucun repli vers des fenêtres non autorisées.
FR4 : vérifier défaut/reprise, annulation, échec durable, cas réellement vide et plusieurs ouvertures natives ; preuves sans contenu privé.
