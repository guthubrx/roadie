# Spécification : Fermeture réactive des fenêtres dans le navrail

**Branche :** `029-navrail-fermeture`
**Date :** 2026-10-14
**Statut :** Implemented
**Entrée :** Quand une fenêtre se ferme, le navrail doit retirer rapidement sa vignette et masquer immédiatement la stage devenue vide.

## Problème

Roadie met plusieurs secondes à refléter la fermeture d'une fenêtre dans le navrail. Si cette fenêtre était la dernière de sa stage, la stage vide reste visible pendant le même délai. Le navrail présente donc un état qui n'existe plus.

## Histoires utilisateur

### US1 — Fermer une fenêtre parmi plusieurs

En tant qu'utilisateur, je veux que la vignette d'une fenêtre fermée disparaisse rapidement du navrail afin que la stage montre uniquement les fenêtres encore présentes.

**Test indépendant :** fermer une fenêtre dans une stage qui en contient deux et vérifier que seule la fenêtre fermée disparaît.

### US2 — Fermer la dernière fenêtre d'une stage

En tant qu'utilisateur, je veux que la stage disparaisse du navrail dès que sa dernière fenêtre ferme afin de ne pas voir une stage vide obsolète.

**Test indépendant :** fermer l'unique fenêtre d'une stage et vérifier que la vignette et la stage disparaissent ensemble.

### US3 — Résister aux événements en retard

En tant qu'utilisateur, je veux que le navrail reste cohérent pendant des fermetures rapides ou concurrentes afin qu'une fenêtre détruite ne réapparaisse pas brièvement.

**Test indépendant :** simuler une notification tardive ou répétée après la fermeture et vérifier que l'état le plus récent reste visible.

## Exigences fonctionnelles

- **FR-001.** Le navrail doit retirer une fenêtre fermée au premier état confirmé qui ne la contient plus.
- **FR-002.** La disparition visuelle ne doit pas attendre la cadence lente d'un relevé périodique général lorsque Roadie reçoit déjà une preuve de fermeture.
- **FR-003.** Une stage qui contient encore une fenêtre doit rester visible avec toutes ses autres fenêtres et leur ordre inchangé.
- **FR-004.** Une stage devenue vide doit disparaître dans la même mise à jour visuelle que sa dernière fenêtre.
- **FR-005.** Le comportement doit couvrir une fermeture normale et plusieurs fermetures rapprochées.
- **FR-006.** Une notification répétée, ancienne ou arrivée dans un ordre différent ne doit pas recréer une fenêtre détruite ni une stage vide.
- **FR-007.** Le changement ne doit pas déclencher de commande de layout, de déplacement, de focus ou de changement de stage.
- **FR-008.** Le changement ne doit pas ajouter de boucle permanente ou non bornée, de nouveau registre de fenêtres ou de dépendance externe.
- **FR-009.** Les modes du navrail et les architectures monolithique et modulaire doivent produire le même résultat.
- **FR-010.** Les stages masquées, parkées, maximisées et en plein écran doivent conserver leurs règles existantes tant que leurs fenêtres existent.
- **FR-011.** Le coût doit rester linéaire selon le nombre de fenêtres observées. Aucun appel d'accessibilité supplémentaire ne doit être lancé pour chaque vignette du rail.
- **FR-012.** La mesure avant/après doit utiliser le même scénario, la même cadence d'observation et le même nombre de fenêtres.
- **FR-013.** Les tests doivent couvrir au minimum une stage avec plusieurs fenêtres, la dernière fenêtre, deux fermetures rapprochées et un événement ancien.
- **FR-014.** La livraison doit suivre le pipeline Roadie existant : tests ciblés, régressions utiles, build, installation ou activation documentée, push vérifié et nettoyage du seul périmètre 029.
- **FR-015.** Si CoreGraphics montre encore une fenêtre après sa fermeture AX, Roadie peut lancer au plus dix reprises à 50 ms par identifiant avec l'échéancier existant.

## Critères de succès

- **SC-001.** La vignette d'une fenêtre fermée disparaît du navrail en moins de 400 ms dans au moins 95 % des mesures locales du scénario de référence.
- **SC-002.** La fermeture de la dernière fenêtre retire la stage dans la même mise à jour du navrail.
- **SC-003.** Cent pour cent des scénarios multi-fenêtres conservent les fenêtres restantes, leur stage et leur ordre.
- **SC-004.** Aucun scénario de notification répétée ou tardive ne fait réapparaître une fenêtre fermée.
- **SC-005.** Les tests ciblés et les régressions du snapshot, du rail et du cycle de vie passent sans nouvelle erreur.
- **SC-006.** Aucune boucle permanente ou non bornée, dépendance externe ou commande de layout n'est introduite ; les reprises cessent après dix passages ou cinq secondes.

## Cas limites

- Deux fenêtres de la même stage ferment presque au même instant.
- Les dernières fenêtres de deux stages ferment presque au même instant.
- La fenêtre ferme pendant un rafraîchissement du navrail.
- Un ancien snapshot contient encore la fenêtre après réception de sa fermeture.
- La fenêtre fermée était ciblée par le focus, une bordure ou une action de glisser-déposer.

## Hors périmètre

Refonte du navrail, nouvelle animation, changement du modèle de stage, nouvelle règle de placement, nouvelle commande CLI, accélération générale de toutes les collectes, modification de macOS, terminaison complète d'une application et changement des règles de focus ou de layout.

## Dépendances

- **SPEC-015** : représentation des fenêtres maximisées et plein écran.
- **SPEC-016** : snapshot partagé et stabilisation du navrail.
- **SPEC-017** : tiling réactif et propagation d'état.
- **SPEC-019** : maximisation qui réserve le navrail.

## Hypothèses

- Roadie reçoit déjà une preuve de disparition avant le prochain relevé complet lent.
- Le renderer du navrail sait déjà supprimer une fenêtre et masquer une stage vide lorsque son état source est à jour.
- Le seuil de 400 ms mesure le retour visuel en p95. Les journaux montrent déjà un p95 proche de 249 ms avant le watcher et le rendu. La cible garde une marge réaliste pour le mode monolithique.

## Sources de référence

- W3C WCAG 2.2 : un changement d'état visible doit rester cohérent et déterminable.
- web.dev INP : le retour visuel rapide évite que l'interface paraisse bloquée ; 200 ms sert de repère web, pas de seuil imposé à ce pipeline natif.
- Testing Library et Playwright : les tests doivent vérifier le résultat visible par l'utilisateur plutôt qu'un détail interne.
