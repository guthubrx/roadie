# Spécification 082 - Documents et onglets dans la recherche

Demande du 25 octobre 2026 (`/my.specify-all 075 a 082`), idée D validée : chercher dans tout ce
qui est ouvert, même caché : noms des documents, onglets et adresses des navigateurs, dans toutes
les stages ; Retour y va et sélectionne le bon onglet.

## Demande reformulée
Taper `facture` trouve aussi le PDF ouvert dans Aperçu d'une stage cachée et l'onglet Chrome « Facture
EDF » d'un autre bureau. Une section « Documents et onglets » les montre avec l'application, la
stage et le bureau ; Retour affiche la stage, met la fenêtre devant et, pour un onglet, le
sélectionne.

## Dépendances
SPEC-077 (lecture du document des fenêtres, relevé), SPEC-073/076 (liste, classement).

## Exigences
- **FR-001 Documents.** À l'ouverture de la barre, en tâche de fond, le document (fichier) ou la
  page web de chaque fenêtre gérée est lu une fois. Ligne : nom du fichier ou titre de la fenêtre
  pour une page ; détail : application, dossier ou adresse, stage.
- **FR-002 Onglets.** Navigateurs ouverts qui le permettent (Chrome, Brave, Edge, Safari) : la liste
  de leurs onglets (titre, adresse) est lue par AppleScript, 2 s au plus par navigateur. Firefox ne
  l'expose pas : non couvert, sans erreur.
- **FR-003 Recherche.** Les lignes correspondent au nom, au titre ou à l'adresse ; 5 au plus,
  après Fenêtres.
- **FR-004 Aller.** Document : la fenêtre passe devant, dans sa stage et son bureau. Onglet : la
  fenêtre du navigateur (retrouvée par son cadre) passe devant et l'onglet est sélectionné.
- **FR-005 Vie privée.** Titres et adresses restent en mémoire pendant la barre ; rien n'est
  journalisé ni écrit.

## Critères de réussite
- Tests : lecture du résultat d'AppleScript, correspondance fenêtre par cadre, recherche par
  adresse et par titre, ligne de document.
- Réel : un document TextEdit d'une stage cachée trouvé et rejoint par la recherche (relevé des
  lignes produites).

## Hors périmètre
Texte des pages ; onglets de Firefox ; onglets des fenêtres d'applications Electron.
