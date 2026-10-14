# Contre-revue ciblée — passage 3

**Décision :** APPROVE le 2026-10-14.

Aucune objection bloquante. La revue confirme la cohérence du marqueur
`confirmedClosedAt`, des reprises bornées, du compteur écrivain par ID, de la
cible p95 à 400 ms et du maintien de SPEC-016.

Trois précisions non bloquantes ont été intégrées avant le code :

- le format persistant change par un champ optionnel rétrocompatible ;
- `missingSince` reste renseigné pour conserver le remappage et la purge ;
- la purge existante garde seule la responsabilité de la durée de vie du membre.
