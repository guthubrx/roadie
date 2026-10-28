# Session 118 : vues Image et PDF des workflows

## Besoin

Briques `alfred.workflow.userinterface.image` et `.pdf` (Alfred 5.5) : Thumbnail Navigation (image et PDF)
et Read the Friendly Manual (PDF) dans le corpus.

## Réglages relevés (application Alfred 5, `AlfredWorkflowUserInterfaceImage.nib` et `…PDF.nib`)

- Image `imageresizemode` : 0 automatique (réduite à la fenêtre), 1 ajustée au cadre, 2 sans tenir compte de
  la résolution (pixels réels).
- PDF `displaymode` : 0 automatique, 1 une page, 2 une page continue, 3 deux pages, 4 deux pages continues.
- `stackview` des deux : Échap revient à la vue d'Alfred précédente.

## Règle

- Le fichier est l'argument reçu (première ligne), relatif au dossier du workflow. Absent : notification,
  l'exécution s'arrête (`media:file`).
- Fenêtre d'aperçu (panneau qui n'active pas Roadie mais reçoit le clavier), titre « workflow · fichier ».
  PDF par PDFKit ; « automatique » donne une page continue.
- Retour (avec les touches tenues) ferme et envoie le chemin à la suite du schéma depuis la brique, avec les
  variables reçues. Échap ferme. Journal `launcher.workflow_media` sans chemin.
- Les effets réels d'un workflow sont créés en un seul endroit du démon (barre, commande, vues).

## Limites

- `stackview` non repris : Échap ferme sans rouvrir la barre.
