# 013 — Champ natif dans la boîte de commandes

Date : 2026-10-15. Statut : adopté pour la correction 038.

La barre dessinait sa saisie et retenait les touches par CGEventTap. Le caret était
un caractère et les raccourcis Commande pouvaient atteindre la fenêtre en dessous.
Réimplémenter sélection, édition par mot, presse-papiers, undo et composition serait
plus complexe que confier ces règles au système.

Un NSTextField vit dans un NSPanel non activant et key, au cadre de contenu existant.
Le tap de recherche observe seulement les clics : il laisse les touches atteindre
le contrôle natif. Le panneau traite les commandes de navigation et validation et
route les raccourcis Édition vers son propre éditeur, car le daemon n'a pas de menu
Édition. Les modèles purs restent responsables de recherche et complétion.

Les rafraîchissements à texte identique ne réassignent pas le champ : sélection et
composition restent stables. Les majuscules sont du texte ; les résultats peuvent
toujours se parcourir avec les flèches. L'application ciblée reste active et T3 ne
doit pas être redémarré. Le nettoyage ferme le panneau avant toute action différée.

Les suggestions dessinées utilisent leur géométrie pour les clics. Un clic sur une
suggestion insère le choix sans l'exécuter ; Retour valide. Un clic extérieur ferme
la boîte sans rejouer le clic. Aucune nouvelle dépendance ni donnée persistante.
