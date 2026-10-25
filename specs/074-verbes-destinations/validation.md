# Validation 074

- `Spec074VerbsTests` : verbes par objet, destinations directes, nouvelle stage nommée ou
  anonyme, stage d'origine exclue, destinations d'un bureau, liste des destinations,
  création unique d'une stage.
- `Spec038NativeInputTests` : Maj + lettre devient une étiquette seulement si les
  étiquettes sont affichées.
- Rendu natif de l'étape des verbes vérifié sur données fictives.
- Limites : « Nouvelle fenêtre » repose sur ⌘N, que certaines applications n'utilisent
  pas ; l'intention de placement retient la première fenêtre nouvelle du paquet, y compris
  une fenêtre ouverte par l'utilisateur dans le même délai.
- Liste à la manière d'Alfred (`31d5ca3b`, `159e71e2`) : icône à deux fois la hauteur du nom,
  nom en graisse normale, fenêtres avec l'icône de leur application, symboles sur tuile,
  lien Safari résolu sans flèche d'alias. `Spec073RichLayoutTests` (défilement, proportions).
  1 976 tests réussis, installation signée roadied-cert, PID 8781, santé 5/5.
- Référence Alfred et priorités : `docs/analyses/2026-10-25-reference-alfred.html`.
- Preuves : diaporama non produit ; rendu réel contiendrait des fenêtres privées. Rendu
  d'essai sur données fictives vérifié.
