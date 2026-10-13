# Research: Mode recherche du mode lettres

Référence fonctionnelle : guide Homerow (https://github.com/nchudleigh/homerow#user-guide) : `Cmd-Shift-Space`, recherche, label vert sur l'élément mis en avant, Tab/Flèche bas/Ctrl-N et Maj-Tab/Flèche haut/Ctrl-P, Maj + label pour sauter, Retour clic, Retour ×2 double-clic, Maj-Retour clic droit, Cmd-Retour Cmd-clic, `*`/`;` tout afficher, `?` Tutor, Échap. Hyper key conseillée : Caps Lock + F.

## Decision: raccourci global enregistré par Roadie (Carbon `RegisterEventHotKey`)

**Rationale**: l'utilisateur veut Hyper + F par défaut **et** paramétrable. Une clé de configuration Roadie rend le réglage portable et rechargeable. `RegisterEventHotKey` ne demande aucune permission (pas d'interception clavier permanente) et fonctionne dans l'app du daemon (`NSApplication.run`). Il consomme la combinaison, qui n'atteint pas l'app au premier plan.

**Alternatives considered**:
- Raccourci BetterTouchTool qui appelle la CLI : non paramétrable dans Roadie ; reste possible via `roadie targets search` (ajouté pour cela).
- Interception permanente par `CGEventTap` : coût et risque permanents pour une seule combinaison.

## Decision: touche donnée par son caractère, traduite selon la disposition clavier

**Rationale**: l'utilisateur est en AZERTY. `RegisterEventHotKey` attend un code physique. La configuration accepte un caractère (`f`) ou un nom (`space`, `return`, `f1`…). Le caractère est traduit en code physique par la disposition active (`TISCopyCurrentKeyboardLayoutInputSource` + `UCKeyTranslate` sur les codes 0-127), comme le relevé AZERTY déjà utilisé pour les signets BTT. « F » donne le code 3 en AZERTY comme en QWERTY.

## Decision: rechargement du raccourci par relecture périodique de la configuration

**Rationale**: `ConfigReloadService.currentConfig()` ne relit le fichier que si sa date ou sa taille changent (coût d'un `stat`). Un minuteur de 2 s compare la valeur `search_hotkey` et réenregistre si elle change. Pas de mécanisme d'abonnement existant (`rg "reloadHandlers|didReload"` : aucun).

## Decision: logique de recherche dans un modèle pur, testable

**Rationale**: correspondance, ordre, mise en avant, navigation en boucle, saut par label, choix du clic selon les touches : tout cela se teste sans écran. La session interactive ne fait que l'afficher et lui transmettre les touches.

Correspondance : texte normalisé (`TargetHintService.normalized` : casse, accents) puis espaces supprimés, des deux côtés ; « contient ». Ordre : correspondances dont le titre commence par la requête d'abord, puis ordre d'origine (stable).

## Decision: texte des enfants rattaché aux feuilles focalisables web

**Rationale**: dans Bluejay, la cible (carte, entrée de menu) est un `AXGroup` sans titre ; le texte est dans ses `AXStaticText` enfants. Le parcours lit déjà le titre et la valeur de chaque élément : rattacher le texte au plus proche ancêtre « feuille en attente » ne coûte aucun appel AX. Le texte n'est utilisé que si la cible n'a pas de titre propre, borné à 120 caractères.

**Alternatives considered**: relire les descendants de chaque cible après le parcours (appels AX en plus, budget dépassé dans Bluejay) ; rattacher aussi aux cibles historiques (le conteneur géant de Bluejay recevrait tout le texte de la page : faux positifs).

## Decision: Cmd-clic par une nouvelle action `command-click`

**Rationale**: `AppTargetQueryService.click` gère clic, double-clic et clic droit par `CGEvent`. Le Cmd-clic est le même clic avec le drapeau Commande. Pour une cible Roadie (fenêtre, stage), les variantes retombent sur l'action par défaut de la cible.

## Decision: affichage

**Rationale**: le mode lettres dessine déjà ses étiquettes dans des fenêtres transparentes par écran (`TargetOverlayWindow`, `TargetOverlayView`). Le mode recherche réutilise ces fenêtres ; la vue reçoit en plus : la cible mise en avant (couleur verte), et une barre de saisie en bas de l'écran principal (requête, nombre de correspondances, ou propriétés pour `?`). Sans état de recherche, la vue dessine exactement comme avant (FR-007).

## Hors périmètre

- Mode défilement Homerow (H/J/K/L) : boîte à idées.
- Interface graphique de réglage du raccourci.

## Décisions après contre-revue du plan (Codex, APPROVE_WITH_CHANGES)

- **Raccourci** : `RegisterEventHotKey` avec `kEventHotKeyExclusive`, sur le fil principal ; démarré et arrêté avec le composant mode lettres (`startTargetModeComponent`), seulement si `enabled` et `overlay_enabled` ; pression ignorée si une recherche est déjà ouverte.
- **Caractère → touche** : la touche qui produit le caractère **sans modificateur** ; `UCKeyTranslate` avec `kUCKeyTranslateNoDeadKeysMask`, état de touche morte remis à zéro par code, `LMGetKbdType()` ; caractère non résolu = échec journalisé. La relecture de 2 s compare le **code résolu** (pas seulement la chaîne) : un changement de disposition réenregistre.
- **Configuration invalide** : la dernière configuration valide reste appliquée (comportement de `ConfigReloadService`) ; `""` désactive.
- **Validation** : le premier Retour fige la **cible** (pas son label) ; l'activation passe par `TargetHintService.perform(target, requestedAction:)` sur cette cible, sans nouvelle liste. Retour en répétition automatique (`keyboardEventAutorepeat`) ignoré. Pendant l'attente de 0,35 s, les autres touches sont ignorées ; Échap annule. Maj-Retour et Cmd-Retour immédiats.
- **Texte des enfants** : champ de recherche distinct (`searchText`), ajouté au `matchText` ; `title` inchangé (sorties du mode lettres classique identiques). Rattaché au plus proche candidat web (historique ou feuille) qui ne contient aucun autre candidat ; 500 caractères max ; texte identique au titre ou à la valeur non répété.
- **Clavier** : décodage propre à la session de recherche (caractères bruts lettres/chiffres/espace/`*`/`;`/`?`, Tab, Maj-Tab, Ctrl-N, Ctrl-P, Retour + Maj/Cmd + répétition, Échap, Effacement, flèches) ; touches mortes et composition ignorées (les accents ne comptent pas dans la recherche) ; limite annoncée pour les méthodes de saisie à composition. Majuscule = saut par label (la recherche ignore la casse).
- **Affichage** : barre sur l'écran qui contient le pointeur, visible même sans correspondance.
- **Options de session** : toutes sources, cibles d'app incluses, 500 résultats max, fermeture après 60 s sans frappe.
- **Classement** : conservé (deux partitions stables, O(n)) : rend « subscr » utile immédiatement, comme Homerow.
