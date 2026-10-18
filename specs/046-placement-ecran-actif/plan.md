# Plan

Réutiliser WindowPlacementConfig, le catalogue et choiceLabel. Le comportement
focused_display et le rechargement immédiat existent et sont testés : aucune
nouvelle option, dépendance ni migration forcée des configurations explicites.
Sans écran actif connu, privilégier l'écran contenant la fenêtre avant le premier
écran de la liste. Ce repli est couvert par le test de placement existant sans focus.

Tester l'absence de table/clé, les trois valeurs explicites, le repli sur valeur
invalide, le défaut proposé par les paramètres et le retour à ce défaut depuis
une valeur explicite. Réutiliser les tests de placement sur deux écrans. Vérifier
la suite complète, compiler avec deux tâches et installer avec certificat stable.

Preuve du comportement : essai réel utilisateur précédant cette demande, deux
terminaux dans le stage de leur fenêtre active malgré la souris sur l'autre écran.
L'accès visuel au bureau reste indisponible ; ne pas inventer de capture du panneau.
