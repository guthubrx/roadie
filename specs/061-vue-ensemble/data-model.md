# Modèle 061

OverviewConfig : enabled Bool=true, presentation enum archipelago|bays=archipelago, loupe Bool=true, magnification Double 100...250=150, hotkey String vide. Chargement ancien : défauts sans réécriture.

OverviewModel : écrans présents, bureaux identifiés par DisplayID+DesktopID, stages par StageScope, fenêtres WindowSwitcherEntry. Projection stable du snapshot et des entrées de l’inventaire. Actif = state.currentDesktopID et activeStageID ; sélection = WindowID ; loupe = identité bureau. Aucun de ces trois états n’est confondu.

OverviewLayout : rectangles écrans/bureaux/stages/fenêtres en coordonnées locales, hauteur documentaire bornée par densité ; le panneau défile si nécessaire. Aucun rectangle ne chevauche un frère. Les images sont contenues dans les cartes.

Cycle : fermé -> acquisition -> ouvert -> activation ou annulation -> fermé. Un résultat de chargement obsolète est ignoré. Échec d’activation : rester ouvert avec erreur. Fermeture : annuler tâche, minuterie et rétention overview.
