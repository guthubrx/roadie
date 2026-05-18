# Ce que Roadie a gagné avec le Target Mode

Ces exemples sont adaptés à ton workspace au moment de l'écriture. Les **labels**
(`A`, `S`, `AF`, `SJ`, etc.) sont des raccourcis générés à partir de l'état
courant : ils peuvent changer si tu ouvres, fermes ou déplaces des fenêtres.
Pour les rafraîchir, lance :

```bash
roadie targets list --max 40
```

**Pour l'utilisateur**

Roadie sait maintenant présenter le bureau comme une **liste de cibles actionnables** plutôt que comme un ensemble de coordonnées à viser à la souris. Concrètement, les **fenêtres**, **stages**, **écrans**, **desktops** et **bookmarks** peuvent recevoir des labels courts, puis être retrouvés ou activés par commande. L'idée est proche de Vimac/Homerow : au lieu de chercher visuellement puis cliquer précisément, on peut dire **"va vers cette cible"**, **"cherche gray"**, **"active ce label"** ou **"envoie la fenêtre active vers cette stage"**.

```bash
roadie targets list
roadie targets list --json --max 10
roadie targets activate S --action focus
roadie targets activate AF --action switch
roadie targets activate AS --action switch
roadie targets activate AD --action switch
```

Dans ton état actuel, `S` correspond à l'écran **LG HDR 4K**, `AF` à la stage
**Work** sur cet écran, `AS` à **Stage 7** avec **BlueJay/Grayjay**, et `AD` à
**Stage 6** avec **Firefox / Horizon Studio**.

On a aussi ajouté un **picker par recherche**. Si une recherche pointe vers une seule cible, Roadie peut agir directement. Si elle est ambiguë, Roadie affiche les candidates et **ne touche à rien**. C'est important pour éviter les erreurs : une commande imprécise ne déplace pas les fenêtres au hasard.

```bash
roadie targets pick gray --action focus
roadie targets pick work --action switch
roadie targets pick horizon --action focus
```

Ici, `gray` doit retrouver les fenêtres **BlueJay / Grayjay**, `work` doit
retrouver ta stage **Work**, et `horizon` doit retrouver la fenêtre Firefox
**Horizon Studio**.

Roadie peut maintenant exposer les **zones sensibles d'une application** via Accessibility : boutons, liens, champs, lignes, menus, etc. C'est **expérimental**, **configurable**, et activable/désactivable. Les clics applicatifs réels sont aussi séparés par option, parce que certaines personnes voudront seulement lister ou inspecter les cibles sans que Roadie clique dans les apps.

```bash
roadie targets list --source app --max 20
roadie targets list --source app --json --max 20
roadie targets inspect D
roadie targets activate D --action click
```

Au moment du relevé, l'app frontmost exposait des cibles applicatives iTerm2 :
`D` et `F` étaient des **AXButton**. Comme les clics applicatifs sont activés
dans ton TOML, `roadie targets activate D --action click` peut vraiment cliquer
dans l'app active.

On a enfin préparé un **overlay visuel de labels**. Il peut afficher temporairement des labels au-dessus des cibles, et il est derrière un paramètre expérimental. Le but est d'aller vers une navigation clavier plus directe, sans imposer cette interface à tous les utilisateurs.

```bash
roadie targets show --json --labels-only
roadie targets show --visual --duration 3
roadie targets hide
```

L'overlay doit te montrer les labels au-dessus des cibles Roadie courantes :
écrans, stages et fenêtres comme **Work**, **Stage 7**, **Stage 6**, **Firefox**,
**iTerm2** et **BlueJay**.

**Pour le debug**

Roadie a gagné une vraie **capacité d'inspection**. On peut demander à une cible ce qu'elle est, où elle vit, à quelle stage ou écran elle appartient, quelles actions elle supporte, si elle est **pinée**, **flottante**, **exclue du tiling**, **stale**, etc. Au lieu de deviner pourquoi une fenêtre se comporte bizarrement, on peut interroger Roadie.

```bash
roadie targets inspect AF
roadie targets inspect AS
roadie targets inspect SJ
roadie targets inspect SL --json
roadie targets list --filter gray --json
```

Dans ton état actuel, `SJ` est une fenêtre **BlueJay / Grayjay** et `SL` est une
fenêtre **Firefox / Horizon Studio**. Ces commandes permettent de voir leur
scope, leur stage, leur écran et les actions supportées.

Les erreurs sont maintenant **plus structurées** : cible inconnue, cible ambiguë, app targets désactivés, clics applicatifs désactivés, action non supportée, cible disparue. Ça évite les comportements silencieux et ça rend les bugs plus faciles à isoler.

```bash
roadie targets pick button --source app --action click
roadie targets activate unknown-target --action focus --json
roadie events tail 30
```

`button` est volontairement un bon test d'erreur : dans l'app active, il y a
souvent plusieurs boutons. Roadie doit donc répondre **ambiguous target** et ne
rien modifier.

On a aussi mis des **garde-fous de configuration**. Le Target Mode, le picker, l'overlay, les app targets, les clics applicatifs et le futur scroll-mode peuvent être activés ou coupés séparément. C'est utile pour diagnostiquer : si un morceau pose problème, on peut le désactiver sans perdre tout Roadie.

```toml
[experimental.target_mode]
enabled = true
picker_enabled = true
overlay_enabled = true
overlay_labels_only = true
overlay_duration_seconds = 3
app_mouse_actions_enabled = true
scroll_mode_enabled = true

[experimental.app_targets]
enabled = true
scope = "frontmost_window"
max_targets = 150
timeout_ms = 120
hint_characters = "asdfghjkl"
include_roles = ["AXButton", "AXLink", "AXTextField", "AXMenuItem", "AXRow", "AXCheckBox", "AXRadioButton", "AXPopUpButton"]
```

```bash
roadie config validate
roadie daemon restart
```

**Pour un agent**

Le gros gain, c'est que Roadie expose maintenant une **API plus exploitable qu'une capture d'écran**. Un agent peut demander la liste des cibles en JSON, lire leurs labels, IDs, types, frames, actions possibles et diagnostics, puis choisir une action sans deviner au pixel près où cliquer.

```bash
roadie query targets
roadie targets list --json --source all --max 80
roadie targets show --json --labels-only
```

Sur ton bureau actuel, un agent verra notamment des cibles comme **LG HDR 4K**,
**Built-in Display**, **Work**, **Stage 7**, **Stage 6**, **Firefox**, **iTerm2**
et **BlueJay** avec leurs IDs stables et leurs actions possibles.

Un agent peut aussi **inspecter avant d'agir**. Par exemple, il peut vérifier qu'une cible est bien une fenêtre, qu'elle appartient au bon écran, qu'elle supporte `focus` ou `send-active`, puis seulement ensuite exécuter l'action. C'est beaucoup plus robuste qu'un pilotage purement visuel.

```bash
roadie targets inspect SJ --json
roadie targets pick gray --json
roadie targets activate SJ --action focus --json
```

Cette séquence dit à un agent : inspecte la fenêtre **Grayjay**, vérifie les
candidates pour `gray`, puis focalise explicitement la cible `SJ`.

Enfin, les app targets ouvrent la porte à une **interaction plus fine avec les applications** : repérer un bouton ou un champ dans la fenêtre active, le lister, l'inspecter, et éventuellement cliquer dessus si l'option est activée. On n'a pas copié le code de Vimac ou Homerow ; on a repris le concept utile et on l'a adapté à Roadie, avec des **garde-fous macOS** et des **sorties structurées** pour l'automatisation.

```bash
roadie targets list --source app --json --max 50
roadie targets inspect D --json
roadie targets activate D --action click --json
```

Dans ton état courant, `D` est une cible applicative de la fenêtre iTerm2 active.
Si tu veux tester dans Firefox ou BlueJay, mets d'abord cette fenêtre au focus,
puis relance :

```bash
roadie targets list --source app --max 20
```
