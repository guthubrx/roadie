# 39.roadies — Stage Manager

Outil CLI macOS suckless pour basculer la visibilite de groupes de fenetres ("stages") via les API Accessibility. Mono-fichier Swift, zero dependance externe.

## Resume en 5 lignes

- 2 stages prealablement configures via `stage assign 1` et `stage assign 2`
- Bascule entre eux par `stage 1` ou `stage 2` (les fenetres de l'autre stage sont minimisees)
- Etat persistant en texte plat dans `~/.stage/`, editable a la main
- Identifiant fenetre stable (`CGWindowID`), survit aux changements de titre
- Build : `make` puis `make install` (dans `~/.local/bin/`)

## Documentation complete

- [Quickstart : install + premier usage](specs/001-stage-manager/quickstart.md)
- [Specification fonctionnelle](specs/001-stage-manager/spec.md)
- [Plan technique](specs/001-stage-manager/plan.md)
- [Recherche & decisions](specs/001-stage-manager/research.md)
- [Modele de donnees](specs/001-stage-manager/data-model.md)
- [Contrat CLI](specs/001-stage-manager/contracts/cli-contract.md)

## Build minimal

```bash
make           # compile vers ./stage (binaire universel)
make install   # installe dans ~/.local/bin/stage
make test      # execute les tests d'acceptation shell
make clean     # supprime le binaire
```

Permission Accessibility requise — le binaire vous indique exactement comment l'accorder au premier lancement.
