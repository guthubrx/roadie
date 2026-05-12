# Spécification Fonctionnelle : Parking et restauration des stages d'écrans

**Branche**: `031-display-stage-parking`  
**Créée le**: 2026-05-12  
**Statut**: Brouillon  
**Entrée**: Description utilisateur : "Quand un écran est débranché, les stages qui étaient présents sur cet écran doivent être rapatriées sur l'écran restant comme nouvelles stages. Si l'écran est rebranché, Roadie doit se souvenir de leur origine et remettre les mêmes stages sur l'écran revenu, dans l'état courant, sans perdre les changements faits pendant l'absence."

## Parcours Utilisateur et Tests

### Parcours utilisateur 1 - Rapatrier les stages d'un écran débranché (Priorité: P1)

En tant qu'utilisateur avec deux écrans, je veux pouvoir débrancher un écran sans perdre mes fenêtres ni voir toutes mes fenêtres mélangées dans une seule stage, afin de continuer à travailler immédiatement sur l'écran restant.

**Pourquoi cette priorité**: C'est la protection principale contre la casse de l'organisation multi-écran. Sans elle, un simple débranchement d'écran peut rendre Roadie stressant et difficile à récupérer.

**Test indépendant**: Peut être testé avec deux écrans, plusieurs stages non vides sur l'écran secondaire, puis débranchement de cet écran. La valeur est livrée si les fenêtres restent visibles et séparées par stages sur l'écran restant.

**Scénarios d'acceptation**:

1. **Étant donné** deux écrans avec trois stages non vides sur l'écran secondaire, **lorsque** l'écran secondaire est débranché, **alors** l'écran restant affiche trois stages rapatriées correspondant aux trois stages d'origine.
2. **Étant donné** une stage nommée "Perso" sur l'écran débranché, **lorsque** elle est rapatriée, **alors** son nom reste compréhensible et elle est identifiable comme provenant de l'écran disparu.
3. **Étant donné** une stage active sur l'écran restant avant le débranchement, **lorsque** l'autre écran disparaît, **alors** cette stage active n'est pas remplacée par un mélange de toutes les fenêtres rapatriées.

---

### Parcours utilisateur 2 - Restaurer les stages quand l'écran revient (Priorité: P2)

En tant qu'utilisateur qui rebranche son écran, je veux que les stages rapatriées retournent automatiquement sur leur écran d'origine reconnu, afin de retrouver l'organisation multi-écran que j'avais avant le débranchement.

**Pourquoi cette priorité**: Le rapatriement seul évite la perte immédiate, mais l'expérience complète exige que le retour à deux écrans soit aussi fluide que le départ à un écran.

**Test indépendant**: Peut être testé en débranchant un écran, en vérifiant le parking des stages, puis en rebranchant le même écran. La valeur est livrée si les stages retournent sur l'écran revenu sans reconstruction manuelle.

**Scénarios d'acceptation**:

1. **Étant donné** des stages rapatriées depuis un écran externe, **lorsque** ce même écran est rebranché, **alors** ces stages sont restaurées sur l'écran externe reconnu.
2. **Étant donné** une stage rapatriée dont l'utilisateur a changé le contenu pendant l'absence de l'écran, **lorsque** l'écran revient, **alors** la version actuelle de cette stage est restaurée, pas une ancienne copie.
3. **Étant donné** un écran rebranché que Roadie ne peut pas reconnaître avec confiance, **lorsque** Roadie hésite entre plusieurs origines possibles, **alors** il ne déplace pas destructivement les stages et conserve l'état rapatrié visible.

---

### Parcours utilisateur 3 - Garder un état compréhensible et récupérable (Priorité: P3)

En tant qu'utilisateur, je veux que Roadie garde une trace claire des stages rapatriées et évite les bascules répétées ou les corrections automatiques agressives, afin que le système reste prévisible même quand les écrans changent vite.

**Pourquoi cette priorité**: Les changements d'écran peuvent produire des événements instables. L'utilisateur doit toujours pouvoir comprendre où sont ses fenêtres et récupérer son organisation.

**Test indépendant**: Peut être testé avec des débranchements/rebranchements rapides, des changements de résolution et des stages modifiées pendant le mode rapatrié.

**Scénarios d'acceptation**:

1. **Étant donné** un écran branché/débranché plusieurs fois rapidement, **lorsque** Roadie reçoit plusieurs changements d'écran rapprochés, **alors** il attend un état stable avant de déplacer les stages.
2. **Étant donné** des stages rapatriées depuis un écran absent, **lorsque** l'utilisateur les renomme, les réordonne ou y déplace des fenêtres, **alors** ces changements restent attachés aux stages rapatriées.
3. **Étant donné** un échec de déplacement d'une fenêtre pendant le rapatriement, **lorsque** Roadie ne peut pas appliquer le placement attendu, **alors** la fenêtre reste visible ou récupérable et l'état de stage n'est pas supprimé.

### Cas Limites

- Un écran externe revient avec un identifiant différent mais un nom, une résolution ou une position comparable.
- Deux écrans externes similaires sont branchés successivement et Roadie ne peut pas déterminer lequel correspond à l'écran disparu.
- Une stage rapatriée porte le même nom qu'une stage déjà présente sur l'écran restant.
- L'utilisateur ferme toutes les fenêtres d'une stage rapatriée avant de rebrancher l'écran.
- L'utilisateur crée de nouvelles fenêtres dans une stage rapatriée pendant que l'écran d'origine est absent.
- Plusieurs écrans sont débranchés ou rebranchés en rafale.
- Une fenêtre refuse d'être déplacée ou redimensionnée pendant le rapatriement.
- Une fenêtre est en plein écran natif ou dans un état système particulier pendant le changement d'écran.
- L'écran restant change aussi de rôle principal pendant l'opération.

## Exigences

### Exigences Fonctionnelles

- **FR-001**: Roadie DOIT attendre que la topologie des écrans soit stable avant de changer les affectations de stages après l'apparition ou la disparition d'un écran.
- **FR-002**: Roadie DOIT préserver l'origine de chaque stage qui appartenait à un écran disparu.
- **FR-003**: Roadie DOIT déplacer chaque stage non vide d'un écran disparu vers une stage rapatriée distincte sur un écran restant.
- **FR-004**: Roadie DOIT préserver le nom, l'ordre relatif, le mode d'organisation, les fenêtres, le focus et les groupes de fenêtres quand une stage est rapatriée.
- **FR-005**: Roadie DOIT permettre de distinguer les stages rapatriées des stages natives de l'écran restant.
- **FR-006**: Roadie NE DOIT PAS fusionner toutes les fenêtres d'un écran disparu dans la stage active de l'écran restant.
- **FR-007**: Roadie DOIT garder toutes les fenêtres vivantes de l'écran disparu visibles ou directement récupérables après rapatriement.
- **FR-008**: L'utilisateur DOIT pouvoir utiliser les stages rapatriées normalement pendant l'absence de l'écran d'origine : bascule, renommage, réordonnancement, déplacement de fenêtres et changement de mode d'organisation.
- **FR-009**: Roadie DOIT préserver les changements effectués par l'utilisateur sur les stages rapatriées pendant l'absence de l'écran d'origine.
- **FR-010**: Quand un écran disparu est reconnu à nouveau, Roadie DOIT restaurer ses stages rapatriées sur cet écran en utilisant leur état courant.
- **FR-011**: Si Roadie ne peut pas associer avec confiance un écran revenu à une origine rapatriée, il DOIT laisser les stages rapatriées visibles et éviter toute restauration automatique destructive.
- **FR-012**: Roadie DOIT préserver autant que possible la stage active et l'ordre des stages déjà présentes sur les écrans restants lors de l'ajout des stages rapatriées.
- **FR-013**: Roadie DOIT gérer les stages vides des écrans disparus sans créer de clutter visible inutile, tout en conservant assez d'information pour restaurer l'organisation plus tard.
- **FR-014**: Roadie DOIT éviter les oscillations répétées de placement des stages pendant les changements d'écran rapides.
- **FR-015**: Roadie DOIT exposer assez d'information d'état pour que l'utilisateur ou un diagnostic sache si une stage est native, rapatriée ou restaurée.

### Entités Clés

- **Écran logique**: Représente un écran reconnu par Roadie au-delà de l'identifiant instable fourni par le système. Il porte l'historique utile pour reconnaître un écran qui revient.
- **Instance d'écran active**: Représente l'écran actuellement visible et utilisable pendant une session.
- **Stage rapatriée**: Stage temporairement hébergée sur un autre écran parce que son écran d'origine est absent.
- **Origine de stage**: Trace de l'écran logique, du desktop, de l'ordre et du contexte d'où vient une stage rapatriée.
- **Session de parking**: Ensemble cohérent de stages rapatriées depuis un écran disparu et restaurables quand cet écran revient.

## Critères de Succès

### Résultats Mesurables

- **SC-001**: Après débranchement d'un écran avec des fenêtres actives, 100% des fenêtres vivantes restent visibles ou récupérables sans action manuelle complexe.
- **SC-002**: Dans 95% des débranchements/rebranchements ordinaires d'un même écran, les fenêtres reviennent dans des stages correspondant à leur organisation avant le débranchement.
- **SC-003**: Le rapatriement initial des stages devient stable en moins de 5 secondes après la stabilisation du système d'affichage.
- **SC-004**: Un rebranchement d'écran reconnu restaure les stages parkées en moins de 5 secondes après la stabilisation du système d'affichage.
- **SC-005**: Aucun scénario nominal de débranchement ne mélange toutes les fenêtres de l'écran disparu dans une seule stage existante.
- **SC-006**: Les utilisateurs peuvent continuer à travailler sur les stages rapatriées sans reconstruire manuellement leur organisation de stages, leurs placements de fenêtres ou leurs modes de layout.
- **SC-007**: Les changements effectués pendant l'absence de l'écran sont conservés dans 100% des cas où les fenêtres concernées restent vivantes.
- **SC-008**: Les changements d'écran rapides ne provoquent pas plus d'un rapatriement ou d'une restauration finale visible par période de stabilisation.

## Hypothèses

- L'utilisateur dispose toujours d'au moins un écran restant quand un écran est débranché.
- Les stages non vides doivent être visibles après rapatriement ; les stages vides ou purement configurées peuvent être conservées en mémoire sans être affichées immédiatement.
- Si plusieurs écrans restants sont disponibles, Roadie choisit l'écran actif ou principal comme destination par défaut, sauf si un écran cible plus pertinent est évident.
- La reconnaissance d'un écran qui revient est probabiliste et conservatrice : en cas de doute, Roadie privilégie la non-destruction plutôt qu'une restauration automatique risquée.
- Les fenêtres fermées pendant l'absence de l'écran ne sont pas recréées au rebranchement.
- Cette fonctionnalité concerne l'organisation Roadie des stages et fenêtres ; elle ne prétend pas contrôler les espaces natifs du système au-delà de ce que Roadie gère déjà.
