# ADR-006 : Parking et restauration des stages d'écrans

## Statut

Accepté.

## Contexte

Roadie gère ses stages et desktops virtuels au-dessus de macOS. Lorsqu'un écran disparaît, l'ancien comportement pouvait traiter les scopes associés comme obsolètes, puis les migrer ou les nettoyer via les chemins de snapshot, audit et heal. En pratique, cela peut mélanger les fenêtres d'un écran disparu dans une seule stage, rendre l'état difficile à récupérer, ou provoquer des oscillations pendant les rafales d'événements d'écran.

Les identifiants d'écran fournis par le système peuvent aussi changer au rebranchement. Un simple `DisplayID` ne suffit donc pas à retrouver l'écran d'origine.

## Décision

Roadie introduit un modèle explicite de parking d'écran :

- les scopes d'écrans absents sont conservés ;
- les stages non vides d'un écran disparu sont rapatriées comme stages distinctes sur un écran hôte ;
- chaque stage rapatriée garde une origine logique restaurable ;
- la restauration automatique n'a lieu que si l'écran revenu est reconnu sans ambiguïté ;
- les événements de changement d'écran sont stabilisés avant toute mutation de layout.

Un service dédié `DisplayParkingService` devient le point central des transitions de topologie. Les chemins `StateAudit`, `DaemonSnapshot` et `DaemonHealth` ne doivent plus effectuer de migration destructive implicite.

## Conséquences positives

- Débrancher un écran ne mélange plus toutes les fenêtres dans une seule stage.
- Les stages rapatriées restent utilisables pendant l'absence de l'écran.
- Le rebranchement peut restaurer l'organisation multi-écran sans reconstruire manuellement les stages.
- Les cas ambigus restent visibles et non destructifs.

## Conséquences négatives

- L'état persistant de stage devient plus riche.
- Il faut maintenir une empreinte logique d'écran et des règles de match conservatrices.
- Certains cas ambigus nécessitent une intervention utilisateur ou restent parkés.

## Garde-fous

- Ne jamais supprimer un scope uniquement parce que son écran est absent.
- Ne jamais restaurer automatiquement si le match d'écran est ambigu.
- Ne jamais ajouter de polling AX agressif dans le chemin focus/bordure.
