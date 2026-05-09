# Recherche : Performance ressentie Roadie

## Décision 1 : commencer par une instrumentation légère des interactions critiques

**Décision**: Ajouter une mesure structurée pour les interactions critiques avant toute optimisation lourde.

**Rationale**: Les lenteurs ressenties peuvent venir de sources différentes : lecture de l'état, masquage/restauration de fenêtres, layout, focus, rail ou tâche de fond. Mesurer chaque étape évite de corriger au hasard et permet de prouver un gain.

**Alternatives considérées**:

- Optimiser directement les délais observés manuellement : rejeté car cela reproduit le risque de tuning fragile.
- Instrumenter tout le daemon en continu : rejeté car la mesure elle-même pourrait devenir coûteuse et bruyante.
- Mesurer uniquement le temps total : rejeté car insuffisant pour diagnostiquer la cause d'une lenteur.

## Décision 2 : définir un vocabulaire d'étapes commun

**Décision**: Standardiser les étapes de mesure : `snapshot`, `state_update`, `hide_previous`, `restore_target`, `layout_apply`, `focus`, `secondary_work`, `total`.

**Rationale**: Un vocabulaire stable permet de comparer stage, desktop, display, AltTab et rail avec les mêmes outils. Il rend aussi les diagnostics compréhensibles sans lire le code.

**Alternatives considérées**:

- Nommer librement chaque étape par commande : rejeté car difficile à comparer.
- Mesurer seulement les appels bas niveau : rejeté car trop technique pour un diagnostic utilisateur.

## Décision 3 : préserver strictement la séparation lecture/écriture

**Décision**: Les chemins de lecture, diagnostic, query, metrics, tree dump et control status doivent rester read-only et ne doivent pas suivre le focus externe ni persister d'état.

**Rationale**: Des bugs récents venaient de lectures qui modifiaient l'état Roadie. La performance ne doit pas réintroduire ce couplage, surtout si les diagnostics deviennent plus fréquents.

**Alternatives considérées**:

- Autoriser les lectures à réparer l'état par opportunisme : rejeté car cela rend les comportements non déterministes.
- Créer des diagnostics séparés sans réutiliser les snapshots : rejeté car cela dupliquerait trop de logique.

## Décision 4 : optimiser d'abord stage et desktop par chemin direct

**Décision**: Les commandes stage/desktop doivent réutiliser le contexte déjà connu et limiter le recalcul à la cible, puis seulement recourir à la boucle globale si nécessaire.

**Rationale**: Ce sont les interactions quotidiennes les plus fréquentes. Le gain perçu est maximal si la cible devient visible et focalisable sans attendre le prochain tick ni un recalcul global.

**Alternatives considérées**:

- Diminuer seulement l'intervalle du timer global : rejeté car cela augmente la charge de fond sans garantir la rapidité des commandes.
- Tout traiter dans `LayoutMaintainer.tick()` : rejeté car la commande explicite doit être prioritaire et directe.

## Décision 5 : traiter AltTab comme une intention utilisateur prioritaire

**Décision**: Les événements de focus externe correspondant à une fenêtre gérée doivent activer directement le stage/desktop propriétaire avec anti-oscillation.

**Rationale**: AltTab est un chemin utilisateur réel, pas un bruit système. Le traiter via la boucle générale rend l'expérience plus lente que les raccourcis Roadie.

**Alternatives considérées**:

- Ignorer AltTab et recommander les raccourcis Roadie : rejeté car contraire à l'usage macOS naturel.
- Suivre tout focus externe sans garde : rejeté car cela réintroduit les oscillations observées.

## Décision 6 : éviter les déplacements redondants avec une tolérance explicite

**Décision**: Une fenêtre déjà équivalente à sa cible ne doit pas être déplacée. La tolérance doit être documentée et testée.

**Rationale**: Les appels de déplacement redondants coûtent du temps et provoquent une sensation de tremblement ou de correction multiple.

**Alternatives considérées**:

- Toujours appliquer toutes les frames pour simplifier : rejeté car coûteux et visuellement bruyant.
- Tolérance implicite non documentée : rejeté car difficile à tester et à ajuster.

## Décision 7 : isoler le rail et les surfaces secondaires du chemin critique

**Décision**: Le rail, les bordures, les métriques et diagnostics peuvent observer ou se rafraîchir après la bascule principale, mais ne doivent pas bloquer la visibilité/focus de la cible.

**Rationale**: Ces surfaces améliorent l'expérience, mais deviennent contre-productives si elles ralentissent l'action principale. Le chemin critique doit rester minimal.

**Alternatives considérées**:

- Désactiver le rail pour gagner en vitesse : rejeté car le rail reste utile et doit cohabiter proprement.
- Forcer le rail à être parfaitement à jour avant chaque focus : rejeté car l'utilisateur priorise la fenêtre cible.

## Décision 8 : garder le timer comme filet de sécurité

**Décision**: La boucle périodique reste active pour rattraper les états manqués, mais les interactions utilisateur critiques doivent être traitées par un chemin événementiel/direct.

**Rationale**: Sur macOS, certains événements peuvent être manqués ou arriver en ordre non idéal. Un filet périodique reste nécessaire, mais ne doit pas définir la latence perçue.

**Alternatives considérées**:

- Supprimer totalement le timer : rejeté car trop risqué pour la robustesse.
- Tout laisser au timer et le rendre plus fréquent : rejeté car cela consomme plus et reste moins réactif qu'un traitement direct.
