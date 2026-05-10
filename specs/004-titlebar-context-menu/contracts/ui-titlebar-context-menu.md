# Contrat : interface du menu contextuel de barre de titre

## Déclenchement

Le menu Roadie peut apparaitre seulement si toutes les conditions suivantes sont vraies :

1. `experimental.titlebar_context_menu.enabled = true`.
2. Le clic est un clic droit.
3. Le point clique appartient a une fenetre connue.
4. La fenetre est eligible selon les reglages.
5. Le point est dans la bande haute configuree.
6. Le point n'est pas dans les marges d'exclusion gauche/droite.
7. Au moins une destination utile existe.

Si une condition echoue, Roadie ne consomme pas le clic.

## Menu

Structure attendue :

```text
Roadie
├── Envoyer vers stage
│   ├── Stage 1 / Nom
│   └── Stage 2 / Nom
├── Envoyer vers desktop
│   ├── Desktop 1 / Label
│   └── Desktop 2 / Label
└── Envoyer vers ecran
    ├── Ecran 1 / Nom
    └── Ecran 2 / Nom
```

## Filtrage des Destinations

- La destination courante est absente ou desactivee.
- Les destinations indisponibles ne doivent pas executer d'action.
- Les sous-menus vides ne doivent pas etre affiches.

## Non-Interférence

- Un clic droit dans le contenu applicatif doit rester disponible pour l'application.
- Un clic droit sur popup/dialogue/transient doit rester disponible pour l'application ou le systeme.
- Le menu ne doit pas changer le focus avant que l'utilisateur choisisse une action.
