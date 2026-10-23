# Validation 058 - Cohérence des paramètres
Date : 23 octobre 2026.

## Résultat
Une ligne commune aligne les libellés, contrôles et réinitialisations dans les
douze catégories. À faible largeur ou grande police, les contrôles passent sous
leur libellé. Les règles et autres collections complexes se replient par entrée,
avec un titre identifiable. Les critères et actions gardent les mêmes colonnes.
Les profils du sélecteur utilisent aussi cette présentation. Les aides complètes
sont sélectionnables et défilables dans un panneau borné.

Les menus gardent leur comportement AppKit. Leur surface suit réellement la
police : le bezel arrondi natif restait limité à 28 points avec une police de 32.
La saisie, la validation, la persistance et les raccourcis ne sont pas modifiés.
Aucune dépendance ajoutée. Géométrie O(1) par ligne, mesure du texte O(t).
Une seule ligne partagée remplace les dispositions distinctes ; pas de nouveau
framework de thème. Aucun benchmark ni gain de vitesse mesuré annoncé.

## Tests
- 101 tests ciblés dans 17 suites réussis après le complément ; puis 7 tests
  de présentation dans 4 suites réussis, avec 72 rendus natifs.
- Suite complète du complément : 1 876 tests dans 231 suites réussis, 32,221 secondes.
- 28 tests de scripts réussis.
- Rendus natifs des douze catégories à 1 040 points / police 16 et à 760 points /
  polices 8, 16, 23, 24 et 32. Assertions des positions et largeurs des menus, hauteur suivant la
  police et absence de réécriture de la configuration. Données fictives.
- Aide longue à grande police : dimensions bornées par l'écran, contenu défilable.
- Revue indépendante : tâche Bridget e17527d1-eaa2-47f3-8b1c-23d6780ea88f,
  source e7987e2f. Géométrie jugée saine, avec limites : pas de shell/diff ni
  tests chez le relecteur. État de repli des règles, sélection des profils et
  onglets, cible d'aide, label contextuel des polices et affichage de toutes les
  erreurs corrigés. Le rétablissement des collections était déjà aligné à droite
  par le label extensible ; capture réelle à l'appui.
- Les brouillons invalides et le message temporaire du recorder ne sont pas
  modifiés dans cette correction de présentation. Les popups conservent leurs
  modèles de valeur distincts ; pas de refactor générique supplémentaire.
- Complément demandé après essai : onglets pleine largeur, état actif marqué,
  lignes compactes et libellés courts. Marge AppKit de l'ancien bezel annulée
  après observation native de ses insets (4 à 5 points à gauche).
- Défilement du composant natif d'aide jusqu'à la fin vérifié en test. Rendus à
  largeur minimale complétés pour les polices 8, 16, 23, 24 et 32 points.
- Deuxième revue ciblée : tâche 72c74fea-dab9-4aee-8b57-4f7e5f272219, source
  944609d8. Aucun défaut bloquant relevé. Le cas limite des onglets a été vérifié
  dans le rendu natif, puis ajusté à la largeur réellement disponible : deux
  colonnes à police 32, même dans la fenêtre minimale. Les marges du test et du
  calcul sont désormais identiques. Captures à police 16 et 32 contrôlées.
  Pas de réduction automatique de police pour cacher un mot coupé.
  Les constantes de mise en page restent locales et immuables. Les cas vides
  non atteignables et les refactors génériques ne sont pas ajoutés au périmètre.

## Installation
Premier build Release arm64 installé, puis daemon relancé, PID 82694.
UUID initial : 474DACEB-1E3B-3A76-A6F6-6BC5FA38FE15.
Complément final installé et relancé : UUID 7993A537-B6B2-3509-A069-FA1854E802C7,
PID 11485. Santé finale : cinq contrôles OK.
Signature vérifiée ; certificat 78a75e8032f190a20072eb91cc2919aac344ef78 conservé.
Configuration avant/après installation identique : SHA-256
8dfcd92534c87350adcf423e75b6b468befdac038a78eaed2a855451a32d0f8c.

## Preuves et limites
Ouverture réelle par /settings via saisie native BTT. Capture de Général, clic
natif vers Tuilage, puis résultat capturé. Le rendu installé des règles a aussi
été observé. Les captures montrent les valeurs utilisateur conservées.
CUA indisponible ; l'injection terminal seule n'est pas utilisable. Les actions
natives BTT fonctionnent. La position de la souris a été relue avant les clics.
Le contrôle d'ouverture d'aide n'a pas pu être attesté : changement concurrent de
catégorie, puis fermeture de la fenêtre. Aucun clic après disparition de celle-ci.
L'ouverture initiale a nécessité d'attendre l'apparition effective du panneau
après la validation de la commande ; une capture trop précoce n'était pas un échec
de commande. Aucun réglage macOS ni autorisation utilisateur n'a été changé.
Après le complément, la barre de recherche a été annulée avant apparition des
paramètres. Le journal confirme target_search_cancelled. Un contrôle de saisie
séparé montre la commande complète /settings selecteur avant validation ; la
barre a ensuite disparu. La dernière capture des onglets installés n'est donc
pas attestée. Les captures de test montrent bien les deux rangées à police 32.

Preuves incomplètes : parcours intégral des aides et dépliage des règles non
enregistré. Les tests natifs complètent les captures sans remplacer ce parcours.
Diaporama : preuves-corrections/2026-10-23-parametres-058/preuves.html.
Captures originales, manifeste et traces de clics conservés hors Git dans le
dossier local de diagnostics 2026-10-23-session058. Aucun événement navigateur
isTrusted ni curseur supposé n'a été fabriqué pour ces clics natifs.

## Livraison
README FR/EN, guides et changelog Non publié mis à jour. Aucun changement de
version ni nouvelle release. Intégration et nettoyage à consigner après revue.
