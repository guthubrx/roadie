# Session 086 - Échecs durables et lenteurs nommées

Correction demandée le 26 octobre 2026, après relecture des journaux du 20 au 26 octobre
(`~/.roadies/events.jsonl` et archives) : « regarde s'il y a eu des trucs aberrants qu'on
n'aurait pas réglés », puis accord pour la correction. 084 et 085 sont pris par le lanceur.

## Constats

1. **Écriture en échec refaite toutes les 31 s.** T3 Code 223, le 25 octobre : 28
   `layout_failed` identiques (`977,46 817x1115`), un toutes les 30 à 33 s. La mémoire des
   échecs complets (`FailedFrame`) expirait après 30 s sans variante durable, contrairement
   aux refus de taille corrigés en 083.
2. **Passes lentes sans cause nommée.** Le 26 octobre, 56 passes de plus de 3 s : de 9 h 00 à
   9 h 07, une quarantaine de 3 à 6 s sans aucune écriture (après le débranchement du LG), puis
   13,6 s, 8,6 s et 13,2 s entre 19 h 54 et 20 h 01 (réveil, écran rebranché, Firefox). Chaque
   appel AX est déjà borné à 0,5 s : la durée vient d'appels nombreux, que les journaux ne
   rattachent à aucune application.
3. **Firefox ramené sur l'écran du Mac.** Le 26 à 20 h 00, Firefox déplacé sur le LG a été
   remis à sa place (`layout_external_change_reverted`) : aucun geste de souris n'a été vu entre
   19 h 50 et 20 h 02, le déplacement a donc été traité comme un changement externe (A4, A13).

## Exigences

- **FR-001** Un échec d'écriture identique (même demande, même cadre observé) revenu après
  l'expiration devient durable : la demande n'est plus refaite tant que la fenêtre reste à ce
  cadre et que la demande ne change pas. Une écriture réussie, un geste, une nouvelle topologie
  d'écrans ou la reprise des réglages l'effacent comme l'échec ordinaire.
- **FR-002** Une passe d'une seconde ou plus ajoute à `live_tick` le champ `axSlowApps` : les
  trois applications dont les appels AX ont cumulé au moins 0,2 s, la plus lente d'abord
  (« Firefox 2.31s/14 »). Une passe lente sans commande est aussi tracée.
- Constat 3 : pas de correction sans cause établie. La mesure de FR-002 et les prochains
  journaux diront si la lenteur de Firefox a masqué le geste.
- Aucune règle propre à une application.
