# Spécification 078 - Fantômes actifs : les vraies fenêtres font la place

Demande du 25 octobre 2026 (`/my.specify-all 075 a 082`), idée G, option 2 choisie par
l'utilisateur : « les fantômes soient actifs, c'est-à-dire qu'ils déplacent le layout ; s'il y a
une fenêtre qui va s'ouvrir, je vois où elle va s'ouvrir et le reste des fenêtres se déplace ».

## Demande reformulée
Pendant le choix d'une stage de destination dans la barre (Tab, puis une stage), les vraies
fenêtres de cette stage prennent leur future place ; la fenêtre qui arrive y est aussi (si elle
existe déjà) ou un fantôme marque sa place (si elle va s'ouvrir). Une stage cachée du même bureau
s'affiche pendant le choix. Échap, une autre destination ou la fermeture de la barre remettent
tout comme avant ; Retour garde la disposition et fait l'action.

## Dépendances
SPEC-017 (arbre BSP, réconciliation), SPEC-062 (pause de la disposition), SPEC-068 (refus de
taille), SPEC-074/075/077 (destinations, variantes, fichiers).

## Exigences
- **FR-001 Déclenchement.** 150 ms après que la ligne choisie se pose sur une destination de type
  stage d'un verbe Ouvrir dans, Envoyer vers ou Amener ici (application, fichier, fenêtre).
  Changer de ligne annule l'aperçu précédent avant le suivant.
- **FR-002 Disposition future.** Calculée comme la réconciliation l'insérerait : même ancre
  (focus), même côté (`new_window_side`), même moteur que la stage (arbre ou non).
- **FR-003 Vraies fenêtres.** Les fenêtres de la stage, et la fenêtre envoyée si elle existe,
  sont écrites à leur future place ; la disposition automatique est suspendue pendant l'aperçu
  (au plus 1,5 s sans renouvellement, filet si la barre disparaît).
- **FR-004 Fantôme.** La fenêtre à ouvrir (application, fichier) est un rectangle translucide en
  couleur d'accent avec l'icône de l'application, à sa future place.
- **FR-005 Stage cachée.** Une stage du bureau affiché qui n'est pas la stage active s'affiche
  pendant l'aperçu ; Échap revient à la stage de départ. Autre bureau : pas d'aperçu.
- **FR-006 Annulation.** Échap, retour d'étape, autre destination ou fermeture : chaque fenêtre
  revient au cadre relevé avant l'aperçu, puis la disposition reprend.
- **FR-007 Validation.** Retour : la disposition reste, l'aperçu se termine sans restauration,
  l'action s'exécute, la disposition reprend.

## Critères de réussite
- Test : la disposition future d'une stage à deux fenêtres côte à côte avec une fenêtre de plus
  donne trois cadres disjoints dans le cadre visible, le fantôme à côté de la fenêtre active.
- Échap après aperçu : cadres relevés identiques à ceux d'avant (tolérance 2 points).
- Aucune oscillation : une fenêtre qui refuse une taille garde la taille acceptée (registre 068).

## Hors périmètre
Aperçu vers un autre bureau ou un autre écran non affiché, vers « Nouvelle stage », pour
« Réunir ses fenêtres » (plusieurs fenêtres).
