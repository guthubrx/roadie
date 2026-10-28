# Session 112 : forme des tuiles des grilles

## Besoin

Reprise d'Alfred : la brique Grille règle l'aspect des images (`imageaspect`). Roadie montrait toujours des
tuiles carrées (limite notée en SPEC-092, research R5).

## Constat

Le menu de la brique Grille d'Alfred 5 (`AlfredWorkflowUserInterfaceGrid.nib`) propose, dans l'ordre :
Square, Portrait, Landscape, avec l'aide « Image aspect is attempted but not guaranteed ». Valeurs relevées :
0 pour System Settings Explorer (icônes), 2 pour Thumbnail Navigation (captures). Décision : 0 carré,
1 portrait (2/3), 2 paysage (3/2) ; une autre valeur donne un carré.

## Règle

- La largeur d'une tuile ne change pas (colonnes du workflow) ; la hauteur de l'image suit l'aspect.
- L'image reste ajustée sans déformation dans sa case.
- Les présentations choisies par ⌘G (session 099) restent carrées.
