# Validation 046

## Comportement attendu

Le constructeur, le décodeur TOML, le défaut proposé par les paramètres et le
fichier exemple utilisent focused_display. Les préférences explicites mouse et
macos restent respectées. Rétablir revient à focused_display. Sans écran actif
connu, l'écran contenant la fenêtre prime sur le premier écran de la liste.

Le panneau Tuilage propose « Écran des nouvelles fenêtres », avec « Écran actif
(recommandé) », « Écran de la souris » et « Choix de macOS ». L'aide explique que
la nouvelle fenêtre rejoint le stage courant de l'écran actif malgré la souris
ailleurs. Aucun délai interne ni algorithme de tuilage n'a changé.

## Tests et revue

Suite complète : 1 696 tests dans 199 suites réussis. Chargement sans table ou sans
clé, valeur invalide, trois choix explicites, libellés avec valeurs brutes
conservées, rétablissement puis réouverture des paramètres et deux écrans testés.

La première passe a révélé le mauvais repli sans écran actif : corrigé et couvert
par le test existant de placement sans focus. Deux fixtures d'attente AX (034 et
037) demandent maintenant macos explicitement, car elles vérifient des fenêtres
sur leurs écrans initiaux ; leurs attentes et protections ne sont pas modifiées.
Le nouveau test ViewModel sélectionne Tuilage avant lecture du cache visible.
Un test existant de signal distribué a dépassé son attente sous charge ; il passe
isolément puis la suite complète passe, sans modification de son délai ni de son code.

Revue indépendante en lecture seule : aucun défaut bloquant. Le relecteur n'a
pas exécuté de diff, build ou test, faute de shell. Notes prises en compte :
changement de défaut classé dans « Changements », choix explicites conservés,
valeurs exactes et repli sur valeur invalide documentés. Pas de refonte pour les
remarques de ponctuation ; les conventions existantes du projet sont conservées.

## Essai réel de référence

Le 18 octobre 2026 à 15:07:21 et 15:07:22 UTC, deux ouvertures par ⌘N dans iTerm2
ont rejoint le même écran et le même stage que le terminal actif, malgré la souris
sur l'autre écran. L'utilisateur confirme : « Même stage, intégration rapide ».
Les deux placements ont réussi sans échec ; les durées de traitement étaient
106,4 et 83,5 ms. Ces valeurs ne mesurent pas la latence depuis la frappe.

Cet essai précède le changement de défaut : il vérifie le mécanisme existant avec
la même valeur focused_display. Aucun nouveau gain de vitesse n'est revendiqué.
Traces hors Git : /Users/moi/.roadies/diagnostics/2026-10-18-ouverture-fenetres/.

## Installation et limites

Compilation Release réussie. UUID compilé et installé identique :
4203C4C0-E22C-3F80-BC7E-4A624E9C0A13. Application installée :
/Users/moi/Applications/Roadie.app. Vérification de signature stricte réussie,
certificat 78a75e8032f190a20072eb91cc2919aac344ef78 conservé.
Redémarrage vérifié, PID 76046, quatre contrôles santé OK après initialisation.

La CLI installée confirme focused_display avec un fichier sans préférence et
macos avec un choix explicite. Configuration réelle inchangée, SHA-256 :
ca42b5c670755e1b39371b1157c116c31e0754930800ad2551841fe5a3f05629.
Les 293 empreintes Sources/Tests sont inchangées depuis la suite verte.
Diagnostics de compilation, revue et tests :
/Users/moi/.roadies/diagnostics/2026-10-18-session046/.

Preuves visuelles incomplètes : bureau inaccessible. Le nouveau texte du panneau
est vérifié dans le catalogue et ses tests, sans capture d'écran ni diaporama.
