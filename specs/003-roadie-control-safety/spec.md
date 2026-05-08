# Spécification Fonctionnelle : Roadie Control & Safety

**Branche fonctionnalité**: `003-roadie-control-safety`  
**Créé le**: 2026-05-08  
**Statut**: Brouillon  
**Entrée**: Description utilisateur : "Oublier les animations et shipper Roadie Control Center, safe config reload, restore safety, transient system windows, layout persistence v2, puis width presets/nudge."

## Scénarios Utilisateur & Tests *(obligatoire)*

### User Story 1 - Piloter Roadie depuis macOS (Priorité : P1)

Un utilisateur qui ne veut pas tout faire au terminal peut voir l'etat de Roadie depuis la barre de menus, ouvrir une fenetre de reglages, recharger la configuration et acceder aux diagnostics courants.

**Pourquoi cette priorité**: C'est le MVP visible. Sans centre de controle, les autres protections restent difficiles a comprendre, verifier et adopter.

**Test indépendant**: Lancer Roadie, ouvrir l'item de barre de menus, verifier que l'etat courant, les chemins utiles, les actions reload/status et les reglages essentiels sont accessibles sans commande shell.

**Scénarios d'acceptation**:

1. **Étant donné que** Roadie tourne, **quand** l'utilisateur ouvre le menu Roadie, **alors** il voit un statut clair du daemon, de la configuration chargee, du desktop/stage actif et des dernieres erreurs importantes.
2. **Étant donné que** l'utilisateur ouvre les reglages, **quand** il modifie une option supportee, **alors** Roadie sauvegarde la configuration et indique si elle a ete appliquee ou rejetee.
3. **Étant donné que** Roadie rencontre une erreur de config ou de permission, **quand** l'utilisateur ouvre le centre de controle, **alors** l'erreur est visible avec une action de diagnostic ou de reload.

---

### User Story 2 - Recharger la configuration sans casser la session (Priorité : P1)

Un utilisateur peut modifier `roadies.toml` puis demander ou attendre un reload ; Roadie applique seulement une configuration valide et conserve la precedente en cas d'erreur.

**Pourquoi cette priorité**: La configuration devient plus riche. Un reload dangereux peut casser le tiler ou rendre les fenetres incontrolables.

**Test indépendant**: Charger une config valide, puis remplacer le fichier par une config invalide ; Roadie doit refuser le reload, conserver l'ancien comportement et exposer l'erreur.

**Scénarios d'acceptation**:

1. **Étant donné qu'** une configuration valide est active, **quand** un fichier invalide est sauvegarde, **alors** Roadie conserve la configuration precedente et publie une erreur de reload.
2. **Étant donné qu'** une configuration corrigee est sauvegardee, **quand** le reload est relance, **alors** Roadie applique la nouvelle configuration sans redemarrage complet.
3. **Étant donné que** plusieurs reloads arrivent rapidement, **quand** Roadie traite les changements, **alors** seul le dernier etat valide devient actif.

---

### User Story 3 - Restaurer les fenetres apres arret ou crash (Priorité : P1)

Un utilisateur peut quitter Roadie ou subir un crash sans laisser des fenetres cachees, parquees, hors ecran ou associees a un etat de layout inutilisable.

**Pourquoi cette priorité**: C'est une garantie de securite operationnelle. Un window manager doit echouer proprement.

**Test indépendant**: Simuler un etat avec fenetres de stages/desktops/groups, arreter Roadie normalement puis simuler une mort du daemon ; les fenetres doivent redevenir visibles et recuperables.

**Scénarios d'acceptation**:

1. **Étant donné que** Roadie gere des fenetres visibles et masquees, **quand** l'utilisateur quitte Roadie proprement, **alors** les fenetres sont restaurees dans un etat visible et utilisable.
2. **Étant donné que** Roadie meurt brutalement, **quand** le watcher detecte l'absence du daemon, **alors** il restaure les fenetres a partir du dernier snapshot de securite.
3. **Étant donné que** le snapshot de restauration est absent ou corrompu, **quand** le watcher s'execute, **alors** il echoue sans aggraver l'etat des fenetres et signale l'incident.

---

### User Story 4 - Respecter les fenetres systeme transitoires (Priorité : P2)

Roadie detecte les sheets, dialogues, popovers, menus et panneaux open/save macOS ; il suspend temporairement les actions de tiling/focus qui risquent de les deplacer ou cacher.

**Pourquoi cette priorité**: Ces fenetres sont frequentes et sensibles. Les gerer mal donne une impression de bug ou peut bloquer l'utilisateur dans une app.

**Test indépendant**: Ouvrir un dialogue systeme dans une app, provoquer un tick Roadie ou un changement de focus, verifier que Roadie reste en retrait puis reprend apres fermeture.

**Scénarios d'acceptation**:

1. **Étant donné qu'** un dialogue systeme est actif, **quand** Roadie recoit des evenements de focus/move/resize, **alors** il suspend les adaptations non essentielles.
2. **Étant donné qu'** un panneau open/save est actif, **quand** il est hors ecran ou cache par erreur, **alors** Roadie tente de le rendre visible sans manipuler les fenetres applicatives normales.
3. **Étant donné que** le dialogue est ferme, **quand** Roadie rescane l'environnement, **alors** le tiling reprend sans perdre l'etat courant.

---

### User Story 5 - Restaurer un layout via identite stable (Priorité : P2)

Apres redemarrage, Roadie peut rapprocher les fenetres courantes de l'ancien etat en utilisant une identite stable, pas seulement des IDs volatils.

**Pourquoi cette priorité**: Les IDs de fenetres changent entre sessions. Une persistance v2 ameliore la continuite des stages, groups, desktops et intentions de layout.

**Test indépendant**: Sauvegarder un layout, redemarrer des apps avec des IDs differents mais des identites similaires, puis verifier que Roadie reconstruit les associations attendues.

**Scénarios d'acceptation**:

1. **Étant donné qu'** un snapshot contient bundle ID, app name, title et attributs AX pertinents, **quand** les fenetres reapparaissent avec de nouveaux IDs, **alors** Roadie retrouve les correspondances sans doublons.
2. **Étant donné que** plusieurs fenetres ont une identite proche, **quand** Roadie restaure l'etat, **alors** il applique une strategie deterministe et evite les affectations multiples.
3. **Étant donné qu'** aucune correspondance fiable n'existe, **quand** Roadie restaure, **alors** il ignore l'entree plutot que d'appliquer un layout incorrect.

---

### User Story 6 - Ajuster les largeurs par presets/nudge (Priorité : P3)

Un utilisateur power-user peut ajuster rapidement la largeur du layout actif via des presets ou des nudges, sans modifier manuellement tout le fichier de configuration.

**Pourquoi cette priorité**: C'est utile, mais moins critique que la securite, la config et le controle. A implementer apres stabilisation des cinq premiers blocs.

**Test indépendant**: Sur un layout avec plusieurs fenetres, appliquer un preset ou un nudge et verifier que le resultat est persiste comme intention utilisateur reversible.

**Scénarios d'acceptation**:

1. **Étant donné qu'** une fenetre active tilee, **quand** l'utilisateur applique le preset suivant, **alors** Roadie ajuste la largeur pertinente sans casser l'arbre.
2. **Étant donné que** plusieurs fenetres tilees, **quand** l'utilisateur applique un nudge global, **alors** Roadie ajuste les ratios concernes dans les limites autorisees.
3. **Étant donné que** le layout courant ne supporte pas l'ajustement demande, **quand** la commande est lancee, **alors** Roadie renvoie une erreur explicite sans modifier l'etat.

### Cas Limites

- Le Control Center est ouvert alors que `roadied` ne tourne pas.
- Le fichier de configuration est supprime, deplace ou partiellement ecrit pendant un reload.
- Deux sauvegardes de config arrivent pendant qu'un reload est deja en cours.
- Le watcher de crash demarre mais le snapshot de restauration est incomplet.
- Une fenetre systeme transitoire n'a pas de role AX standard mais appartient au service open/save d'Apple.
- Deux fenetres partagent le meme bundle ID et le meme titre.
- Les width presets sont vides, non tries, hors limites ou incompatibles avec le layout actif.

## Exigences *(obligatoire)*

### Exigences Fonctionnelles

- **FR-001**: Roadie DOIT fournir un centre de controle macOS accessible depuis la barre de menus.
- **FR-002**: Le centre de controle DOIT exposer la sante du daemon, l'etat de la configuration active, le resume desktop/stage actif, les erreurs recentes de reload et les actions courantes.
- **FR-003**: Les utilisateurs DOIVENT pouvoir ouvrir une fenetre de reglages depuis le centre de controle.
- **FR-004**: Les utilisateurs DOIVENT pouvoir declencher un reload de configuration, reappliquer le layout, ouvrir/reveler la config et ouvrir/reveler l'etat depuis le centre de controle.
- **FR-005**: Roadie DOIT valider une nouvelle configuration avant de la rendre active.
- **FR-006**: Roadie DOIT conserver la configuration valide precedente quand la validation d'un reload echoue.
- **FR-007**: Roadie DOIT publier des evenements observables pour les reloads de configuration demandes, appliques et echoues.
- **FR-008**: Roadie DOIT conserver un snapshot de securite suffisant pour recuperer les fenetres gerees apres un arret normal ou un crash du daemon.
- **FR-009**: Roadie DOIT restaurer les fenetres gerees dans un etat visible et utilisable lors d'un arret normal quand la restauration de securite est activee.
- **FR-010**: Roadie DOIT fournir un watcher de crash capable de restaurer les fenetres si le processus daemon disparait de facon inattendue.
- **FR-011**: Roadie DOIT detecter les fenetres systeme macOS transitoires, dont sheets, dialogues, popovers, menus et panneaux open/save.
- **FR-012**: Roadie DOIT suspendre les actions non essentielles de tiling/focus pendant qu'une fenetre systeme transitoire est active.
- **FR-013**: Roadie DOIT tenter une recuperation sure pour les fenetres transitoires cachees ou hors ecran.
- **FR-014**: Roadie DOIT persister des donnees d'identite layout qui survivent aux changements d'ID de fenetre volatils.
- **FR-015**: Roadie DOIT restaurer stages, desktops, groups et intentions de layout avec une identite de fenetre stable quand la confiance est suffisante.
- **FR-016**: Roadie DOIT eviter les correspondances d'identite dupliquees ou ambiguës pendant la restauration.
- **FR-017**: Roadie DOIT supporter des commandes de preset de largeur et de nudge de largeur pour les layouts compatibles.
- **FR-018**: Roadie DOIT rejeter les changements de largeur qui ne peuvent pas etre appliques surement au layout courant.
- **FR-019**: Roadie DOIT exposer tous les nouveaux comportements visibles utilisateur via tests, etat CLI/query ou evenements afin qu'ils soient verifiables sans inspection visuelle uniquement.
- **FR-020**: Roadie NE DOIT PAS introduire d'animations de fenetres dans cette session.
- **FR-021**: Roadie NE DOIT PAS dependre des APIs privees SkyLight ou MultitouchSupport pour ces fonctionnalites.

### Entités Clés *(inclure si la fonctionnalité implique des données)*

- **ControlCenterState**: Snapshot displayed by the menu bar UI: daemon health, config state, active workspace context, recent errors and action availability.
- **ConfigReloadState**: Current config path, active version, pending version, validation result and last error.
- **RestoreSafetySnapshot**: Last known recoverable state for managed windows, including frames, visibility, stage/desktop/group membership and capture time.
- **WindowIdentityV2**: Stable matching identity built from bundle ID, app name, title, role/subrole and optional process/window metadata.
- **TransientWindowState**: Detection result for active system windows, including recoverability and reason for pause.
- **WidthAdjustmentIntent**: Preset ou nudge de largeur demande par l'utilisateur, avec scope et contraintes de ratio resultantes.

## Critères de Succès *(obligatoire)*

### Résultats Mesurables

- **SC-001**: Un utilisateur peut installer/demarrer Roadie et verifier le statut daemon/config/layout depuis la barre de menus en moins de 30 secondes sans taper de commande de diagnostic.
- **SC-002**: Les reloads de config invalides preservent la configuration active precedente dans 100% des cas de test automatises.
- **SC-003**: L'arret normal restaure toutes les fenetres de test gerees dans des frames visibles dans 100% des scenarios de restauration automatises.
- **SC-004**: La restauration par watcher de crash se termine en moins de 2 secondes apres disparition du daemon dans les tests automatises de cycle de vie processus.
- **SC-005**: La detection de fenetre systeme transitoire empeche les changements de tiling pendant les scenarios sheet/dialog/open-save actifs dans les tests automatises de simulation AX.
- **SC-006**: La persistance layout v2 restaure les correspondances de fenetres non ambiguës apres redemarrage dans au moins 95% des cas de fixtures deterministes.
- **SC-007**: Les commandes width preset/nudge appliquent un ajustement valide ou renvoient une erreur structuree dans 100% des tests de commande.
- **SC-008**: La fonctionnalite complete passe `make build` et `make test` avant que l'implementation soit consideree terminee.

## Hypothèses

- Roadie remains a macOS Swift package with CLI, daemon and AppKit/SwiftUI surfaces.
- BetterTouchTool remains a supported primary hotkey path; this session does not add a full native hotkey daemon.
- DMG and manual install paths remain separate from the feature implementation, except documentation updates if needed.
- Animations are explicitly out of scope for this session.
- Private macOS frameworks are out of scope for core behavior; public Accessibility/AppKit APIs are preferred.
- Width presets/nudge are last priority and may be deferred if earlier safety stories reveal more work than expected.
