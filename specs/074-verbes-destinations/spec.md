# Session 074 - Lanceur : verbes et destinations (lot 2 de SPEC-073)

Demande du 25 octobre 2026 : corriger Maj + étiquette, puis mettre en place les verbes
et les destinations. Variantes (⌘/⌥ Retour) et sélection multiple : expliquées, non
réalisées dans cette session.

## Comportement
- Tab sur une ligne : verbes de l'objet, verbe par défaut en premier. Verbe à « … » :
  Tab ou Retour mène aux destinations. Échap ou effacement dans un champ vide : retour.
- Taper un nom à l'étape des verbes montre directement les destinations du verbe
  principal (ouvrir dans, envoyer vers, déplacer vers) : objet, Tab, nom, Retour.
- « Nouvelle stage » : nommée d'après la saisie si le nom est libre (SPEC-067), créée dans
  le bureau affiché de l'écran actif.
- Ouvrir dans une stage (F5) : ⌘N si l'application a déjà des fenêtres, sinon ouverture
  par macOS ; la première nouvelle fenêtre du paquet en 10 s rejoint la stage, puis Roadie
  y va. Sans nouvelle fenêtre : rien n'est déplacé.
- Envoyer vers et Déplacer vers ne changent pas la stage affichée ; Ouvrir dans et
  Réunir dans y vont.

## Correctif
Maj + lettre arrivait au champ natif (SPEC-038) comme une majuscule : il est intercepté
comme étiquette quand des étiquettes sont affichées, jamais en mode commande.
