# Validation 066

## Tests
- `Spec066DesktopReorderTests` : correspondance, renumérotation complète, intentions,
  commande sur état temporaire, espaces d'insertion en Archipel et en Baies.
- Suite complète à la clôture : voir `specs/069-release-090/validation.md`.

## Essais réels
- CLI `roadie desktop move 2 1` puis retour : aucun cadre de fenêtre modifié (immédiat
  et 7 s), santé 5/5, état final identique à la sauvegarde.
- Glisser à la souris fait par l'utilisateur. Premier essai : déplacements faits mais
  affichage non rafraîchi une fois sur deux ; cause : relevé refusé quand l'état des
  stages change pendant la lecture. Corrigé par relecture (jusqu'à 6 essais, 80 ms).
- Deuxième essai : fonctionnel ; demande de viser les espaces entre bureaux, puis trait
  plus fin et plus transparent sans point. Validé par l'utilisateur.

## Limites
- Glisser simulé impossible depuis le terminal (pas d'autorisation Accessibilité).
- Preuves : pas de diaporama ; les captures réelles montrent des contenus privés.
