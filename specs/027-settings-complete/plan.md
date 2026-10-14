# Plan — session 027

Réutiliser SettingsService et ses garanties d'écriture, le catalogue, les modèles
SwiftUI, ConfigReloadService, TickScheduler et les notifications de la session 025.
Utiliser TOMLKit déjà présent pour lire les valeurs structurées ; ne pas introduire
une autre bibliothèque ni réécrire tout le fichier avec ses défauts.

## Répartition et interfaces

1. Configuration : types de collections, schémas, catalogue, service et éditeur de
   fichier. Publier rapidement le contrat typé des valeurs pour les éditeurs.
2. Fenêtre : saisie immédiate, éditeurs structurés et éditeur avancé intégré.
   Consommer le contrat du service ; conserver les brouillons pendant l'édition.
3. Application : relier les écritures validées à l'ordonnanceur du tuilage et
   vérifier les composants qui gardent leur configuration en mémoire.
4. Polices : configuration, rendu Caps+F et sélecteur des familles installées.

Chaque partie possède ses fichiers. Les compilations sont centralisées : aucun
fichier source n'est modifié pendant une compilation Swift active. Une modification
de structure publique de configuration peut nécessiter une reconstruction propre.

## Contrat à fixer après l'inventaire technique

Le service expose des valeurs structurées typées et un point d'écriture validé.
L'interface manipule listes et lignes ; elle n'écrit pas de fragments TOML à la main
pour les réglages courants. Les champs inconnus d'une ligne sont conservés.
Les écritures publient le chemin et l'identifiant du réglage modifié. Le tuilage
filtre les identifiants concernés et regroupe les demandes via son ordonnanceur.

L'éditeur avancé accepte un fragment de la structure complexe ou une correction
complète du fichier invalide, avec prévalidation et détection de conflit.
Les familles de police utilisent des champs texte dans le modèle pur ; le sélecteur
AppKit connaît les familles installées. Défaut `system`, secours système explicite.

## Étapes de validation

Reproduire la saisie de marge ignorée ; tester chaque contrat ; intégrer les quatre
parties ; revue indépendante et corrections ; suite Swift complète ; rendus réels
hors écran ; installation signée, redémarrage, santé ; validation utilisateur et Git.
