# Implémentation — session 027

**Statut : clôturée, installée et validée.**

La session a été validée par « Go, avec des agents ». Elle couvre l'application
immédiate des réglages, l'édition intégrée des collections et les familles de
police indépendantes de Caps+F. Aucune nouvelle release n'est prévue.

## Diagnostic initial

Les champs ordinaires attendaient Retour ou la perte du focus, alors que les
tailles de police suivaient déjà la saisie. Le tiler n'écoutait pas directement
les notifications des paramètres. Une marge modifiée pouvait donc attendre
un événement AX ou le filet périodique. Les exceptions par côté et écran peuvent
également conserver leur priorité sur une marge générale : cette priorité reste
intentionnelle et doit être expliquée dans la fenêtre.

Douze entrées du catalogue renvoyaient au fichier externe. Les noms des stages
configurés étaient appliqués seulement à leur création ou à leur nom initial.

## Quatre lots réalisés

1. **Configuration et collections.** Contrat typé, lecture et écriture des douze
   entrées, validation, conservation ciblée des commentaires et champs inconnus,
   détection des conflits, sauvegarde et remplacement atomique.
2. **Fenêtre.** Saisie scalaire immédiate avec conservation des brouillons,
   éditeurs structurés pour les listes et lignes courantes, éditeur avancé intégré
   pour les structures complexes et la correction d'une configuration invalide.
   Les collections restent dans leurs catégories normales. Le calcul `hasDrafts`
   distingue les brouillons non appliqués des valeurs déjà sauvegardées.
   Une saisie déjà sauvegardée ne réécrit pas un changement externe lors du retour
   du focus. Les critères connus vides restent présents si une autre valeur change.
3. **Application au daemon.** Notification avec chemin et identifiant, filtrage
   des changements effectifs, TickScheduler, traitement précis du pas de marge
   d'un point et mise à jour transactionnelle des noms de stages modifiés.
4. **Polices Caps+F.** Familles de saisie et de suggestions indépendantes, choix
   parmi les familles installées, tailles existantes conservées et secours système.

## Garanties de l'application immédiate

La validation sémantique porte sur le fichier principal et les fragments générés.
Elle utilise le chemin logique de configuration, y compris à travers un lien
symbolique, pour conserver la résolution correcte des fichiers associés.

Le contrôleur compare les domaines de la configuration active. Il résout les
liens symboliques et ignore une écriture d'un autre fichier. Un changement de
police seul ne demande pas de retuilage, y compris avec l'identifiant `*`.
Le signal passe par NotificationCenter dans un même processus et par
DistributedNotificationCenter entre les composants modulaires. La comparaison
des domaines rend les deux réceptions idempotentes : un signal doublé ne produit
ni deuxième passe ni deuxième renommage de stage.

Une modification de géométrie invalide les intents non zoomés, puis demande une
passe regroupée par TickScheduler. Les scopes concernés disposent d'une précision
temporaire dont l'avancement est suivi par fenêtre. Une demande non tentée reste
en attente des gardes ou du budget d'écriture. Elle n'est pas consommée seulement
parce qu'une passe a eu lieu. Les protections de geste, veille et transition restent
actives. La grâce de redimensionnement manuel de 0,35 s garde sa priorité.

Après une écriture, le cadre réel fournit la preuve du résultat. Un écart ou un
résultat inconnu permet une seule reprise, après une échéance courte de 0,1 s
intégrée au planificateur. Une fenêtre déjà arrivée à la cible ne reçoit aucune
nouvelle écriture. Un vrai cadre contraint suit le traitement existant des refus.
Un scope devenu inactif conserve ses intents et sa reprise bornée jusqu'à sa
réactivation. La tolérance ordinaire des événements AX reste à 2 points. Ce suivi
n'ajoute aucune boucle d'écriture sans borne et ne dépasse aucun budget.

La quatrième revue a demandé une vérification des transitions avant la reprise.
Les tests ont reproduit une échéance passée persistante quand le stage restait
actif mais vide ou passait en zoom ordinaire. Le réveil est désormais suspendu
dans ces cas. La demande reste disponible à la sortie du zoom ou au retour d'une
fenêtre. Le zoom réservant le rail garde son application géométrique.

Les arbres, choix de zoom et cadres de restauration sont conservés. Le zoom
réservant le rail recalcule son conteneur selon la nouvelle configuration.
Le zoom plein écran ordinaire garde son comportement plein écran.

Pour les noms de stages, seules les définitions ajoutées ou dont le nom a changé
renomment les stages existants. Les autres noms personnalisés restent intacts.
Une suppression ou réidentification de définition ne déplace aucun membre et ne
supprime aucun stage. Une erreur de persistance est journalisée ; elle ne produit
ni deuxième notification des paramètres ni boucle de nouvelle tentative.

## Vérifications acquises et restantes

- La suite complète finale a passé **1 440 tests Swift dans 154 suites**, en **6,943 s**.
  Résultat consigné dans `/private/tmp/roadie-027-final-tests.log`.
- Les tests couvrent notamment la saisie valide et les brouillons, les collections,
  les conflits, les polices et leur secours, les changements de marge 6→7 et
  6,25→7,25, la priorité des exceptions d'écran et la conservation des stages.
  Le test IPC utilise un véritable processus enfant JXA pour publier le signal
  distribué. La garde de redimensionnement de 0,35 s est également vérifiée.
  Les régressions vérifient aussi la reprise bornée après une première écriture
  ignorée, l'attente des gardes et du budget, la conservation d'un scope inactif,
  les conflits après saisie sauvegardée, les fragments générés via lien symbolique
  et la conservation des critères connus vides.
- **20 rendus hors écran ont été actualisés et inspectés**, notamment à 760 px
  de largeur et avec des polices de 24 points. Le rendu réel sur l'écran utilisateur
  est confirmé par l'essai utilisateur.
- Les constats de niveau élevé et moyen de la première revue **027-1 sont corrigés**.
  La quatrième revue **027-4 confirme les corrections précédentes**. Les quatre
  variantes de transition vide/zoomé ont échoué avant la correction ciblée, puis
  passé avec elle pour les modes BSP et BSP spatial. La suite runtime ciblée passe :
  **12 tests dans une suite, en 0,477 s**. Journaux :
  `/private/tmp/roadie-027-retry-transition-red.log` et
  `/private/tmp/roadie-027-retry-transition-green.log`.
  La suite complète finale inclut ce dernier correctif et passe.
- L'installation finale et `make restart` ont réussi. Le daemon est actif sous
  le PID 47508 depuis le 14 octobre 2026 à 04:25:59 UTC. Les quatre contrôles
  de santé sont OK : autorisations Accessibilité et capture d'écran accordées,
  configuration valide. Le certificat est conservé, empreinte SHA
  `78a75e8032f190a20072eb91cc2919aac344ef78`.
- Cette installation inclut le dernier correctif de transition. Sa santé est vérifiée.
- Validation utilisateur : « Oui, tout fonctionne ». Les espacements sans Retour,
  les listes et noms de stages, les polices Caps+F immédiates et la fluidité sont confirmés.
- Commit de livraison : `6190f4de`, fusionné dans `main` sans conflit.
- Les branches fusionnées 026 et 027 sont supprimées. Le worktree lié à la
  conversation et sa branche 025 sont conservés et alignés sur `main`.

## Limites connues

Les textes gérés par macOS gardent leur police système. Les moteurs de disposition
conservent leurs arrondis de cadres ; une valeur fractionnaire n'implique pas un
placement sous-pixel de toutes les fenêtres. Les commandes libres des signaux
disposent d'un éditeur intégré, mais cette session n'ajoute pas d'exécuteur de hooks.
Les actions de règles `layout` et `gap_override` sont enregistrées mais n'ont pas
d'effet géométrique. L'aide de leur éditeur indique explicitement cette limite.
