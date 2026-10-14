# Contre-revue du plan — passage 2

**Décision :** BLOCK ciblé, traité le 2026-10-14.

## Objections retenues

- Un événement AX peut aussi arriver pendant `Cmd-Q`. Supprimer le membre
  casserait alors le rattachement SPEC-016 après relance.
- Les reprises bornées doivent être autorisées explicitement par la spec.
- Le compteur doit être par ID et alimenté seulement par le writer.
- Plusieurs textes conservaient l'ancienne cible et l'ancienne portée.

## Réponses

- Le membre persistant n'est plus supprimé. Il reçoit `confirmedClosedAt`.
  Le navrail le masque, mais SPEC-016 peut encore le remapper après relance.
- FR-008 et SC-006 interdisent seulement les boucles permanentes ou non bornées.
- FR-015 autorise dix reprises à 50 ms par fermeture.
- Seuls les snapshots écrivains incrémentent le compteur par ID.
- Une notification répétée ne rafraîchit ni la date ni le compteur.
- La fenêtre revue ou remappée efface le marqueur visuel.
