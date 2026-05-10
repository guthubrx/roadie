# Recherche : Menu Contextuel de Barre de Titre

## Décision 1 : section TOML experimentale dediee

**Décision** : exposer la fonctionnalite sous `[experimental.titlebar_context_menu]`, avec `enabled = false` par defaut.

**Justification** : la detection de barre de titre est heuristique et depend fortement des applications. Le namespace experimental rend le risque explicite et permet de desactiver la fonctionnalite sans impacter le reste de Roadie.

**Alternatives étudiées** :

- Ajouter les reglages dans `[focus]` : rejete, car le comportement concerne une interaction contextuelle et non la politique de focus.
- Activer par defaut : rejete, car le risque d'intercepter un clic droit applicatif est plus couteux que le benefice de decouvrabilite.

## Décision 2 : detection conservative par bande haute configurable

**Décision** : considerer eligible uniquement une bande haute de fenetre configurable, avec marges d'exclusion gauche/droite et restriction aux fenetres gerees par Roadie.

**Justification** : macOS ne donne pas une definition uniforme de "barre de titre" pour toutes les apps modernes. Une bande haute configurable donne un comportement comprehensible, testable et ajustable.

**Alternatives étudiées** :

- Detecter les elements AX exacts de titlebar : interessant mais incomplet selon les apps, et plus fragile pour Electron/SwiftUI/toolbars fusionnees.
- Intercepter tout clic droit sur la fenetre : rejete, car cela casserait les menus contextuels internes.

## Décision 3 : fail-open pour proteger les applications

**Décision** : si le point clique, la fenetre cible, le type de fenetre ou la destination sont ambigus, Roadie ne consomme pas le clic et ne montre pas de menu.

**Justification** : l'objectif prioritaire est de ne pas interferer avec les applications. Un menu Roadie absent est acceptable ; un menu Roadie qui remplace un menu applicatif attendu ne l'est pas.

**Alternatives étudiées** :

- Toujours afficher un menu Roadie puis proposer "Annuler" : rejete, car l'utilisateur perdrait le menu applicatif attendu.
- Journaliser uniquement les cas ambigus sans changer le comportement : conserve comme diagnostic, mais ne remplace pas la regle fail-open.

## Décision 4 : menu Roadie separe du menu natif

**Décision** : afficher un menu Roadie propre quand les conditions sont reunies, sans modifier ni injecter d'entrees dans les menus natifs des applications.

**Justification** : les menus natifs appartiennent aux applications et leur injection serait instable, intrusive et difficile a rendre universelle sans hacks.

**Alternatives étudiées** :

- Modifier le menu de barre de titre macOS : rejete, pas assez stable ni universel.
- Ajouter seulement un raccourci clavier : plus simple, mais ne repond pas au besoin de clic droit sur la barre haute.

## Décision 5 : reutiliser les services de commande existants

**Décision** : les actions du menu doivent appeler les services Roadie existants pour stage, desktop et display, avec des adaptateurs ciblant une fenetre explicite si necessaire.

**Justification** : Roadie possede deja les primitives de deplacement. La fonctionnalite doit etre une couche d'interaction, pas une nouvelle logique d'etat.

**Alternatives étudiées** :

- Reimplementer les mutations dans le controleur de menu : rejete, car cela dupliquerait la logique et augmenterait les risques sur stages/desktops.
- Activer/focus la fenetre puis appeler les commandes active-window : possible mais fragile, car cela ajoute des changements de focus non demandes.
