# Spécification Fonctionnelle : Performance ressentie Roadie

**Branche fonctionnalité**: `027-perceived-performance`  
**Créé le**: 2026-05-09  
**Statut**: Brouillon  
**Entrée**: Description utilisateur : "Faire une spec pour améliorer progressivement la vitesse ressentie et la fluidité de Roadie : mesurer les latences, réduire les lectures complètes après commandes, éviter les déplacements redondants, rendre les switch stage/desktop/AltTab plus directs, garder la boucle périodique comme filet de sécurité et isoler le rail du chemin critique."

## Scénarios Utilisateur & Tests *(obligatoire)*

### User Story 1 - Comprendre où Roadie perd du temps (Priorité : P1)

Un utilisateur qui ressent une lenteur lors d'un changement de stage, desktop, écran ou fenêtre doit pouvoir obtenir un diagnostic simple qui indique quelle étape consomme du temps et si la latence vient de Roadie ou de l'environnement macOS.

**Pourquoi cette priorité**: Sans mesure, les optimisations deviennent du tuning au hasard. La première tranche doit rendre les lenteurs visibles, comparables et vérifiables avant de modifier les comportements sensibles.

**Test indépendant**: Déclencher plusieurs actions Roadie représentatives, consulter le diagnostic de performance, puis vérifier que chaque action expose une durée totale et une répartition par étape utilisateur observable.

**Scénarios d'acceptation**:

1. **Étant donné que** Roadie exécute un changement de stage, **quand** l'action se termine, **alors** un diagnostic indique le temps total perçu et les principales étapes de l'action.
2. **Étant donné que** plusieurs actions similaires sont exécutées, **quand** l'utilisateur consulte le résumé, **alors** Roadie affiche des tendances ou percentiles permettant de comparer avant/après.
3. **Étant donné qu'** une action dépasse le seuil de confort défini, **quand** Roadie publie le diagnostic, **alors** l'utilisateur peut identifier si la lenteur vient du changement de contexte, du déplacement des fenêtres, du focus ou d'une tâche de fond.

---

### User Story 2 - Changer de stage ou desktop sans attente visible (Priorité : P1)

Un utilisateur qui utilise les raccourcis Roadie pour changer de stage ou de desktop doit voir la cible s'activer rapidement, sans clignotement, sans exploration visuelle de stages intermédiaires et sans attendre un cycle de maintenance général.

**Pourquoi cette priorité**: C'est le chemin quotidien le plus fréquent. Si cette interaction est rapide et stable, Roadie paraît fiable même quand d'autres optimisations restent à venir.

**Test indépendant**: Configurer plusieurs stages et desktops avec fenêtres visibles et masquées, déclencher des changements directs et cycliques, puis mesurer que la cible apparaît rapidement et sans activation intermédiaire visible.

**Scénarios d'acceptation**:

1. **Étant donné que** trois stages existent dans un ordre utilisateur connu, **quand** l'utilisateur active le deuxième stage par raccourci, **alors** seul ce stage devient visible et actif.
2. **Étant donné que** des fenêtres du stage précédent doivent être masquées, **quand** le stage cible est activé, **alors** les fenêtres cible deviennent utilisables sans attendre une correction ultérieure.
3. **Étant donné que** le desktop courant change, **quand** l'utilisateur active un autre desktop Roadie, **alors** les fenêtres du desktop cible sont restaurées et focalisables dans le même enchaînement utilisateur.

---

### User Story 3 - Basculer via AltTab avec la même fluidité qu'un raccourci Roadie (Priorité : P1)

Un utilisateur qui choisit une fenêtre via AltTab doit voir Roadie activer immédiatement le stage et le desktop qui contiennent cette fenêtre, sans délai perceptible ni attente d'une boucle périodique.

**Pourquoi cette priorité**: AltTab est un chemin de navigation naturel hors Roadie. Si Roadie le traite comme un signal secondaire, l'expérience donne l'impression d'être lente ou incohérente.

**Test indépendant**: Placer des fenêtres dans plusieurs stages et desktops, sélectionner une fenêtre masquée ou inactive via AltTab, puis vérifier que Roadie active directement le bon contexte et rend la fenêtre visible rapidement.

**Scénarios d'acceptation**:

1. **Étant donné qu'** une fenêtre cible appartient à un stage inactif, **quand** l'utilisateur la sélectionne via AltTab, **alors** Roadie active le stage correspondant sans passer visuellement par d'autres stages.
2. **Étant donné qu'** une fenêtre cible appartient à un desktop Roadie inactif, **quand** l'utilisateur la sélectionne via AltTab, **alors** Roadie active le desktop correspondant et rend la fenêtre utilisable.
3. **Étant donné que** plusieurs événements de focus arrivent rapidement, **quand** ils concernent la même intention utilisateur, **alors** Roadie les traite comme une seule bascule cohérente.

---

### User Story 4 - Éviter les mouvements inutiles de fenêtres (Priorité : P2)

Un utilisateur ne doit pas voir ses fenêtres trembler, se repositionner inutilement ou se déplacer deux fois lorsque Roadie connaît déjà leur position cible.

**Pourquoi cette priorité**: La fluidité ressentie dépend autant de l'absence de mouvements inutiles que de la vitesse brute. Réduire les corrections redondantes diminue aussi la charge sur macOS.

**Test indépendant**: Déclencher des commandes dans un état déjà proche de la cible, puis vérifier que Roadie ne déplace que les fenêtres qui ont réellement besoin de changer.

**Scénarios d'acceptation**:

1. **Étant donné qu'** une fenêtre est déjà à sa position cible, **quand** Roadie applique le contexte courant, **alors** cette fenêtre n'est pas déplacée.
2. **Étant donné qu'** une fenêtre est dans une position équivalente à une tolérance acceptable, **quand** Roadie vérifie le layout, **alors** il évite une correction visuellement inutile.
3. **Étant donné que** plusieurs fenêtres doivent changer, **quand** Roadie applique les changements, **alors** les changements sont groupés de manière à éviter les allers-retours visibles.

---

### User Story 5 - Garder le rail et les tâches de fond hors du chemin critique (Priorité : P2)

Un utilisateur qui change de stage, desktop ou fenêtre ne doit pas subir de latence parce que le rail, les bordures, les métriques ou les tâches de maintenance font du travail non essentiel au même moment.

**Pourquoi cette priorité**: Les surfaces visuelles et diagnostics sont utiles, mais elles ne doivent jamais ralentir l'action principale. Le chemin critique doit rester réservé au contexte actif et aux fenêtres visibles.

**Test indépendant**: Activer le rail et les diagnostics, exécuter des bascules rapides, puis vérifier que les timings des interactions principales restent dans les seuils de confort même si les surfaces secondaires se mettent à jour ensuite.

**Scénarios d'acceptation**:

1. **Étant donné que** le rail est visible, **quand** l'utilisateur change de stage, **alors** la bascule reste prioritaire et le rail peut se rafraîchir après l'action principale.
2. **Étant donné que** des diagnostics ou métriques sont collectés, **quand** une commande utilisateur démarre, **alors** la commande n'attend pas une lecture non essentielle.
3. **Étant donné que** Roadie est inactif, **quand** aucun changement utilisateur ni système pertinent n'arrive, **alors** Roadie limite son travail de fond tout en conservant une correction périodique de sécurité.

### Cas Limites

- Une fenêtre disparaît pendant une bascule stage/desktop/AltTab.
- Une fenêtre refuse son déplacement ou son focus pendant une action rapide.
- Plusieurs événements de focus contradictoires arrivent dans une fenêtre de temps très courte.
- Un écran est déconnecté pendant ou juste après une bascule.
- Un stage ou desktop cible contient uniquement des fenêtres fermées ou non gérables.
- Une tâche de restauration de sécurité, de détection de fenêtre transitoire ou de diagnostic démarre pendant une commande utilisateur.
- Le rail est désactivé, masqué, épinglé ou en cours de rafraîchissement pendant une bascule.
- Les mesures de performance ne doivent pas elles-mêmes rendre l'interaction perceptiblement plus lente.

## Exigences *(obligatoire)*

### Exigences Fonctionnelles

- **FR-001**: Roadie DOIT mesurer les interactions utilisateur critiques, au minimum les changements de stage, desktop, écran, focus directionnel, focus via AltTab et actions de rail.
- **FR-002**: Roadie DOIT exposer pour chaque interaction mesurée une durée totale et une répartition lisible des étapes principales, sans exiger l'inspection des logs bruts.
- **FR-003**: Roadie DOIT conserver un historique court des mesures récentes permettant de comparer les temps typiques et les actions lentes.
- **FR-004**: Roadie DOIT signaler les interactions qui dépassent les seuils de confort définis pour l'usage quotidien.
- **FR-005**: Les commandes explicites de stage et desktop DOIVENT activer directement la cible demandée sans parcourir visuellement les cibles intermédiaires.
- **FR-006**: Les commandes explicites de stage et desktop DOIVENT rendre les fenêtres cible visibles et focalisables dans le même enchaînement utilisateur.
- **FR-007**: Roadie DOIT traiter une bascule AltTab vers une fenêtre gérée comme une intention utilisateur prioritaire capable d'activer le stage et le desktop propriétaires de cette fenêtre.
- **FR-008**: Roadie DOIT regrouper les signaux de focus rapprochés qui représentent la même intention utilisateur afin d'éviter les oscillations.
- **FR-009**: Roadie DOIT éviter de déplacer une fenêtre lorsque sa position actuelle est déjà équivalente à la position cible selon une tolérance documentée.
- **FR-010**: Roadie DOIT éviter de recalculer ou relire l'état global lorsque l'action utilisateur ne concerne qu'un contexte limité et que les informations nécessaires sont déjà disponibles.
- **FR-011**: Roadie DOIT conserver une correction périodique de sécurité pour les états manqués, mais cette correction NE DOIT PAS être le chemin principal des interactions utilisateur critiques.
- **FR-012**: Les surfaces secondaires telles que rail, bordures, diagnostics et métriques NE DOIVENT PAS bloquer la visibilité ou le focus de la fenêtre cible lors d'une interaction critique.
- **FR-013**: Roadie DOIT fournir une manière utilisateur de consulter les performances récentes et de repérer les actions lentes.
- **FR-014**: Roadie DOIT fournir des tests de régression couvrant les bascules stage, desktop et AltTab afin d'empêcher le retour des oscillations ou délais perceptibles.
- **FR-015**: Roadie DOIT préserver les garanties de sécurité existantes : pas de dépendance à des APIs privées, pas de désactivation de protections système, pas d'animations système imposées.
- **FR-016**: Roadie DOIT permettre une livraison progressive : la mesure seule doit être utile, puis chaque optimisation doit pouvoir être validée indépendamment.

### Entités Clés *(inclure si la fonctionnalité implique des données)*

- **Interaction critique**: Action utilisateur dont la lenteur est immédiatement ressentie, par exemple changement de stage, desktop, écran, focus, AltTab ou clic rail.
- **Mesure de performance**: Résumé d'une interaction critique, incluant nom d'action, contexte, durée totale, étapes principales, résultat et indicateur de dépassement de seuil.
- **Seuil de confort**: Limite mesurable au-delà de laquelle une interaction est considérée lente pour un usage quotidien.
- **Contexte cible**: Stage, desktop, écran et fenêtre que l'utilisateur veut atteindre à la fin d'une interaction.
- **Travail critique**: Travail minimal nécessaire pour rendre le contexte cible visible et focalisable.
- **Travail secondaire**: Mise à jour de surfaces, diagnostics, métriques ou correction de fond pouvant être différée sans empêcher l'utilisateur de continuer.

## Critères de Succès *(obligatoire)*

### Résultats Mesurables

- **SC-001**: Au moins 95% des changements de stage directs mesurés sur un environnement de test représentatif rendent la fenêtre cible visible et focalisable en moins de 150 ms.
- **SC-002**: Au moins 95% des changements de desktop Roadie mesurés rendent une fenêtre cible disponible en moins de 200 ms lorsque les fenêtres existent encore.
- **SC-003**: Au moins 90% des bascules AltTab vers une fenêtre gérée rendent le stage ou desktop propriétaire visible en moins de 250 ms.
- **SC-004**: Les changements de stage, desktop et AltTab ne montrent aucune activation intermédiaire visible dans 100% des scénarios automatisés de régression.
- **SC-005**: Les interactions critiques lentes produisent un diagnostic actionnable dans 100% des scénarios de test où le seuil de confort est dépassé.
- **SC-006**: Les actions déjà proches de leur état cible réduisent le nombre de déplacements de fenêtres inutiles d'au moins 80% par rapport à la baseline mesurée avant optimisation.
- **SC-007**: La présence du rail et des diagnostics n'augmente pas de plus de 10% la durée médiane des changements stage/desktop dans les scénarios de test.
- **SC-008**: Les optimisations de performance conservent les tests de régression existants sur stages, desktops, focus, rail, restore safety, fenêtres transitoires et query/status.

## Hypothèses

- La priorité est la fluidité ressentie par l'utilisateur, pas une optimisation théorique de tous les chemins internes.
- Les seuils proposés sont des objectifs initiaux ; ils pourront être ajustés après mesure réelle si macOS impose une limite observable.
- Le travail sera livré progressivement : instrumentation, puis chemins stage/desktop, puis AltTab, puis réduction des mouvements inutiles, puis isolation des surfaces secondaires.
- Le rail reste utile mais ne doit pas être dans le chemin critique d'une bascule.
- La boucle périodique reste nécessaire comme filet de sécurité, même si les interactions principales deviennent événementielles.
- Les animations de fenêtres, les APIs privées macOS et le contrôle natif des Spaces restent hors périmètre.
- Les mesures doivent rester légères et ne pas devenir une nouvelle source de lenteur.
