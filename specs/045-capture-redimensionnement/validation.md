# Validation 045

## Parcours réel avant correction
Observation assistée par l'utilisateur de 45 secondes, le 18 octobre 2026 de 14:28:30 à 14:29:15 UTC. Géométrie des fenêtres à 20 Hz, état du bouton et journaux Roadie ; aucune injection souris ni capture d'écran.

Chrome 46100 passe de y=279/h=695 à y=599/h=375 pendant l'appui, puis revient à y=279/h=695 au relâchement. Aucun geste ciblé correspondant n'est enregistré. Le garde de main.swift refuse le clic en se fondant sur la zone d'une poignée prévue, avant son acceptation. Les rectangles transparents borders peuvent aussi arrêter le picker natif. Six applications par poignée sont parallèlement enregistrées, sans échec d'écriture ; leurs durées réelles de traitement vont de 48,3 à 79 ms pour les cinq appels non vides. Ces durées comprennent les appels AX, sans mesurer toute la latence du geste.

Un autre geste pousse iTerm à une hauteur de 692 points en ne laissant que 232 points à Chrome. Chrome refuse et conserve au moins 375 points ; une correction vers une disposition faisable est alors nécessaire. Ce cas ne prouve pas une perte de capture. Les minimums de Chrome (500 points de largeur observés aussi) doivent rester respectés.

## Reproduction et correction
Un test avec quatre fenêtres, décorations placées devant elles et clic dans un interstice de poignée reproduit le défaut avant correction : quatre assertions échouent, cible absente et taille restaurée à 395 au lieu des 375 points choisis. Après correction, le geste est conservé et l'arbre ainsi que les cadres restent stables sur quatre passes supplémentaires.

La poignée réclame le geste seulement après acceptation par son coordinateur. Le garde géométrique et sa liste d'état dérivé sont retirés. Le filtre étroit des seules décorations borders est partagé avec le picker des gestes ; le picker du focus ordinaire reste inchangé. Les tests couvrent aussi refus de poignée, acceptation sans double geste et intention native précédente encore dans UserInputActivity.

40 tests ciblés réussis, puis 1 692 tests dans 199 suites réussis avant revue. Le constructeur et le raccordement runtime ont été relus localement. Aucune nouvelle dépendance ni réglage.

## Revue et vérifications supplémentaires
Revue indépendante en lecture seule : aucune régression avérée. Le relecteur n'avait pas de shell et n'a exécuté ni diff, ni build, ni tests. Le cas d'un geste natif déjà consommé par LayoutMaintainer a été ajouté aux tests : observation native en attente, prise explicite acceptée, écriture de la poignée pendant l'appui, relâchement, six passes supplémentaires. La garde physique empêche l'ancien geste d'intervenir pendant l'appui ; la disposition finale et l'arbre restent conformes ensuite. Aucune modification supplémentaire du code de production n'était nécessaire pour ce scénario.

Une poignée périmée qui refuse le clic peut laisser une attente native sans changement de cadre ; l'attente existante est bornée et ne prouve pas un retour de taille. Le refus ne doit pas supprimer à nouveau un geste sur la seule présence géométrique d'une poignée. Le critère de décoration reste volontairement étroit et dépend du nom de processus borders ; aucun filtre générique d'applications sans AX n'est introduit. Le diagnostic frontApp montre encore la fenêtre CG de premier plan, même si le picker de geste ignore sa décoration.

Un test existant de TickScheduler lisait l'état physique de la souris pendant l'essai utilisateur et échouait aussi isolément. Il reçoit désormais explicitement mouseButtonsPressed=false pour simuler son scénario sans appui. Les tests de la priorité d'un véritable appui restent séparés. Résultat final : 1 693 tests dans 199 suites réussis. Les modifications après la compilation Release concernent uniquement les tests et les documents.

## Parcours réel après installation
Observation du 18 octobre 2026, de 14:52:41 à 14:53:40 UTC : 274 échantillons de géométrie et d'appui. À 14:52:51, le bord d'iTerm 46200 est ciblé malgré frontApp=borders ; le geste natif est traité à 14:52:52, hauteur 292 conservée jusqu'au geste suivant. À 14:52:54, Chrome 46100 passe à y=599/h=375 ; le geste est reconnu et sa hauteur reste conservée. Les applications par poignée de 14:53:00 réussissent sans échec. Le changement de largeur suivant est accompagné d'un nouveau geste natif réel ; il ne constitue pas un retour spontané de la poignée précédente.

L'utilisateur confirme après installation : « La nouvelle taille reste ». Des contraintes Chrome de largeur 500 points ont également été observées ; les ajustements nécessaires pour les respecter restent actifs. Le contrôle ne constitue pas une mesure globale de latence.

## Limites et livraison
Le build T3 local est signé ad hoc, sans certificat stable. L'outil de test indique accessibility=false, screen_capture=false et post_events=false, malgré les autorisations déjà activées par l'utilisateur. Ne pas demander de les réactiver à répétition. La cause exacte de ce décalage n'est pas établie ; le test est assisté par l'utilisateur, sans changement des droits.

Compilation Release réussie et installation vérifiée. UUID du binaire compilé et installé : 60B2AD40-0F27-3EB6-BA6D-08570FEF5290. Signature stable conservée, certificat 78a75e8032f190a20072eb91cc2919aac344ef78 ; vérification stricte réussie. Configuration avant/après identique : SHA-256 6429d922fe7bf820fdd962acb9d79ef9c6ec5f028396672a0646180fa70bc0bc. Redémarrage vérifié, PID 65772, quatre contrôles santé OK. Application : /Users/moi/Applications/Roadie.app.

Sources/Tests : 293 empreintes vérifiées après compilation, puis deux fichiers de tests seuls complétés après revue. Traces hors Git : /Users/moi/.roadies/diagnostics/2026-10-18-session045/, dont trace-reelle.json pour les événements initiaux, positions-apres.jsonl et evenements-apres.json pour le contrôle après correction. Le premier fichier brut de positions avant correction a été réutilisé par erreur par un relevé suivant ; les événements initiaux filtrés et les constats consignés avant correction restent disponibles.

Preuves visuelles incomplètes : bureau inaccessible, aucun diaporama ni clic capturé dans une image. Le parcours réel a été observé par géométrie CoreGraphics et journaux, puis confirmé par l'utilisateur.

Correction f0c39696 fusionnée et poussée sur main. Branche de session supprimée,
fichiers de compilation et recette temporaire retirés. Le worktree lié à cette
conversation reste disponible, détaché ; les diagnostics restent hors Git.
