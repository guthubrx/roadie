# 048 - Consommation au repos

Demande validée le 18 octobre 2026 (`/my.specify-all 1 a 4`, point 1), après l'audit
performance du 15 octobre et une mesure de 3,4 s de CPU en 30 s le 18 octobre.

## Besoin

Quand l'utilisateur ne touche pas la machine, Roadie doit presque cesser de travailler.
Aujourd'hui, des minuteries relancent des relevés complets des fenêtres et des captures
d'écran. Chaque relevé interroge toutes les applications ouvertes et les réveille.

## Périmètre

Les quatre constats CRITICAL de l'audit du 15 octobre, s'ils restent ouverts dans le
code actuel :
- A-01 : la bordure relance un relevé complet un rafraîchissement sur deux ;
- C-01 : chaque lot de vignettes énumère toutes les fenêtres du système ;
- C-02 : la minuterie du rail relève et relit des fichiers avant de savoir si rien n'a changé ;
- C-03 : une vignette neuve fait reconstruire toutes les cartes du rail.

## Exigences

- R1 Au repos, aucun lecteur périodique (bordure, rail) ne déclenche plus de relevé
  complet que le tiler n'en produit déjà.
- R2 Les vignettes ne relancent pas l'énumération de toutes les fenêtres du système à
  chaque lot quand l'ensemble des fenêtres n'a pas changé.
- R3 Une minuterie du rail sans changement d'état ne fait ni relevé complet supplémentaire
  ni relecture de fichier inchangé.
- R4 Une vignette neuve met à jour sa carte, pas toutes les cartes du rail.
- R5 Comportements conservés : bordure à jour au changement de focus, vignettes
  rafraîchies, rail à jour au changement de stage, budgets de capture et quarantaines.

## Critères de réussite

- Mesure avant/après par `specs/048-consommation-repos/mesures/mesure-repos.py`, mêmes
  conditions : inactivité d'au moins 60 s, fenêtre de 120 s, échantillon de pile 10 s.
- Baisse du CPU au repos et des échantillons de relevé AX complet ; chiffres publiés
  avec leurs limites. Sans baisse mesurée, le changement est retiré ou documenté comme
  sans gain (constitution XXII).
- Suite de tests verte, hors les deux tests instables préexistants documentés en 047.

## Hors périmètre

Constats HIGH (session 051), réglages macOS (049), double-clic (050).
