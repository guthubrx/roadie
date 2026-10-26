# Spécification 091 - Sélection multiple dans le lanceur

Demande du 26 octobre 2026 (`/my.specify-all 086 a 091`), ligne 091 du tableau validé :
« sélection multiple ». Modèle : le tampon de fichiers d'Alfred (⌥↑, ⌥↓, ⌥←, ⌥→, ⌥⌫), étendu
à ce que Roadie range : applications, fenêtres et fichiers.

## Demande reformulée
Dans Capslock + F, on réunit plusieurs lignes, même trouvées par des saisies différentes, puis
on choisit un seul verbe pour toutes : les envoyer dans une stage, dans une nouvelle stage
(créée une seule fois), sur un bureau ou un écran, les amener ici, les fermer, les quitter.
L'usage visé : « ces trois fenêtres dans une nouvelle stage Dev » en quelques touches.

## Dépendances
SPEC-074 (verbes et destinations), SPEC-077 (fichiers), SPEC-078 (aperçu actif), SPEC-081
(annuler le dernier déplacement).

## Exigences
- **FR-001 Touches.** ⌥↑ ajoute ou retire la ligne choisie ; ⌥↓ l'ajoute et passe à la suivante ;
  ⌥← retire la dernière ajoutée ; ⌥→ ouvre les verbes de la sélection ; ⌥⌫ vide la sélection.
  Seules les applications, fenêtres et fichiers s'ajoutent ; une autre ligne ne fait rien.
- **FR-002 Affichage.** Une ligne sélectionnée porte « ✓ » ; la barre montre « N choisis » dans sa
  capsule. La sélection reste quand la saisie change, pour réunir des objets trouvés séparément.
- **FR-003 Retour.** Avec une sélection, Retour ouvre ses verbes (comme ⌥→), sans agir tout de
  suite. Échap vide d'abord la sélection, puis ferme.
- **FR-004 Verbes de la sélection.** Proposés s'ils valent pour au moins un objet, avec le
  nombre concerné : « Envoyer vers… » (fenêtres envoyées, applications et fichiers ouverts dans
  la destination : stage, nouvelle stage, bureau, écran), « Amener ici », « Fermer les fenêtres »,
  « Réduire les fenêtres », « Quitter les applications », « Masquer les applications »,
  « Copier les chemins », « Montrer dans le Finder ». Saisie à l'étape des verbes : comme 074.
- **FR-005 Exécution.** Un objet après l'autre, dans l'ordre de sélection. Une nouvelle stage est
  créée une fois, puis reçoit tous les objets ; Roadie y va à la fin. Un échec n'arrête pas les
  suivants ; le résultat donne « N sur M ».
- **FR-006 Annuler.** « Annuler » de la barre vide (081) remet toutes les fenêtres du dernier envoi
  groupé dans leur stage d'avant.

## Critères de réussite
- Trois fenêtres choisies par ⌥↓ puis « Envoyer vers… › Nouvelle stage « Dev » » : une seule stage
  Dev contenant les trois, affichée à la fin.
- Sélection gardée en changeant la saisie ; ⌥⌫ la vide ; Échap vide puis ferme.

## Hors périmètre
Sélection à la souris, sélection de stages ou de bureaux, aperçu actif pour plusieurs fenêtres.
