# Validation 091

## Tests
- `Spec091SelectionTests` (4) : ajout, retrait, doublon, stage refusée, dernière retirée, vidage ;
  verbes du lot et leur nombre, filtrage par la saisie, titres ; actions (fenêtres envoyées,
  application et fichier ouverts dans une nouvelle stage, rien vers un bureau pour eux) ; verbe de
  destination selon le lot ; touches ⌥↑ ⌥↓ ⌥← ⌥→ ⌥⌫ et flèches sans ⌥ inchangées ; annulation d'un
  lot (fenêtre repartie ailleurs exclue, déplacement seul comme avant).
- `Spec038NativeInputTests` adapté : ⌥ seul est pris par la sélection ; ⌥⇧, ⇧ et ⌘ + flèches restent
  au champ (décision research R1).
- Suite complète : 2 085 tests / 291 suites réussis.

## Installation
PID 52635, santé 5/5, signature conservée.

## Limites
- Lot non essayé au clavier ni sur de vraies fenêtres (il déplacerait les fenêtres de l'utilisateur) :
  essai proposé (quickstart).
- Applications et fichiers d'un lot : une fenêtre neuve attendue 10 s chacune, sans aperçu actif.
- ⌥ + flèches ne déplace plus le curseur par mot dans la barre.
- Contre-revue Bridget : refusée (`project_mapping_unknown`).

## Correction du 27 octobre 2026
- ⌥ + flèches et ⌥⌫ ne servent à la sélection que si elle peut servir (`SelectionKeys`, research R1) ;
  sinon le curseur se déplace par mot, par exemple dans `=sqrt(2)+3`.
- Tests : `optionKeysDriveTheSelection` couvre les trois cas ; suite complète 2 086 tests / 292 suites.
  Installé : PID 60525, santé 5/5, certificat `roadied-cert` conservé.
- Non vérifié : frappe réelle dans la barre (essai utilisateur).
