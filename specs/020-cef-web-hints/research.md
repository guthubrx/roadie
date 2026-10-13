# Research: Lettres d'accès dans Bluejay

## Mesure de départ (journal réel)

`~/.roadies/events.jsonl`, 2026-10-13 04:00-04:01 UTC, `com.futo.grayjay.desktop` : 6-7 éléments lus, 4 candidats, profondeur 2-3, `sawWebArea=false`.

## Decision: publier l'arbre par `--force-renderer-accessibility` dans Bluejay

**Rationale**:
- CEF n'active pas l'accessibilité sur demande externe : la détection est à la charge de l'application hôte, qui doit intercepter `AXEnhancedUserInterface` et appeler `CefBrowserHost::SetAccessibilityState(STATE_ENABLED)` (https://magpcss.org/ceforum/viewtopic.php?f=10&t=3133, https://cef-builds.spotifycdn.com/docs/124.3/classCefBrowserHost.html, https://github.com/cztomczak/cefpython/issues/449).
- `JustCef/native/src/main_mac.mm` : `SharedApplication` ne gère aucun attribut d'accessibilité. Le binaire CEF 141 de Grayjay ne contient pas la chaîne `AXManualAccessibility`.
- `ReconstructArgs` (`Grayjay.Desktop.CEF/Program.cs:148-173`) transmet les arguments de Grayjay à CEF sans filtrer cette option.
- Mesure 2026-10-13 : Grayjay lancé avec `--force-renderer-accessibility` publie sa zone web (410 éléments, profondeur 11).

**Choix utilisateur** : option toujours active dans Bluejay (branche `pr/*`), Grayjay amont non modifié.

**Alternatives considered**:
- Activation à la demande dans la classe application native de JustCef : plus propre, mais recompilation de `justcefnative` ; refusée par l'utilisateur.
- Demande `AXEnhancedUserInterface` depuis Roadie : sans effet sans code hôte (JustCef) ; non retenue.

## Mesure de l'arbre de Bluejay (relevé jetable, Article VIII)

Relevé jetable, installé puis retiré, Bluejay lancé avec l'option, page d'accueil. Fichier supprimé après analyse (il contenait aussi des données d'une autre application) ; seuls ces chiffres sont conservés.

| Constat | Valeur |
|---|---|
| Éléments lus sous la zone web | 405 |
| Rôles | 197 `AXGroup`, 106 `AXStaticText`, 96 `AXImage`, 4 `AXButton`, 1 `AXTextField`, 1 `AXWebArea` |
| Actions | 397 éléments n'ont que `AXShowMenu`/`AXScrollToVisible` (ignorées) ; 6 ont `AXPress` |
| `AXFocused` modifiable | 38 éléments |
| Focalisables sans descendant focalisable | 14 entrées de barre latérale, 17 cartes vidéo, 2 boutons ronds, champ de recherche, bouton « collapse » |
| Focalisables avec descendants focalisables | zone web, `rootElement`, `containerScroll` (grands conteneurs) |

Cause côté page : SolidJS délègue `onClick` au document ; Chromium ne voit pas de clic sur les `div` et ne leur donne pas `AXPress`. La directive `use:focusable` de Bluejay gère le focus en JavaScript, sans `tabindex`, mais Chromium les expose quand même comme focalisables (mesuré).

## Decision: règle « feuille focalisable » dans les zones web

Dans une zone web (`AXWebArea` et ses descendants), un élément qui n'est pas déjà candidat devient candidat si `AXFocused` est modifiable et si aucun élément focalisable n'est son descendant. La zone web elle-même est exclue.

**Rationale**: signal exposé par Chromium, indépendant des noms de classes CSS (hachés par module), mesuré sur l'arbre réel : il sépare exactement les éléments cliquables des grands conteneurs.

**Heuristique sur l'arbre parcouru**: un alias des attributs boost ou une collision `CFHash` peut placer un élément sous un autre parent que son parent réel (comportement antérieur du parcours, accepté).

**Sous-arbres inconnus** (contre-revue) : un élément à `max_depth` ou dont `AXChildren` est illisible est un marqueur « inconnu » ; un conteneur qui en contient un n'est pas une feuille. Un parcours coupé écarte les éléments dont un descendant reste dans la pile.

**Priorité** : les cibles historiques passent d'abord et seules comptent pour `max_targets` ; les feuilles s'ajoutent ensuite. Même parcours et même arrêt `limit` = mêmes cibles historiques (T3 Code).

**Calcul**: le parcours est en préordre (`stack` + enfants empilés en ordre inverse). Un élément X a un descendant focalisable si et seulement si l'élément focalisable suivant dans le préordre est un descendant de X (chemin préfixé par `X.`). Vérification en O(n) sur la liste des focalisables.

**Alternatives considered**:
- Noms de classes (`sideBarButton`, `container`) : fragile et propre à une application.
- Tous les `AXGroup` qui contiennent texte ou image : trop de lettres (≈ 200 groupes).
- `AXDOMClassList` + heuristique « cursor » : Chromium n'expose pas le curseur.

**Coût**: un appel AX en plus (`AXUIElementIsAttributeSettable`) par élément de zone web non candidat. Hors zone web : aucun appel en plus (FR-004).

## Decision: répartition des rôles écartés dans `targets.app_scan`

Champ `rejectedRoles` : les 5 rôles les plus fréquents parmi les éléments lus et non retenus, format `AXGroup=197,AXStaticText=106`. Sert à repérer la prochaine application mal couverte sans relevé jetable.

## Mesures d'implémentation (2026-10-13)

**Anti-doublon révisé** : le blocage de toute feuille sous une cible retenue (correction du round 1 de contre-revue) écartait toute la page de Bluejay : relevé jetable sans texte, la cible `0.0.0` est un `AXGroup` 1836×2082 avec `AXPress` qui englobe la page ; 12 feuilles bloquées sur 62 éléments. Règle retenue : une cible qui enveloppe une seule feuille garde sa lettre (même élément cliquable) ; une cible qui en enveloppe plusieurs est un conteneur et ses feuilles restent. Résultat : 11 puis 72 feuilles.

**Attributs boost hors zones web seulement** : avec boost, Bluejay ne lisait que 62-73 éléments en 250 ms (~3,6 ms par élément). Sans boost dans les zones web : 1 516-1 544 éléments en 250 ms (~0,17 ms). T3 Code : 124-136 ms → 43-58 ms, même arrêt `limit`, mêmes 368 éléments lus. Les attributs boost restent pour les arbres non web (Firefox, raison de la spec 009).

**Élagage hors fenêtre rejeté** : essai « ne pas parcourir un sous-arbre web hors fenêtre » : `pruned=0` sur Bluejay, aucun gain ; retiré (Article XXII).

**Budget** : Bluejay expose 3 317 éléments, lus en 440-468 ms. Choix utilisateur : `timeout_ms = 500` dans `~/.config/roadies/roadies.toml` (Finder : 58 cibles en 502 ms au lieu de 252 ms ; T3 Code inchangé).

## Corrections après retour utilisateur (page Abonnements, 2026-10-13)

Relevés jetables sans texte (rôle, chemin, taille, classes), retirés après usage.

| Constat | Mesure | Décision |
|---|---|---|
| Zone de contenu absente du parcours | `0.0.0.1`-`0.0.0.4` écartés par `seen` : même `CFHash` qu'un élément de la barre latérale, `CFEqual=false` (12 cas) | `CFIdentitySet` : hash puis `CFEqual`, dans le parcours et dans `copyChildren` |
| Budget épuisé dans la barre latérale | ~1 000 abonnements défilés, chacun réduit par Chromium à 1 point (`191x1`) | pas de descente sous 4 points (seuil de l'affichage) |
| Cartes vidéo non retenues | barre de progression `283x4` dans chaque carte, marquée « inconnue » | marqueur seulement si ≤ 1 point ou hors fenêtre |
| Anti-doublon par comptage | contre-revue round 4 : perte de feuilles avec cibles imbriquées ou parcours coupé | comparaison de surfaces locale (≥ 80 %) |

Résultat : 80 cibles dont 73 feuilles (30 cartes), parcours complet 463 ms ; T3 Code 150 (`limit`), Finder 58.

**Budget final** : mesures à ~3 080 éléments entre 463 et 501 ms (arrêt `timeout` une fois à 501 ms). Choix utilisateur : `timeout_ms = 700` pour la marge.

**Anti-doublon final** : recouvrement ≥ 80 % de la surface de la feuille **et** de celle de la cible (contre-revue round 5).
