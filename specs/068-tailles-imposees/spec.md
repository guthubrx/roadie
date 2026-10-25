# Session 068 - Fenêtres à taille imposée qui oscillent

Correction demandée le 25 octobre 2026 : la fenêtre de l'émulateur Android passait sans
cesse d'une taille à l'autre.

## Cause
Fenêtre seule dans sa stage, format verrouillé : Roadie demande 1650 × 1087, l'émulateur
répond 471 × 1086. La réponse acceptée ne valait que pour la génération de placement en
cours ; chaque changement de stage ou de fenêtre active en ouvre une nouvelle, Roadie
redemandait la même cible et l'application la refusait de nouveau.

## Correction générique
Refus durable dans `WrittenFrameRegistry` : même cible, même réponse de l'application sur
au moins deux générations consécutives. Le maintien de disposition et les commandes
cessent alors de réécrire cette cible. Une autre cible, un autre cadre observé ou une
écriture acceptée telle quelle relancent le comportement normal. Aucune règle propre à
une application.
