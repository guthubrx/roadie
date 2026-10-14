# Diagnostic et réutilisation — session 027

- SettingsViewModel.editText applique seulement les clés font_size ; les autres
  champs attendent commitDraft via Retour ou perte du focus.
- SettingsService valide un candidat, sauvegarde, remplace par rename, recharge
  la configuration puis publie roadieSettingsDidChange avec seulement configPath.
- startTilerComponent écoute AX, les bureaux, écrans et réveils ; il n'écoute pas
  directement cette notification de paramètres.
- Les douze entrées non scalaires du catalogue sont affichées en lecture seule
  avec un bouton d'ouverture du fichier. Six sont de simples listes.
- ConfigFileEditor préserve les lignes et commentaires des scalaires. Ses lectures
  de valeurs brutes et tableaux de tables peuvent aider l'édition structurée.
- TOMLKit est déjà une dépendance de RoadieCore ; réutiliser son analyse existante.
- La configuration réelle comporte des marges par côté et une exception par écran.
  Une marge locale peut donc conserver sa priorité après un changement général.
- TargetOverlayStyle et SearchBarRenderer suivent déjà les tailles en place ;
  ajouter les familles au même circuit de mise à jour.
- Pas de changement de configuration réelle pour les tests : fixtures temporaires.
