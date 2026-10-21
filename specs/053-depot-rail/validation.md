# Validation 053 - Dépôt fidèle dans le rail

## Demande et décisions

L'utilisateur confirme que le point de dépôt fait foi : haut, interstice et bas.
Un dépôt sur une carte rejoint sa stage. L'ordre persistant remplace la partition
automatique occupées/vides. Le rail reste défilable, sans nouvelle option à régler.
Une ancienne stage anonyme devenue vide reste masquée comme auparavant ; cela
compacte la liste sans réordonner les autres stages ni modifier la destination.

## Reproductions

Les deux derniers événements réels d'affectation confirment les écrans et stages,
mais n'avaient pas de coordonnées de dépôt. Ils ne suffisent pas à prouver la
position visée. Etat initial et quatre événements archivés hors Git dans
/Users/moi/.roadies/diagnostics/2026-10-21-session053/.

Avant correction, neuf assertions échouent : position du bas non transmise,
rang non persisté sur un/deux écrans, ordre changé quand une carte vide se remplit.
Après une première correction par rang, huit assertions supplémentaires échouent
si une stage est ajoutée en arrière-plan entre la prise de cible et le dépôt.
La destination est donc portée par un identifiant de voisin ou la fin de liste,
puis résolue dans la transaction verrouillée d'affectation.

## Revue et décisions

Revue indépendante en lecture seule, sans shell/diff ni écran chez le réviseur.
Le responsable relit le diff, exécute les tests et assume les corrections.

- D1 : ancre stable et calcul sous verrou ajoutés. Le slot doit encore être vide,
  anonyme et non parqué ; une ancre disparue fait échouer sans mutation.
- D2 : retrait du repli vers le panneau source lorsque le panneau destination
  manque. Panneau et écran sont choisis ensemble.
- D3 : disparition de la carte source anonyme vide conservée ; aucune suppression
  persistante ni réorganisation des autres cartes. Ce comportement est distinct
  du tri automatique retiré à la demande de l'utilisateur.
- Haut/milieu/bas, défilement, aperçu transparent à la souris et concurrence sont
  couverts par les tests. Le gel d'une reconstruction asynchrone est relu dans le
  contrôleur ; son parcours réel reste à vérifier sur un bureau accessible.

Le repère « Nouvelle stage » indique l'emplacement ; le survol d'une carte la met
en évidence. L'aperçu et le dépôt utilisent la même sélection. Aucun trait bleu.
Au relâchement, le journal indique le point en coordonnées écran NS, le type de
cible, son écran, sa stage et l'ancre demandée. Pas de relevé AX par mouvement.

## Complexité, simplicité et limites

Sélection et aperçu linéaires dans les cartes ; résolution du rang linéaire dans
les stages lors du seul dépôt. Réutilisation de la transaction existante, sans
nouvelle dépendance. La copie de la liste persistante à chaque mouvement a été
retirée grâce à l'ancre. Le calcul du voisin reste répété pour placer le repère :
il porte sa géométrie, sans stocker un état de destination qui pourrait diverger.
Pas de gain de performance chiffré revendiqué.

Preuves visuelles incomplètes : CUA renvoie « CUA_REPL_ENABLED_SURFACES is required »
et screencapture « could not create image from display ». Aucun clic aveugle,
aucune demande répétée d'autorisation macOS, aucun diaporama fabriqué.

## Vérifications

95 tests ciblés réussis, puis 1 758 tests dans 210 suites après les derniers cas
de refus de destination et le retrait du repli de panneau. Les trois cas de refus
vérifient l'identité des octets persistés avant/après. 303 empreintes Sources/Tests
conservées avant compilation Release et vérifiées inchangées après installation.

Release compilée et installée ; UUID
458CF5AB-3B7E-3F5A-9B09-656E7B0FF331 identique entre binaire compilé et installé.
Signature stricte vérifiée ; certificat 78a75e8032f190a20072eb91cc2919aac344ef78
et configuration inchangés. Redémarrage terminé, PID 81466, cinq contrôles santé OK.
Recette temporaire d'installation à deux tâches retirée. Essai utilisateur proposé
sur les trois positions ; aucun résultat manuel revendiqué à ce stade.
