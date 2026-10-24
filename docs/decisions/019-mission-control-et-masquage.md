# ADR 019 - Mission Control et masquage des fenêtres

Date : 2026-10-24. Statut : Accepté.

Pendant Mission Control, macOS rapporte des cadres réduits et déplacés pour toutes les
fenêtres (mesure : 1837×2114 devient 575×662). Roadie les observait comme des cadres
réels. Il garait les fenêtres des stages masquées avec la taille réduite, enregistrait
ces cadres comme « dernière frame visible » dans stages.json et restore.json, puis les
réappliquait à l’arrêt. Une écriture sans réponse de l’application (−25204) était en
plus acceptée comme réponse, ce qui figeait la petite taille.

Décision : quatre protections indépendantes.

1. Sonde : Mission Control est reconnu aux fenêtres du Dock de niveau 18 couvrant un écran.
2. Pendant Mission Control et 0,4 s après, la passe de disposition s’arrête avant le
   relevé ; tout relevé est provisoire (ni enregistré, ni partagé) ; le fichier de
   restauration garde sa version précédente.
3. Garer une fenêtre écrit sa position seule : la taille d’une fenêtre masquée n’est
   jamais réécrite.
4. Une écriture sans relecture n’est pas une réponse de l’application : l’écart est repris.

Conséquences : aucune disposition pendant Mission Control (ce que l’utilisateur voit est
de toute façon l’animation macOS). Une énumération CG des fenêtres à l’écran par passe.
La signature du Dock est empirique : si macOS la change, la protection 3 empêche encore
le rétrécissement des fenêtres masquées. Les cadres déjà pollués guérissent à l’affichage
suivant de leur stage.
