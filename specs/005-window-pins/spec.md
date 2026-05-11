# Spécification Fonctionnelle : Pins de Fenêtres

**Branche** : `030-window-pins`  
**Créée le** : 2026-05-11  
**Statut** : Brouillon  
**Entrée utilisateur** : "Ajouter des pins de fenêtres depuis le menu contextuel de barre de titre : pin sur une stage du même desktop, pin visible sur toutes les stages du desktop courant, pin visible sur tous les desktops, avec options de retrait du pin et sans re-tiler les fenêtres flottantes."

## Scénarios Utilisateur & Tests *(obligatoire)*

### Récit Utilisateur 1 - Pinner une fenêtre sur le desktop courant (Priorité : P1)

Un utilisateur veut garder une fenêtre utile visible lorsqu'il change de stage dans le même desktop, sans que cette fenêtre apparaisse dans les autres desktops Roadie.

**Pourquoi cette priorité** : C'est le besoin principal exprimé : garder une fenêtre de référence ou un panneau utile sous les yeux tout en changeant de contexte dans le même desktop, sans polluer les autres desktops.

**Test indépendant** : Avec une fenêtre visible, deux stages dans le même desktop et au moins un autre desktop, le test réussit si la fenêtre reste visible en changeant de stage dans le desktop courant, puis disparaît quand l'utilisateur change de desktop.

**Scénarios d'acceptation** :

1. **Étant donné** une fenêtre visible sur une stage active, **lorsque** l'utilisateur choisit "Pin sur ce desktop" depuis le menu de barre de titre, **alors** la fenêtre reste visible sur toutes les stages du desktop courant.
2. **Étant donné** une fenêtre pinée sur le desktop courant, **lorsque** l'utilisateur passe à un autre desktop Roadie, **alors** la fenêtre n'est plus visible.
3. **Étant donné** une fenêtre pinée sur le desktop courant, **lorsque** l'utilisateur revient au desktop d'origine, **alors** la fenêtre redevient visible sans changer de stage active.

---

### Récit Utilisateur 2 - Pinner une fenêtre sur tous les desktops Roadie du même écran (Priorité : P2)

Un utilisateur veut garder une fenêtre visible quel que soit le desktop Roadie actif sur le même écran, par exemple un outil de monitoring, une documentation ou une fenêtre de contrôle.

**Pourquoi cette priorité** : Ce mode couvre les fenêtres vraiment transverses, sans obliger l'utilisateur à les déplacer ou à les recréer dans chaque desktop.

**Test indépendant** : Avec deux desktops et plusieurs stages sur le même écran, le test réussit si la fenêtre reste visible après chaque changement de stage et de desktop, sans être dupliquée dans les listes ou menus.

**Scénarios d'acceptation** :

1. **Étant donné** une fenêtre visible sur une stage active, **lorsque** l'utilisateur choisit "Pin sur tous les desktops", **alors** la fenêtre reste visible lors des changements de stage et de desktop Roadie sur le même écran.
2. **Étant donné** une fenêtre pinée sur tous les desktops, **lorsque** l'utilisateur change plusieurs fois de stage et de desktop, **alors** la fenêtre conserve sa position et ne déclenche pas de réorganisation du layout.
3. **Étant donné** une fenêtre pinée sur tous les desktops, **lorsque** l'utilisateur la déplace manuellement, **alors** sa nouvelle position reste respectée lors des prochains changements de contexte.

---

### Récit Utilisateur 3 - Retirer un pin proprement (Priorité : P3)

Un utilisateur veut retirer le pin d'une fenêtre depuis le même menu et retrouver un comportement normal sans perdre la fenêtre ni provoquer de saut de layout.

**Pourquoi cette priorité** : Tout état persistant ou transversal doit être réversible directement par l'utilisateur, sinon la fonctionnalité devient vite confuse.

**Test indépendant** : En pinant une fenêtre puis en retirant le pin, le test réussit si la fenêtre redevient liée à une seule stage et suit à nouveau les règles normales de visibilité.

**Scénarios d'acceptation** :

1. **Étant donné** une fenêtre pinée sur le desktop courant, **lorsque** l'utilisateur choisit "Retirer le pin", **alors** la fenêtre reste sur la stage active et disparaît des autres stages du même desktop.
2. **Étant donné** une fenêtre pinée sur tous les desktops, **lorsque** l'utilisateur choisit "Retirer le pin", **alors** la fenêtre reste visible uniquement dans le contexte actif courant.
3. **Étant donné** une fenêtre non pinée, **lorsque** l'utilisateur ouvre le menu de barre de titre, **alors** les actions de pin sont proposées et l'action de retrait n'est pas présentée comme active.

---

### Cas Limites

- Une fenêtre déjà exclue du tiling doit pouvoir être pinée sans devenir tileable.
- Une fenêtre tileable pinée doit rester hors du calcul de layout pendant qu'elle est pinée, afin d'éviter les sauts de layout.
- Une fenêtre pinée puis fermée doit être retirée automatiquement des états de pin.
- Une fenêtre pinée déplacée vers une autre stage, un autre desktop ou un autre écran doit avoir un état de pin cohérent avec sa nouvelle destination.
- Une fenêtre pinée ne doit jamais apparaître plusieurs fois dans les menus de destination ou dans le rail.
- Si le menu de barre de titre est désactivé, aucun nouveau point d'entrée de pin n'est requis pour cette version.
- Les fenêtres système transitoires, dialogues, panneaux de sauvegarde et popups ne doivent pas être pinées par accident.

## Exigences *(obligatoire)*

### Exigences Fonctionnelles

- **FR-001** : Roadie DOIT permettre à l'utilisateur de pinner une fenêtre éligible afin qu'elle reste visible sur toutes les stages du desktop courant uniquement.
- **FR-002** : Roadie DOIT permettre à l'utilisateur de pinner une fenêtre éligible afin qu'elle reste visible sur tous les desktops Roadie du même écran.
- **FR-003** : Roadie DOIT fournir une action claire pour retirer un pin existant d'une fenêtre éligible.
- **FR-004** : Roadie DOIT exposer les actions de pin et de retrait de pin depuis le menu contextuel de barre de titre existant lorsque ce menu est activé.
- **FR-005** : Roadie DOIT distinguer clairement, dans les libellés utilisateur, un pin limité au desktop courant et un pin valable sur tous les desktops du même écran.
- **FR-006** : Roadie DOIT préserver la position et la taille courantes d'une fenêtre pinée, sauf si l'utilisateur la déplace ou la redimensionne.
- **FR-007** : Roadie DOIT garder les fenêtres pinées hors des calculs automatiques de layout tant qu'elles sont pinées.
- **FR-008** : Roadie DOIT continuer à cacher une fenêtre pinée lorsque son scope de pin ne couvre pas le desktop ou la stage active.
- **FR-009** : Roadie DOIT nettoyer automatiquement l'état de pin quand la fenêtre pinée se ferme ou ne peut plus être retrouvée.
- **FR-010** : Roadie DOIT empêcher qu'une fenêtre pinée ait plusieurs propriétaires dans les stages, desktops ou écrans.
- **FR-011** : Roadie DOIT garder inchangés les comportements de changement de stage, changement de desktop et fenêtres flottantes pour les fenêtres non pinées.
- **FR-012** : Roadie DOIT éviter de proposer des actions de pin pour les panneaux système transitoires où le pin créerait un comportement confus ou instable.
- **FR-013** : Roadie DOIT rendre l'état de pin courant compréhensible depuis le menu avant que l'utilisateur ne le modifie.

### Entités Clés

- **Fenêtre pinée** : fenêtre sélectionnée par l'utilisateur pour rester visible au-delà de son appartenance normale à une stage. Ses attributs clés sont la fenêtre cible, le scope de pin et le dernier placement connu.
- **Scope de pin** : limite de visibilité choisie par l'utilisateur. Les scopes supportés pour cette fonctionnalité sont le desktop courant et tous les desktops du même écran.
- **État de pin** : état durable déterminant si une fenêtre est pinée, comment elle doit être affichée ou cachée pendant les changements de contexte, et quand cet état doit être supprimé.
- **Fenêtre éligible** : fenêtre utilisateur que Roadie peut gérer sans traiter les panneaux transitoires comme des éléments de travail persistants.

## Critères de Succès *(obligatoire)*

### Résultats Mesurables

- **SC-001** : En test manuel, une fenêtre pinée sur le desktop courant reste visible sur 10 changements de stage consécutifs dans le même desktop et est cachée sur 10 bascules consécutives vers un autre desktop.
- **SC-002** : En test manuel, une fenêtre pinée sur tous les desktops reste visible sur 10 changements de desktop consécutifs et 10 changements de stage consécutifs sur le même écran.
- **SC-003** : Le retrait d'un pin ramène la fenêtre à une visibilité de contexte unique en moins de 2 secondes après l'action utilisateur.
- **SC-004** : Le pin et le retrait de pin ne déplacent pas les fenêtres tiled non concernées dans au moins 95 % des vérifications répétées de changement de stage et de desktop.
- **SC-005** : Les fenêtres pinées fermées sont retirées du comportement visible de pin sans action utilisateur au prochain refresh normal de Roadie.
- **SC-006** : Les utilisateurs peuvent identifier l'état de pin actif et choisir la bonne action de pin depuis le menu de barre de titre sans connaître les IDs internes des stages.

## Hypothèses

- Le pin est limité aux fenêtres que Roadie suit déjà comme appartenant à un écran et à un contexte utilisateur.
- "Tous les desktops" signifie tous les desktops virtuels Roadie du même écran ; déplacer une fenêtre pinée vers un autre écran reste géré par les actions de déplacement existantes.
- Une fenêtre pinée se comporte visuellement comme une fenêtre flottante, pas comme une tuile supplémentaire dans le layout courant.
- Le menu contextuel de barre de titre reste le point d'entrée principal de cette fonctionnalité.
- Les actions de pin sont volontairement séparées des actions d'assignation vers stage ou desktop.
- Les garde-fous existants pour les panneaux transitoires et popups système continuent de s'appliquer.
