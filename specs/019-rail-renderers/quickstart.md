# Quickstart — Changer de rendu du navrail

**Audience** : utilisateur power-user de roadie souhaitant tester ou adopter un rendu alternatif.

## Pré-requis

- roadie installé et `roadied` démarré.
- `roadie-rail` visible (raccourci configuré ou `roadie rail toggle`).

## Lister les rendus disponibles

```bash
roadie rail renderers list
```

Sortie typique (après MVP US1+US2) :
```
* stacked-previews   Stacked previews   (default, current)
  icons-only         Icons only
```

Le `*` marque le rendu actuellement appliqué. Le ratio `(default, current)` indique que c'est aussi le rendu par défaut.

Pour une sortie machine-readable :
```bash
roadie rail renderers list --json
```

## Changer de rendu

Deux méthodes, équivalentes :

### Méthode A — CLI (recommandée)

```bash
roadie rail renderer icons-only
```

Sortie :
```
renderer: stacked-previews → icons-only
reloaded
```

Le rail bascule visuellement en moins d'une seconde.

### Méthode B — édition TOML manuelle

```bash
# Edit ~/.config/roadies/roadies.toml
# Sous la section [fx.rail], ajouter (ou modifier) :
[fx.rail]
renderer = "icons-only"

# Puis :
roadie daemon reload
```

Effet identique.

## Revenir au rendu par défaut

Trois manières équivalentes :

```bash
# A — set explicite
roadie rail renderer stacked-previews

# B — supprimer la clé du TOML, puis reload
# (le défaut sera réappliqué)

# C — éditer le TOML pour mettre la valeur par défaut
[fx.rail]
renderer = "stacked-previews"
roadie daemon reload
```

## Comportement en cas d'erreur

| Situation | Comportement |
|---|---|
| Valeur TOML inconnue (typo) | Warning loggé dans `~/.local/state/roadies/daemon.log`, fallback silencieux sur `stacked-previews` |
| `roadie rail renderer foobar` (id inconnu) | Erreur exit code 5 + message « renderer 'foobar' not found. Available: ... » |
| Daemon arrêté | Erreur exit code 3 + message « daemon not running » |

## Tester pour comparer

Cycle rapide pour décider quel rendu te convient :
```bash
for r in stacked-previews icons-only ; do
    roadie rail renderer "$r"
    echo "Rendu actuel : $r — observe le rail puis Entrée pour passer au suivant"
    read
done
```

## Limitations connues

- Le swap de rendu ne préserve PAS l'animation entre l'ancien et le nouveau rendu (transition brute). C'est un compromis assumé au profit de la simplicité.
- Les rendus disponibles sont **compilés** dans le binaire `roadie-rail`. Pour ajouter un nouveau rendu (ex: « polaroid »), il faut recompiler le projet (cf. SPEC-019 plan.md US3-US5 pour les rendus prévus).

## Références

- [SPEC-019 spec.md](spec.md) — vision et user stories
- [SPEC-019 plan.md](plan.md) — choix techniques
- [SPEC-019 contracts/cli-protocol.md](contracts/cli-protocol.md) — détails CLI
- [SPEC-014 spec.md](../014-stage-rail/spec.md) — le rail lui-même
