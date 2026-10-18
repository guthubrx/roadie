# Refus — implémentation et contrat pour le parent

Branche vérifiée au départ : `session-043-redimensionnement-fiable`.
Base vérifiée au départ : `e86e71b74cdb870f7b7ae6b151e178bcd3303f1d`.
Implémentation terminée. Validation Swift réservée au parent : aucun build ni test Swift lancé.
Aucun commit, push, installation, benchmark ni sous-agent supplémentaire.

## Propriété et résultat

Fichiers écrits par ce livrable uniquement :

- /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/025-settings-readability/Sources/RoadieDaemon/LayoutMaintainer.swift
- /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/025-settings-readability/Tests/RoadieDaemonTests/Spec043RefusalTests.swift
- /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/025-settings-readability/specs/043-redimensionnement-fiable/notes-refus.md

Les fichiers du registre AX, de l'observateur, du BSP, des poignées et du parent restent intacts.
Les modifications concurrentes ont été conservées. Le parent a avancé HEAD pendant ce travail ; aucun retour à la base n'a été effectué.

## Causes établies dans le code de base

1. `treeLayoutCommands` applique le geste, puis confirme et corrige les refus. Ces deux derniers chemins ne vérifiaient pas la génération de l'écriture. Un refus confirmé de G1 pouvait donc déplacer la frontière que le geste venait de choisir en G2. La garde `correctedGenerations[id] != generation` limitait chaque correction dans G2, mais ne prouvait pas que le refus appartenait à G2.
2. `treeWrite` reconnaissait une relecture refusée de l'ancienne génération comme écho, même pour une nouvelle intention demandant la même cible. L'ancien refus pouvait ainsi empêcher la nouvelle demande d'atteindre le point d'écriture.
3. Les minimums de l'arbre n'étaient liés qu'à l'identifiant CG. Un nouvel identifiant de processus, un autre stage ou un autre mode conservaient cette contrainte. Un redimensionnement réellement obtenu sous l'ancien minimum restait aussi limité par ce minimum.
4. Une lecture AX de confirmation pouvait remplacer son entrée pendant l'appel. Son résultat était ensuite appliqué à l'entrée courante sans vérifier qu'il s'agissait encore de la demande lue au départ. Le plan de l'ancienne génération pouvait également être appliqué après une commande plus récente arrivée pendant cette lecture.
5. Les échéances de correction reprenaient les refus d'anciennes générations. La borne `echoWindow` était respectée par les échéances, mais pas par la relecture exécutée lors d'une passe de sécurité ultérieure.

Ces causes sont démontrables par l'ordre des appels et les gardes absentes. Les nouveaux tests rendent ces ordres exécutables. Ils n'ont pas encore été exécutés : ne pas présenter un échec avant correctif ou un succès après correctif comme une mesure obtenue.

## Reproduction déterministe principale

Deux fenêtres sur un écran 1000 × 800 ; arbre vertical 50/50.

1. À t0, la génération G1 demande 500 points à la fenêtre 1. L'application rend 700 points. Le registre conserve demande, relecture et G1.
2. À t0 + `refusalConfirmDelay`, une seconde observation réelle de 700 confirme le refus. La correction n'est pas encore passée.
3. L'application accepte maintenant une taille plus petite. L'utilisateur obtient réellement 400 points et relâche la souris. La session de geste donne son cadre de départ et son cadre observé.
4. `layoutGesture` ouvre G2. `applyGesture` déplace la frontière à 0,4.
5. Avant correction : le refus G1 était traité sous G2 et ramenait la frontière à 0,7. Après correction : les chemins de refus ignorent G1 ; la fenêtre 1 reste à 400 points et la voisine commence à x = 400.

Le test `confirmedOldRefusalCannotOverwriteFreshResize` capture cet ordre. `pendingOldRefusalCannotConstrainGestureOnNeighbor` couvre le geste sur la voisine avant toute seconde observation de l'ancien refus.

## Décisions et garanties

- Confirmation, correction et échéance de refus exigent la génération courante. Une correction interne n'ouvre aucune génération. Le marqueur de correction reste limité à une fois par fenêtre et par génération.
- La relecture fraîche reste obligatoire. Elle ne commence qu'après `refusalConfirmDelay`, avant la fin de `echoWindow`. Un snapshot republié, une lecture absente ou un ancien cadre historique ne deviennent pas des preuves.
- Après la lecture, l'entrée doit être identique à celle capturée avant l'appel. La génération attendue est aussi transmise au registre sous son verrou. Si une commande a ouvert une nouvelle génération pendant la lecture, le plan d'arbre de la passe devenue ancienne est abandonné.
- Le filtre d'écho de `treeWrite` s'applique à la génération concernée. Une nouvelle intention peut donc réessayer la même cible avec son propre budget. Aucun compteur existant n'est remis à zéro pour une correction interne.
- Les minimums portent maintenant le PID, le bundle, le scope complet et le mode. Ils sont filtrés avant le traitement du geste. Les minimums valides des voisines restent contraignants.
- Quand une vraie session de redimensionnement obtient une dimension inférieure à son ancien minimum, cette observation réduit uniquement le minimum de la fenêtre manipulée, axe par axe. Le plancher `minimumTileSide` reste conservé. Un simple clic ou déplacement sans changement de taille ne modifie pas cette mémoire.
- La signature de génération inclut aussi le PID, le bundle et le mode. Une réutilisation d'identifiant CG ne transporte donc pas les refus de l'ancienne fenêtre dans la même génération.
- Le BSP conserve ses algorithmes de frontière et de correction des minimums. Aucun changement de délai, aucune règle de trois refus, aucune dépendance et aucun code externe incorporé.

Coût ajouté : O(n + r) par passe d'arbre pour l'index existant des fenêtres et le filtrage des r minimums, avec accès au stage en dictionnaire. Les conversions des minimums restent O(r), une fois avant la réduction des quatre bords au plus. Les corrections BSP conservent leur coût existant. Mémoire supplémentaire O(r), uniquement les identités nécessaires à la validité de la contrainte.

## Interface et raccordement du parent

L'API publique de `LayoutMaintainer` est inchangée.

Le seul raccordement consommé de l'autre livrable est déjà présent dans :
/Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/025-settings-readability/Sources/RoadieAX/WrittenFrameRegistry.swift

```swift
confirmRefusal(windowID:observed:at:generation:)
```

Le dernier argument est la génération capturée avant la lecture AX. L'agent historique a ajouté ce paramètre facultatif ; les autres appelants restent compatibles. La comparaison de l'entrée entière protège aussi le remplacement d'une demande dans la même génération avant le retour de lecture.

Pour les nouvelles poignées, le parent doit conserver ce contrat existant des commandes d'arbre :

1. Vérifier le scope et la topologie de la commande.
2. Ouvrir une génération pour la nouvelle intention qui change réellement le ratio. Une reprise interne ou une confirmation de refus conserve sa génération.
3. Appliquer par le service existant avec cette génération, puis publier le résultat via `noteTreeScopeApplied`, comme pour les commandes d'arbre actuelles.
4. Ne pas oublier le registre ni réinitialiser ses compteurs pour faire passer une correction ou une reprise. Ne pas confirmer une entrée à partir du seul historique.

Le geste natif continue de passer par `layoutGesture`, qui ouvre déjà sa génération avant `applyGesture`. Les événements AX `Moved` et `Resized` restent des causes internes. Le parent garde la propriété du service et du raccordement des poignées ; aucun de ses fichiers n'a été modifié.

## Tests remis au parent

Fichier : /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/025-settings-readability/Tests/RoadieDaemonTests/Spec043RefusalTests.swift

14 fonctions, soit 17 cas avec les trois fonctions paramétrées. Provider réutilisé : `PowerUserProvider`. L'écrivain enveloppe `PowerUserWriter` pour simuler les seuls minimums AX et tenir le registre. Horloge, souris et lectures sont injectées. Aucun délai réel ni dépendance au bureau.

Cas couverts :

- Refus confirmé ancien après un geste récent sur la même fenêtre.
- Refus non confirmé ancien après un geste sur la voisine.
- Nouvelle intention qui demande la même cible précédemment refusée.
- Seconde observation absente et confirmation hors fenêtre temporelle.
- Écriture remplacée pendant la lecture, dans la même génération ou dans la suivante.
- Annulation des écritures du plan devenu ancien pendant une lecture.
- Taille utilisateur réellement obtenue sous son minimum appris.
- Changement de PID seul ou de bundle seul.
- Transfert de stage ; minimum précédent devenu invalide.
- Minimum toujours valable chez une voisine.
- Ancien refus confirmé qui ne doit plus réarmer une échéance échue.
- Plein écran natif avant correction du refus.
- Refus successifs et repos stable, avec deux puis quatre fenêtres ; génération et budgets conservés.
- Appui souris qui suspend la confirmation jusqu'au relâchement.

Répertoire de travail : /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/025-settings-readability

Dans le créneau Swift sérialisé du parent :

```sh
swift test --filter 'Spec043RefusalTests'
swift test --filter 'TreeLayoutMaintainerTests|LayoutMaintainerTests|PlacementTransitionRegressionTests|NavrailMaximizationRefusalTests|Spec036WindowPresenceTests|Spec037PlacementReadinessTests'
swift test --filter 'Spec043WrittenFrameHistoryTests|Spec043AXEchoTests|WrittenFrameRegistryTests|AXWindowEventObserverDispatchTests'
```

Puis la suite complète selon le plan du parent. Les tests existants restent inchangés dans ce livrable. Les tests de dépôt et de glisser de `TreeLayoutMaintainerTests` doivent aussi passer : ils protègent la consommation des sessions et les arbres imbriqués.

## Vérifications et limites

Diff de production relu. Contrôle des espaces effectué sur le fichier modifié et le nouveau test, sans diagnostic d'espace invalide. Aucune commande Swift exécutée. Aucune affirmation de compilation ou de succès des tests à ce stade.

Preuves visuelles incomplètes : aucune installation ni manipulation du bureau n'est autorisée pour ce sous-agent. Le parent doit rejouer le parcours réel après intégration et produire le diaporama prévu par les consignes du projet.
