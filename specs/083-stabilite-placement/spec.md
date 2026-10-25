# Session 083 - Stabilité du placement

Correction demandée le 25 octobre 2026, après lecture des journaux du 22 au 25 octobre
(`~/.roadies/events.jsonl` et archives) : « corrige tout dans l'ordre de priorité que tu
veux ». Numéro 083 : 078 à 082 sont réservés par le pipeline `/my.specify-all 075 a 082`.

## Constats (heures locales du 25 octobre)

1. **Nouvelles fenêtres sur le mauvais écran.** Neuf fenêtres (Chrome, Finder, iTerm2,
   émulateur) rangées dans la stage active du LG, puis rattachées à l'écran intégré dans la
   même seconde (`window.scope_reconciled_to_physical_display`, délai 0 à 3 s). La stage
   `7-restored-2` du LG est en mode `bsp`, le seul où le rattachement physique s'applique.
   macOS ouvre la fenêtre sur l'autre écran ; le rattachement passait avant le placement.
2. **T3 Code et Chrome toutes les 32 s.** De 16 h 18 à 18 h 33, environ 230 fois : passe
   `safety`, demande 817 points, T3 Code garde 840, réparation de Chrome. La mémoire du
   refus expirait après 30 s (FR-004) et la même demande revenait.
3. **Émulateur Android toutes les 4 s.** De 19 h 02 à 20 h 14, environ 175 réécritures :
   l'émulateur accepte 673 × 934 puis revient à 403 × 933. La mémoire des écritures
   annulées ne valait que 3 s, les passes de contrôle arrivaient toutes les 4 s.
4. **Fenêtre fantôme d'AlDente (781).** Gardée membre de la stage Perso par l'inventaire
   CoreGraphics (même pid), alors qu'AlDente l'a retirée : 82 échecs de restauration et
   bascules qui l'attendent.

## Exigences

- **FR-001** Une fenêtre neuve n'est pas rattachée à l'écran où macOS l'a ouverte pendant
  `LayoutTolerance.newWindowDriftGrace` (5 s) ; le placement la pose sur l'écran choisi.
  Après ce délai, le rattachement reste le repli.
- **FR-002** Un refus de taille identique (même demande, même réponse) revenu après
  l'expiration devient durable, jusqu'à une demande acceptée d'une autre taille.
- **FR-003** Une écriture acceptée puis annulée deux fois de suite (retour au même cadre)
  n'est plus refaite tant que la cible et le cadre observé restent les mêmes.
- **FR-004** Toutes les 30 s, un membre gardé seulement par l'inventaire et retiré par son
  application (critères SPEC-065) est marqué fermé ; l'absence ordinaire le retire.
- Aucune règle propre à une application.
