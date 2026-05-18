# Research: Roadie Target Mode

## Sources consultées

- Vimac README et manuel : modèle de hint-mode, labels et scroll-mode.
- Homerow README : recherche de cible, labels-only mode, tutor, ergonomie Hyper key.
- Neru README : séparation entre hint/label mode et grille récursive.
- Apple Accessibility / AXUIElement : source primaire pour la capacité à lire des éléments UI macOS via Accessibility.
- Baselines utilisateur : `01-ai-agents-agentic-ai.md`, `03-cognitive-load-productivity.md`, `10-data-privacy.md`.

## Decision: Séparer cibles Roadie et cibles applicatives

**Rationale**: Roadie contrôle de manière fiable les fenêtres, stages, desktops et displays. Les éléments internes des apps dépendent de la qualité de l'arbre AX, qui varie fortement selon Firefox, Electron, apps Apple et popups système. Une séparation évite qu'un échec de crawl AX entraîne relayout, changement de stage ou bordure obsolète.

**Alternatives considered**:
- Tout mélanger dans un seul inventaire : rejeté, trop risqué pour le moteur de layout.
- Ne jamais exposer les app targets : rejeté, car l'objectif utilisateur inclut explicitement les zones sensibles façon Vimac.

## Decision: Commencer par CLI/JSON avant overlay complet

**Rationale**: La valeur agent-friendly vient d'abord d'une API déterministe : list, inspect, activate. L'overlay visuel peut ensuite utiliser exactement le même modèle. Cela réduit les risques UI et rend les tests unitaires possibles.

**Alternatives considered**:
- Construire l'overlay d'abord : rejeté, plus fragile et plus long à tester.
- S'appuyer seulement sur screenshots : rejeté, moins fiable pour les agents.

## Decision: Labels déterministes indépendants des IDs

**Rationale**: Les IDs de stages/fenêtres sont stables pour la machine mais peu lisibles. Les labels courts doivent suivre l'ordre visible et le filtrage, comme Vimium/Vimac/Homerow, tout en restant calculés localement sans copier l'algorithme GPL.

**Alternatives considered**:
- Utiliser les IDs comme labels : rejeté, source de confusion déjà observée.
- Utiliser uniquement la recherche texte : rejeté, moins rapide pour usage clavier.

## Decision: App targets désactivés par défaut et bornés

**Rationale**: Interroger l'arbre AX peut être lent ou incomplet. Les app targets doivent avoir `enabled=false` par défaut, un `max_targets`, un `timeout_ms` et un scope `frontmost_window`.

**Alternatives considered**:
- Crawl complet de l'app active : rejeté pour performance et stabilité.
- Crawl de tout le desktop : rejeté, risque trop élevé et valeur marginale.

## Decision: Inspecteur comme primitive de debug

**Rationale**: L'utilisateur veut comprendre pourquoi Roadie agit ainsi, et les derniers bugs ont montré que l'opacité coûte cher. L'inspecteur expose les raisons : scope, tileability, pins, règles, subrole, mobilier, dernier événement pertinent.

**Alternatives considered**:
- Logs seuls : rejeté, trop indirect.
- UI seulement : rejeté, inutilisable par agent.

## Decision: Ajouter une grille récursive en fallback universel

**Rationale**: Les arbres AX ne couvrent pas tout, notamment les canvases, webviews et zones non accessibles. Une grille récursive donne un langage spatial robuste : l'utilisateur ou l'agent peut cibler "cellule AAG" sans dépendre d'une capture écran fragile.

**Alternatives considered**:
- Forcer l'AX partout : rejeté, impossible sur certaines apps.
- Garder uniquement les coordonnées absolues : rejeté, pas assez lisible ni rejouable.

## Decision: Enregistrer les macros avec contexte cible + fallback coordonnées

**Rationale**: Pour apprendre une manipulation à un agent, il faut garder à la fois ce que l'utilisateur a fait et ce que Roadie comprend de l'objet cliqué. Le replay tente donc une cible Roadie/AX stable, puis retombe sur les coordonnées.

**Alternatives considered**:
- Enregistrer uniquement les coordonnées : rejeté, fragile au moindre changement de layout.
- Enregistrer uniquement l'AX : rejeté, trop dépendant de la qualité de l'app.

## Decision: AX boost configurable

**Rationale**: Firefox/Electron exposent parfois leurs éléments via `AXVisibleChildren`, `AXRows`, `AXContents` ou ordre de navigation plutôt que par `AXChildren`. Le boost est utile mais doit rester borné par profondeur et timeout.

**Alternatives considered**:
- Toujours crawler tous les attributs : rejeté, trop coûteux.
- Faire des exceptions app hardcodées : rejeté, moins générique.

## Red flags et mitigations

- **AX app lent ou faux positif** : timeout, limite, résultat partiel, aucun relayout.
- **Licence Vimac GPL** : ne reprendre aucun code, seulement les concepts UX.
- **Surcharge cognitive** : commandes simples `targets list`, `targets inspect`, `targets activate`; overlay ensuite.
- **Automatisation agent dangereuse** : actions explicites, inspect avant activation possible, JSON transparent.
- **Record sensible** : `record_text_input=false` par défaut, durée et nombre d'événements bornés.
- **Grille trop intrusive** : option expérimentale, aucune mutation de layout.
