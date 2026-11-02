# Plan 150

1. Sauvegarder la configuration BTT par lecture seule ; réutiliser le dossier global de fenêtres Roadie.
2. Résoudre directement la stage sous le pointeur dans launch --here --mouse. Lire seulement les écrans (aucun relevé AX pour la géométrie). Refuser si aucun écran/scope ne correspond. Utiliser le bureau affiché, même si la stage est vide et le focus sur l’autre écran.
3. Sans fenêtre existante, ouvrir en conservant cette destination via openWindow et placeNewWindow existants. Sinon réutiliser bringHere. Ne plus changer le focus d’écran avant de choisir la destination.
4. Configurer un seul ⌘E global actif par API BTT, lire son résultat, tester les parcours natifs et vérifier santé/configuration.
5. Documenter, soumettre une revue indépendante, publier et nettoyer les temporaires. Conserver les limites des preuves clavier.

## Diagnostic mesuré
Un premier adaptateur JXA a sélectionné l’écran puis appelé display focus et launch --here. Les journaux montrent display_focus écran2 focused=false suivi d’un launcher.brought vers l’écran1 (12h44m53UTC). Le relevé de focus peut remettre l’écran précédent entre les deux commandes, notamment sans fenêtre à activer à destination. Cet adaptateur n’est pas livré ; la destination native explicite le remplace.
