# Spécification 080 - Stages enregistrées et rouvertes comme des projets

Demande du 25 octobre 2026 (`/my.specify-all 075 a 082`), idée E validée : « Enregistrer cette
stage » retient ses applications, documents, adresses et sa disposition ; elle se rouvre telle
quelle, même après un redémarrage. Fonction phare, sans équivalent dans Alfred.

## Demande reformulée
Une stage nommée devient un projet : ses fenêtres (application, document ou adresse quand
l'application les expose) et la forme de sa disposition sont gardées. Rouvrir le projet, depuis
la barre ou la commande `roadie project open NOM`, montre la stage si elle vit encore ; sinon la
recrée sur le bureau affiché, rouvre chaque fenêtre dans l'ordre et remet la disposition.

## Dépendances
SPEC-067 (noms uniques), SPEC-017 (arbre), SPEC-074/077/079 (verbes, document des fenêtres,
placement des nouvelles fenêtres, noms réels).

## Exigences
- **FR-001 Enregistrer.** Verbe « Enregistrer comme projet » d'une stage nommée dans la barre, et
  `roadie project save [NOM]` (défaut : stage active). Pour chaque fenêtre vivante de la stage :
  application (identifiant et chemin), document (fichier) ou adresse web s'ils sont lus, titre.
  La disposition (arbre) est gardée par rang des fenêtres. Une stage anonyme est refusée.
- **FR-002 Rouvrir.** Stage du même nom avec des fenêtres vivantes : Roadie y va. Sinon la stage
  (existante vide, ou créée sur le bureau affiché de l'écran actif) s'affiche, puis chaque
  fenêtre s'ouvre à son tour : document ou adresse avec son application, sinon une nouvelle
  fenêtre de l'application ; chaque nouvelle fenêtre rejoint la stage (10 s au plus chacune).
  Si toutes sont revenues, la disposition gardée est remise.
- **FR-003 Barre.** Section « Projets » (nom, nombre de fenêtres) ; Retour rouvre ; verbes :
  Rouvrir, Supprimer le projet.
- **FR-004 Commandes.** `roadie project save [NOM] | open NOM | list [--json] | delete NOM`.
- **FR-005 Stockage.** `~/.roadies/projects.json`, local ; un même nom remplace le projet.

## Critères de réussite
- Tests : capture d'une stage à deux fenêtres (document, adresse, application seule) et arbre
  par rangs ; arbre remis sur les nouvelles fenêtres dans le même ordre.
- Réel : enregistrer une stage de deux fenêtres, les fermer, rouvrir : deux fenêtres dans la
  stage, côte à côte comme avant.

## Hors périmètre
Contenu interne des applications (onglets de Firefox, position dans un document) ; projets sur
plusieurs stages ou bureaux.
