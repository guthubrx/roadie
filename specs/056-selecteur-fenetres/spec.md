# Session 056 - Sélecteur de fenêtres Roadie

Statut : implémenté et installé. Autorisation utilisateur : examiner AltTab gratuit et Pro, puis « on le fait » ; répartition entre agents validée. Limites de validation réelle dans validation.md.

## Usage
Un sélecteur natif ouvre les fenêtres dans leur contexte Roadie sans les réaffecter.
Maintenir les touches, Tab avance, Maj+Tab recule, relâcher valide. Échap annule sans changer le focus ni la disposition.
Le mode persistant permet la recherche puis Retour/clic pour valider. Ordre des fenêtres stable pendant la sélection ; sélection attachée à l'identité, pas au rang.
Une fenêtre d'une autre stage/bureau fait ouvrir son contexte sur son écran. Aucune téléportation implicite. Les stages inactives ne sont pas assimilées aux fenêtres fermées.

## Fonctions de base
- Fenêtres individuelles, plusieurs fenêtres d'une même application, ordre récent global.
- Vignettes avec repli icône/titre, aperçu agrandi sans activer la vraie fenêtre.
- Clavier, clic, navigation inverse, fermeture au clic extérieur, apparence claire/sombre et accessibilité.
- Inclure/exclure fenêtres réduites, applications masquées et plein écran ; exceptions par bundle.
- Actions explicites sur la sélection : fermer, réduire/restaurer, masquer l'application, quitter normalement l'application, maximiser et plein écran Roadie.

## Fonctions avancées
- Recherche par application, titre, nom de stage et bureau, casse/accents ignorés ; classement par correspondance et récence.
- Trois styles : vignettes, icônes, liste compacte. Taille automatique ou largeur manuelle ; taille et famille de police réglables.
- Jusqu'à neuf profils de raccourcis indépendants : touches, filtre (stage/bureau/écran/application/tout), tri, validation au relâchement ou maintien ouvert ; une fenêtre par application optionnelle.
- Réglages intégrés et appliqués sans redémarrage. Commandes CLI show/next/previous/accept/cancel pour outils externes et gestes BTT.

## Choix de livraison
Défaut sans raccourci interne, toutes les fenêtres gérées, style vignettes. Le raccourci externe choisi sur cette installation est Cmd+Tab via BetterTouchTool. AltTab installé et ses raccourcis restent disponibles pour comparaison. Aucun transfert de code ou d'assets GPL dans Roadie ; comportements réimplémentés sur ses services.
Les bureaux/stages Roadie sont prioritaires. La navigation des Spaces natifs macOS et des onglets natifs ne sera pas présentée comme équivalente : Roadie ne possède pas leur gestion complète. Aucun nouvel accès privé SkyLight, aucun moteur de captures parallèle permanent. Les gestes peuvent invoquer la CLI via BTT ; pas de pilote multitouch ajouté.

## Vérification
Tests Swift Testing du filtrage/tri/recherche, sélection stable, annulation et relâchement ; configuration et éditeur ; activation inter-stage/bureau/écran sans réaffectation ; cible fermée/inaccessible, refus AX et erreurs de persistance. Tests ciblés puis suite séquentielle jobs2. Revue indépendante, build/install signé conservé, santé et essai utilisateur. Preuves UI honnêtes si bureau inaccessible.

## Ajustement validé pendant l’essai installé

L’utilisateur demande une grille à côté de l’aperçu, un champ de recherche borné
au panneau, et le déclenchement via BetterTouchTool/CLI. Il remplace Ctrl+Alt+Tab
par Cmd+Tab après avoir quitté AltTab. Le défaut `hotkey` devient vide ; les
raccourcis internes restent facultatifs. `switcher cycle --hold cmd` démarre ou
avance ; `--backwards` inverse ; le relâchement valide. `show` reste persistant.
