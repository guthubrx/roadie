# ADR 026 — Identifiants de capture clavier sans adresse de session

Date :1novembre2026. Statut : accepté. Session149.

## Contexte
Un crash natif SIGTRAP dans swift_unknownObjectRetain provient du callback commun de KeyEventTapSession. Son contexte C était une adresse non retenue de la session. La fermeture retirait la source et désactivait le tap, mais ne révoquait pas l’adresse des événements déjà en file.

## Décision
Le contexte devient un identifiant monotone opaque. Un registre sous verrou associe cet identifiant à un propriétaire faible. Le callback cherche le propriétaire sans déréférencer le contexte. La fermeture retire d’abord l’identifiant, désactive et invalide le port Mach puis invalide sa source. Les trois types de session réutilisent le même nettoyage.

## Conséquences
Un événement tardif retrouve nil et passe sans effet. Un ancien identifiant ne cible pas une nouvelle session, même si le système réutilise une adresse d’objet. Le registre ne prolonge pas la vie d’une session et garde une entrée par capture active. Un petit registre partagé remplace l’emprunt de pointeur et réduit le nettoyage dupliqué. Les tests couvrent retrait, libération du propriétaire et non-réutilisation du contexte. Aucun nouveau droit système.
