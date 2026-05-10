# Contrat : événements du menu contextuel de barre de titre

## Types d'événements

| Événement | Déclenchement |
|-------|------|
| `titlebar_context_menu.shown` | Menu affiche pour une fenetre eligible |
| `titlebar_context_menu.ignored` | Clic droit ignore pour une raison diagnostique |
| `titlebar_context_menu.action` | Action utilisateur selectionnee |
| `titlebar_context_menu.failed` | Action selectionnee mais non appliquee |

## Détails communs

```json
{
  "windowID": "12345",
  "reason": "eligible",
  "bundleID": "com.example.App",
  "title": "Window title"
}
```

## Détails d'action

```json
{
  "windowID": "12345",
  "kind": "stage",
  "targetID": "2",
  "result": "changed"
}
```

## Règles

- Les evenements `ignored` doivent rester peu bruyants : Roadie journalise au plus un `ignored` par couple `(windowID, reason)` sur une fenetre de 2 secondes, sauf si `windowID` est absent.
- Les raisons triviales `disabled` et `not_titlebar` ne doivent etre journalisees qu'en mode diagnostic explicite afin d'eviter un log par clic droit applicatif.
- Les raisons utiles au diagnostic (`no_window`, `not_managed`, `transient`, `excluded_margin`, `no_destination`) peuvent etre journalisees avec la limitation temporelle ci-dessus.
- Les actions echouees doivent indiquer la cause : fenetre disparue, destination disparue, cible courante, action indisponible.
