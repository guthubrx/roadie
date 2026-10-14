# Implémentation - session 028

Statut : clôturée, installée et validée par l’utilisateur.

## Première passe, avant corrections de revue

- 73 tests ciblés dans 6 suites passent.
- 1 456 tests Swift dans 156 suites passent en 6,255 s.
- 26 tests des scripts passent en 23,021 s.
- Santé de la version installée avant remplacement : quatre contrôles OK ;
  daemon PID 85924, autorisation Accessibility présente.

Après correction de la revue, la même fixture exécutée avec l’ancienne logique
échoue : cinq tests sur huit, douze assertions. « draft » ne trouve pas Drafts et
le parcours complet de 364 éléments fait 2 428 appels AX simulés. Avec la logique
corrigée, la suite complète passe : **1 458 tests Swift, 156 suites, 6,640 s**.
La même fixture fait **1 472 appels**, soit **956 appels et 39,4 % de moins**.
Ce compteur inclut rôle, enfants, métadonnées et deux appels par lecture de cadre.
Il ne mesure pas le temps d’Outlook réel.

Journaux de vérification : `/private/tmp/roadie-028-baseline-tests.log`,
`/private/tmp/roadie-028-final-tests.log` et
`/private/tmp/roadie-028-script-tests.log`.

## Revue 028-1 et décisions

La fermeture ne présente pas de défaut bloquant relevé. Le clic est transmis et
le Retour différé annulé avant la fermeture. Les callbacks de chargement anciens
vérifient déjà que la session reste ouverte.

La fixture hors écran couvre les cellules et textes descendants et compte tous
les appels AX simulés. Les cadres des textes natifs hors fenêtre sont lus avant
leurs métadonnées, sans supprimer un descendant qui pourrait être visible.
Le comportement web des attributs vides est conservé. Les lignes de message sont
centralisées pour que dessin et zone de clic utilisent le même contenu.

Le texte visible propre à un contrôle natif est recherchable, comme celui d’une
cible web. Cela inclut son contenu utile, pas seulement un nom de dossier. Les
grands conteneurs ne reçoivent pas tous les textes de la fenêtre ; les contrôles
imbriqués gardent leur propre texte. Aucun nouveau stockage de contenu d’Outlook.

La fixture avec un enfant visible d’un parent hors écran est volontaire : elle
protège la descente existante. Une seconde fixture avec des frères couvre le
cas usuel. La pile préexistante reste locale ; pas de refactor structurel.

## Essai utilisateur confirmé

L’utilisateur a répondu « Oui, tout fonctionne » aux trois points : la recherche
« draft » trouve Drafts dans Outlook ; un clic extérieur ferme la barre et agit
normalement, y compris sur un autre écran ; un clic dans la barre ou ses
suggestions la garde ouverte, aussi en mode commande.

La revue finale 028-2 ne relève aucun défaut bloquant. L’essai réel demandé est
confirmé. La fermeture synchrone dans le tap est conservée : le
Retour différé doit être annulé avant le prochain timer, et la variable locale du
callback garde la session vivante pendant le retrait de sa source. Le daemon
PID 56325 reste sain après l’essai : les quatre contrôles sont OK.

Le dernier scan Outlook observé après installation est complet : 242 éléments
parcourus, 120 candidats et 649 ms. Un scan précédent atteint encore le délai de
deux secondes. Les fenêtres et contenus ayant changé entre les essais, ces
mesures ne constituent pas un gain de temps avant/après comparable. La recherche
reste bornée par son budget ; la validation de Drafts repose sur l’essai réel.

## Installation vérifiée

Application : `/Users/moi/Applications/Roadie.app` ; CLI :
`/Users/moi/.local/bin/roadie`. Installation optimisée et redémarrage effectués.
Le daemon PID 56325 remplace le PID 85924. Les quatre contrôles de santé sont OK,
dont Accessibility, configuration valide et audit de l’état.

La signature vérifiée utilise toujours le certificat `roadied-cert`, empreinte
`78a75e8032f190a20072eb91cc2919aac344ef78`. Le SHA-256 de
`/Users/moi/.config/roadies/roadies.toml` est identique avant et après installation.
La version publiée et ses fichiers ne sont pas modifiés.

Journaux : `/private/tmp/roadie-028-install.log`,
`/private/tmp/roadie-028-restart.log`, `/private/tmp/roadie-028-after-health.json`.
