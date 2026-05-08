# Spécification de fonctionnalité : Évolution écosystème Roadie

**Branche**: `002-roadie-ecosystem-upgrade`  
**Créé le**: 2026-05-08  
**Statut**: Brouillon  
**Entrée**: Description utilisateur : "SpecKit specify l'ensemble des améliorations évoquées pour faire évoluer Roadie vers un écosystème plus ouvert inspiré de yabai, AeroSpace et Hyprland : bus d'événements, subscribe, moteur de règles, commandes power-user, groupes/stack/tabbed, surfaces CLI et intégrations externes."

## Scénarios utilisateur et tests *(obligatoire)*

### Scénario 1 - Observer Roadie en temps réel (Priorité : P1)

Un utilisateur avancé veut connecter Roadie à des outils externes comme une barre de statut, des scripts, BetterTouchTool ou un système de monitoring. Il doit pouvoir recevoir les changements importants de Roadie sans lire périodiquement tout l'état.

**Pourquoi cette priorité**: Sans événements fiables, Roadie reste un outil isolé. C'est la fondation nécessaire avant les règles, les intégrations et les automatisations.

**Test indépendant**: Peut être testé en démarrant Roadie, en ouvrant/fermant/focalisant des fenêtres, en changeant de desktop ou de stage, puis en vérifiant que les événements attendus sont publiés dans l'ordre avec les informations utiles.

**Scénarios d'acceptation**:

1. **Étant donné** Roadie est actif avec au moins une fenêtre gérée, **Quand** une fenêtre est créée, fermée, focalisée, déplacée ou réorganisée, **Alors** un événement nommé et documenté est publié.
2. **Étant donné** un outil externe est abonné aux événements Roadie, **Quand** l'utilisateur change de stage, desktop ou écran actif, **Alors** l'outil reçoit un événement contenant le nouveau contexte actif.
3. **Étant donné** Roadie applique ou échoue à appliquer un layout, **Quand** l'action se termine, **Alors** un événement indique le résultat, le périmètre concerné et les compteurs utiles.

---

### Scénario 2 - Automatiser les fenêtres par règles (Priorité : P2)

Un utilisateur veut déclarer des règles pour que Roadie sache quoi faire des fenêtres selon leur application, titre, rôle, écran ou contexte courant. Les règles doivent couvrir les cas usuels sans écrire de scripts fragiles.

**Pourquoi cette priorité**: Les règles transforment Roadie d'un tiler manuel en système prévisible. Elles réduisent les corrections manuelles répétitives.

**Test indépendant**: Peut être testé avec une configuration de règles et des fenêtres simulées ou réelles, en vérifiant que chaque fenêtre reçoit les actions attendues au moment de sa détection.

**Scénarios d'acceptation**:

1. **Étant donné** une règle cible une application précise, **Quand** une fenêtre de cette application apparaît, **Alors** Roadie applique l'action déclarée sans intervention manuelle.
2. **Étant donné** plusieurs règles correspondent à une même fenêtre, **Quand** Roadie évalue les règles, **Alors** l'ordre de priorité est déterministe et observable.
3. **Étant donné** une règle est invalide ou ambiguë, **Quand** la configuration est validée, **Alors** Roadie signale le problème sans appliquer partiellement une règle dangereuse.

---

### Scénario 3 - Piloter l'arbre de layout comme power-user (Priorité : P3)

Un utilisateur veut restructurer rapidement son espace de travail avec des commandes explicites : revenir au dernier focus, déplacer un workspace vers l'écran courant, contrôler l'orientation d'une séparation, aplatir un layout, définir le point d'insertion de la prochaine fenêtre ou agrandir temporairement une fenêtre sans perdre l'organisation.

**Pourquoi cette priorité**: Ces commandes rapprochent Roadie de l'ergonomie attendue par les utilisateurs venant de yabai, AeroSpace, i3 ou Hyprland.

**Test indépendant**: Peut être testé commande par commande sur un état connu, en vérifiant que le focus, les memberships et les placements obtenus correspondent à l'intention utilisateur.

**Scénarios d'acceptation**:

1. **Étant donné** deux fenêtres ou plus sont gérées dans un stage, **Quand** l'utilisateur demande un retour au focus précédent, **Alors** Roadie focalise l'élément précédent si celui-ci existe encore.
2. **Étant donné** un layout contient plusieurs subdivisions, **Quand** l'utilisateur demande un aplatissement, **Alors** Roadie produit un layout lisible sans perdre les fenêtres ni leur stage.
3. **Étant donné** plusieurs écrans sont connectés, **Quand** l'utilisateur demande à amener un desktop ou un stage sur l'écran courant, **Alors** Roadie met à jour le contexte sans déplacer les fenêtres vers un écran inattendu.

---

### Scénario 4 - Grouper des fenêtres dans un même emplacement (Priorité : P4)

Un utilisateur veut regrouper plusieurs fenêtres dans un même slot de layout, avec une navigation claire entre elles, pour les cas d'usage comme terminaux multiples, documents liés ou fenêtres auxiliaires d'une même application.

**Pourquoi cette priorité**: Les groupes/stack/tabbed apportent un gain UX fort, mais nécessitent une base d'événements, de règles et de commandes stable avant d'être sûrs.

**Test indépendant**: Peut être testé en créant un groupe, en y ajoutant plusieurs fenêtres, en changeant la fenêtre active du groupe, puis en vérifiant que le layout global reste stable.

**Scénarios d'acceptation**:

1. **Étant donné** deux fenêtres sont dans le même stage, **Quand** l'utilisateur les groupe, **Alors** elles partagent un emplacement et une seule est active visuellement.
2. **Étant donné** un groupe contient plusieurs fenêtres, **Quand** l'utilisateur navigue dans le groupe, **Alors** Roadie change la fenêtre active sans modifier les autres stages.
3. **Étant donné** une fenêtre quitte ou ferme un groupe, **Quand** le groupe devient vide ou singleton, **Alors** Roadie normalise l'état sans perdre la fenêtre restante.

---

### Scénario 5 - Explorer l'état Roadie de manière stable (Priorité : P5)

Un utilisateur ou un script veut obtenir des listes normalisées des fenêtres, écrans, desktops, stages, règles et événements pour construire des intégrations robustes.

**Pourquoi cette priorité**: Une surface d'observation stable réduit les scripts ad hoc et facilite les intégrations externes.

**Test indépendant**: Peut être testé en interrogeant chaque liste sur un environnement contrôlé et en vérifiant que les champs restent cohérents entre deux appels.

**Scénarios d'acceptation**:

1. **Étant donné** plusieurs écrans, desktops et stages existent, **Quand** un outil demande la liste correspondante, **Alors** Roadie retourne une représentation stable et documentée.
2. **Étant donné** une fenêtre appartient à un stage, **Quand** un outil liste les fenêtres, **Alors** la réponse expose son contexte sans nécessiter de croisement manuel complexe.

### Cas limites

- Roadie démarre alors que des fenêtres existent déjà : l'état initial doit produire un snapshot cohérent et éviter de rejouer des événements trompeurs.
- Une fenêtre disparaît entre sa détection et l'application d'une règle : Roadie doit abandonner l'action de façon observable.
- Deux règles se contredisent : Roadie doit appliquer une priorité explicite ou refuser la configuration.
- Un outil externe se connecte après plusieurs changements : il doit pouvoir récupérer un état initial avant les événements suivants.
- Un stage, desktop ou écran référencé par une commande n'existe plus : la commande doit échouer proprement et expliquer la cause.
- Les fenêtres système, panneaux temporaires, popups et fenêtres non gérables ne doivent pas polluer les règles ni les groupes.
- Les features dépendantes d'APIs privées macOS, de désactivation SIP, de contrôle natif des Spaces ou d'un compositor ne font pas partie du périmètre.

## Exigences *(obligatoire)*

### Exigences fonctionnelles

- **FR-001**: Roadie DOIT publier un catalogue documenté d'événements couvrant le cycle de vie des fenêtres, les changements de focus, les changements d'écran, les changements de desktop, les changements de stage, l'application d'un layout, l'échec d'un layout, l'application d'une règle et les commandes déclenchées par l'utilisateur.
- **FR-002**: Roadie DOIT permettre à un consommateur externe de s'abonner aux événements en direct et de recevoir un état initial lorsque cela est demandé.
- **FR-003**: Roadie DOIT maintenir des noms d'événements, des champs obligatoires et des garanties d'ordre suffisamment stables pour que des automatisations externes puissent s'y fier.
- **FR-004**: Roadie DOIT exposer des consultations d'état structurées pour les fenêtres, écrans, desktops, stages, contexte actif, règles, santé et événements récents.
- **FR-005**: Roadie DOIT fournir un système de règles capable de faire correspondre les fenêtres au minimum par identité d'application, titre, rôle ou catégorie de fenêtre, écran, desktop et contexte de stage.
- **FR-006**: Roadie DOIT prendre en charge des actions de règles pour exclure une fenêtre du tiling, assigner une fenêtre à un desktop ou un stage, sélectionner un comportement flottant, sélectionner un mode de layout, appliquer un comportement de gaps et marquer une fenêtre pour un futur workflow de type scratchpad.
- **FR-007**: Roadie DOIT valider les règles avant de les appliquer et signaler les critères non supportés, actions non supportées, priorités dupliquées et conflits ambigus.
- **FR-008**: Roadie DOIT enregistrer quelle règle, commande ou action utilisateur a causé un changement d'état visible lorsque cette information est disponible.
- **FR-009**: Roadie DOIT fournir des commandes power-user pour revenir au focus précédent, revenir au desktop précédent, déplacer un stage ou desktop entre écrans, aplatir un layout, choisir explicitement une orientation de split, contrôler la cible d'insertion et activer un comportement de zoom temporaire.
- **FR-010**: Roadie DOIT définir le comportement des commandes face aux fenêtres manquantes, fenêtres masquées, écrans déconnectés, stages inactifs et états persistés obsolètes.
- **FR-011**: Roadie DOIT prendre en charge les groupes de fenêtres comme concept utilisateur de premier niveau, incluant la création de groupe, l'ajout au groupe, le retrait du groupe, la navigation entre membres actifs, la dissolution du groupe et la persistance des memberships.
- **FR-012**: Roadie DOIT fournir assez de retour visuel et d'état pour les fenêtres groupées afin que l'utilisateur identifie le membre actif et l'appartenance au groupe sans ambiguïté.
- **FR-013**: Roadie DOIT préserver sa posture actuelle sans API privée et sans gestion des Spaces natifs pour cet ensemble de fonctionnalités.
- **FR-014**: Roadie DOIT rester utilisable sans daemon de raccourcis natif ; les intégrations via launchers externes, BetterTouchTool ou scripts shell restent de première classe.
- **FR-015**: Roadie DOIT documenter le contrat d'automatisation stable afin qu'un utilisateur puisse construire des intégrations sans lire le code source interne.
- **FR-016**: Roadie DOIT garantir que chaque tranche livrable indépendamment puisse être testée sans exiger que toutes les autres tranches soient terminées.

### Entités clés *(si la fonctionnalité implique des données)*

- **Événement Roadie**: Événement nommé émis par Roadie. Ses attributs clés incluent le nom, l'horodatage, le scope, la fenêtre concernée le cas échéant, le contexte actif le cas échéant, le résultat et la cause optionnelle.
- **Abonné aux événements**: Consommateur externe recevant les événements Roadie en direct. Ses attributs clés incluent les filtres d'abonnement, la préférence d'état initial et le cycle de vie de connexion.
- **Règle de fenêtre**: Association déclarée par l'utilisateur entre critères de correspondance et actions. Ses attributs clés incluent l'identifiant, la priorité, les critères, les actions, l'état d'activation et le résultat de validation.
- **Correspondance de règle**: Relation évaluée entre une règle et une fenêtre. Ses attributs clés incluent les champs qui correspondent, les champs ignorés et la décision finale.
- **Commande power-user**: Action de haut niveau déclenchée par l'utilisateur qui modifie le focus, le layout, le stage, le desktop ou le contexte d'écran. Ses attributs clés incluent le nom de commande, la cible, le scope et le résultat.
- **Groupe de fenêtres**: Ensemble de fenêtres partageant un même emplacement de layout. Ses attributs clés incluent l'identifiant du groupe, les fenêtres membres, le membre actif, le stage propriétaire et l'état de persistance.
- **Contrat d'automatisation**: Surface externe documentée incluant les noms d'événements, les champs de consultation d'état, le comportement des commandes et les attentes de compatibilité.

## Critères de succès *(obligatoire)*

### Résultats mesurables

- **SC-001**: Une barre de statut ou un script peut mettre à jour les indicateurs d'écran actif, desktop, stage et fenêtre focalisée en moins d'une seconde après un changement d'état Roadie, sans interroger l'état complet en boucle.
- **SC-002**: Au moins 90 % des cas d'automatisation courants identifiés dans la comparaison yabai/AeroSpace/Hyprland sont couverts par des événements, règles ou commandes documentés, hors fonctionnalités compositor ou Spaces natifs explicitement rejetées.
- **SC-003**: Un utilisateur peut exprimer au moins cinq politiques courantes de placement de fenêtres via des règles sans écrire de glue shell.
- **SC-004**: Les règles invalides sont détectées avant les actions runtime, avec une sortie de validation actionnable pour chaque règle invalide dans une configuration de test.
- **SC-005**: Les commandes power-user de retour focus, retour desktop, aplatissement et cible d'insertion réussissent dans des tests contrôlés et ne laissent aucun membership de fenêtre dupliqué ou orphelin.
- **SC-006**: Les groupes de fenêtres survivent au redémarrage du daemon dans un test contrôlé tout en préservant le membership du groupe et le membre actif lorsque les fenêtres existent encore.
- **SC-007**: Les workflows quotidiens existants de Roadie restent compatibles : tiling, stages, desktops virtuels, nav rail, focus follows mouse, bordures et commandes CLI actuelles continuent de passer leurs tests de régression.
- **SC-008**: Le contrat d'automatisation peut être consommé à partir de la seule documentation par un utilisateur techniquement compétent, sans inspecter les fichiers d'implémentation.

## Hypothèses

- Le travail sera livré en plusieurs tranches d'implémentation, pas comme un changement monolithique risqué.
- La publication d'événements et la consultation d'état constituent la première fondation, car les règles et intégrations ultérieures en dépendent.
- Roadie n'ajoutera pas de daemon de raccourcis natif dans cette roadmap ; les outils externes de déclenchement restent la couche prévue pour les bindings.
- Roadie ne gérera pas les Spaces natifs macOS, n'exigera pas de changement SIP et ne dépendra pas d'APIs privées d'écriture.
- Le chargement de plugins runtime est hors périmètre pour la première roadmap ; l'ouverture signifie d'abord événements, commandes, règles et documentation stables.
- Les fonctionnalités visuelles de compositor comme blur, ombres, transitions d'opacité et animations système sont hors périmètre sauf si macOS expose des capacités publiques sûres.
- Le window swallowing n'est pas inclus dans le premier passage, car l'inférence de processus parent est fragile sur macOS ; il pourra être réévalué après stabilisation des événements et règles.
- Les actions scratchpad peuvent être modélisées dans les règles avant que l'expérience utilisateur scratchpad complète existe.
