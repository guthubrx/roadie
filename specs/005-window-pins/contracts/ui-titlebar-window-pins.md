# Contrat : interface du menu de pins

## Point d'entrée

Les actions de pin sont exposées dans le menu Roadie existant déclenché par clic droit dans la barre de titre.

## Structure attendue

```text
Roadie
├── Fenêtre
│   ├── Pin sur ce desktop
│   ├── Pin sur tous les desktops
│   └── Retirer le pin              # visible seulement si fenêtre déjà pinée
├── Envoyer la fenêtre vers stage
├── Envoyer la fenêtre vers desktop
└── Envoyer la fenêtre vers écran
```

## États de menu

- Fenêtre non pinée : afficher les actions de pin disponibles.
- Fenêtre pinée `desktop` : indiquer l'état courant et proposer `Retirer le pin` ainsi que le changement vers `Pin sur tous les desktops`.
- Fenêtre pinée `all_desktops` : indiquer l'état courant et proposer `Retirer le pin` ainsi que le changement vers `Pin sur ce desktop`.
- Fenêtre non éligible : ne pas afficher le menu Roadie, conformément au comportement existant du menu de barre de titre.

## Non-interférence

- Le menu ne doit pas apparaître dans le contenu applicatif.
- Le menu ne doit pas apparaître sur les popups, sheets, dialogues et panneaux système.
- Choisir une action de pin ne doit pas changer la stage active ni le desktop actif.
- Choisir une action de pin ne doit pas déclencher une réorganisation des fenêtres non pinées.
