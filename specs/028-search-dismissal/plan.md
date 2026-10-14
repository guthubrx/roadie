# Plan — session 028

Swift, AppKit, Accessibility ; Swift Testing. Réutiliser AppTargetQueryService,
TargetSearchSession, SearchBarLayout et RoadieScreenCoordinate.

## Répartition

- Collecte : AppTargetQueryService et tests de cibles natifs. Vérifier la cause
  avant correction ; préserver identifiants, registre AX et point d’activation.
- Fermeture : TargetOverlayPresenter, SearchBarRenderer et tests de fermeture.
  Utiliser les cadres réels de la barre et du panneau, pas la fenêtre plein écran.
- Intégration : artefacts, tests centralisés, documentation et installation.

Aucun agent ne compile ni ne commite. Les éditions s’arrêtent avant toute
compilation commune. Les deux parties ne modifient pas les mêmes fichiers.

## Choix

Collecte linéaire bornée par le budget existant ; enrichir les contrôles précis
sans absorber tout le texte d’une fenêtre. Observer les clics sans les consommer.
Nettoyer les observateurs dans le chemin de fermeture déjà idempotent.

## Vérification

Reproductions ciblées avant correction ; tests ciblés puis suite Swift complète ;
tests de scripts si requis par installation ; santé après redémarrage ; essai
manuel sur la version installée. Le diagnostic AX via CLI est local et peut être
refusé alors que le daemon possède l’autorisation ; ne pas confondre les deux.
