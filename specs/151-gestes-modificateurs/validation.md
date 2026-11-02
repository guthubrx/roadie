# Validation151 — version active

Le 2 novembre 2026. Ctrl + glisser gauche déplace depuis le contenu ; Ctrl + Alt + glisser gauche redimensionne. Deux choix indépendants dans Tuilage, modifiables à chaud et désactivables. La configuration initiale a été rétablie à l'octet près après les essais de désactivation.

## Tests
- 19 tests ciblés151 verts après le correctif final de source de rejeu.
- Suite finale :2480 tests /375 suites,62,493s, tous verts.
- 28 tests de scripts,13,663s, tous verts.
- Décomptes du catalogue mis à jour pour les deux nouveaux réglages.
- 534 empreintes Sources/Tests conformes entre les tests et la construction finale. Aucune source ni test modifié pendant une construction.

## Revues
Revue de plan et deux rondes de revue de code via Bridget. R1-R4 traités ; dernière revue sur76cc7873 sans défaut bloquant. Limite des relecteurs : lecture seule, pas de shell ni exécution des tests. Le dernier correctif de source de rejeu6525a8b9 a ensuite été validé par le parent avec la suite et les événements natifs. Le détail des constats, décisions et limites reste dans revue-code.md.

## Construction et activation
Source6525a8b9. Build Release signé avec le certificat existant ; aucune permission changée. Installation dans /Users/moi/Applications/Roadie.app et CLI /Users/moi/.local/bin/roadie. UUID1D14C437-8C8B-357A-BB20-50B016B79EBF. PID29631. Santé finale5/5. Retour arrière150 et symboles conservés hors Git. Redémarrage normal par les scripts du projet, sans arrêt forcé.

## Parcours natifs
Trois fenêtres AppKit fictives, événements macOS injectés par une action BTT ad hoc. Aucun déclencheur BTT persistant ajouté. Le produit ne dépend pas de BTT.

| Parcours | Observation |
|---|---|
| Ctrl + glisser dans le contenu | A et C permutées,5 cadres observés avant le relâchement, arbre final relu |
| Ctrl + Alt + glisser de −100 points | Largeur A938→838 ; voisines408→508,14 cadres intermédiaires et ratios conservés |
| Échap pendant le resize | 14 cadres intermédiaires, puis trois cadres initiaux restaurés et arbre inchangé |
| Ctrl + clic sans glisser | Une paire source puis exactement une paire rejouée, marqueur5927948012369431627, client recevant Ctrl ; pas de boucle |
| Ctrl + glisser d'une flottante | B décalée de(−100,−50),9 cadres intermédiaires ; A/C stables, position relue dans l'épinglage |

Le premier essai a révélé le conteneur invisible plein écran de Notification Center ; filtre limité et test de régression ajoutés. Le premier pilote de preuve lançait sa capture suivante avant la fin effective de l'action BTT ; il attend maintenant un reçu écrit après le up. Un tap natif indépendant a aussi révélé le rejeu dont le champ userData était repris de la source initiale. Les gestes ont été temporairement désactivés pour arrêter cette boucle. Le correctif attache une source CG privée avec son propre marqueur. Le tap final observe seulement quatre événements (paire initiale puis paire Roadie), et le client seulement la paire rendue.

Les fenêtres fictives ont été fermées proprement. La stage validation151 et son épinglage temporaire ont disparu. Les stages initiales et l'écran actif initial ont été rétablis. L'essai de flottant a épinglé B, confirmée ensuite dans l'état ; seuls les trois objets fictifs ont été manipulés.

## Preuves et limites
Diaporama autonome de huit étapes, captures limitées aux fenêtres fictives. Aperçu sans erreur console ; navigation jusqu'à8/8 et lecture/pause vérifiées. Coordonnées CG réelles dans les légendes. Aucun isTrusted de navigateur ou clic physique inventé.

Preuves partielles : appuis physiques, interface des réglages et ouverture effective d'un menu contextuel non enregistrés. La paire Ctrl + clic et ses touches sont observées dans le client ; son menu n'est pas revendiqué. Aucun gain CPU/GPU ni latence globale revendiqué. Une taille imposée par une application et le plein écran natif gardent leurs limites habituelles. L'échec d'une observation pour un clic reste refusé par prudence ; la trace de ce cas rare est une limite mineure.

Originaux, sources du pilote, manifestes, traces, tests, retour arrière et symboles : /Users/moi/.local/state/roadies/validation/2026-11-02-151. Aucun contenu utilisateur capturé ou publié. Incident Bridget de paramètre SHA invalide conservé ; catalogues de mainteneurs vides, aucun destinataire autorisé identifié, aucun envoi arbitraire.
