# Diagnostic — session 029

## Cause racine

Roadie reçoit déjà la fermeture par `AXUIElementDestroyed`. Le tiler programme
une passe après 15 ms. Le fichier des stages déclenche ensuite le navrail avec
un regroupement de 20 ms.

Le retard apparaît plus loin. Le writer retire immédiatement la feuille de
l'arbre BSP, mais il conserve le membre persistant de la stage. Le navrail
traite alors cette fermeture confirmée comme une absence transitoire. Il garde
la carte pendant 15 secondes. Son minuteur d'une seconde ajoute jusqu'à une
seconde avant la disparition finale.

## Données observées

Les événements réels de `/Users/moi/.roadies/events.jsonl` montrent :

- 164 rafraîchissements du fichier des stages ; médiane 91,5 ms, p90 127,4 ms ;
- 473 passes demandées par une destruction ; médiane 59,4 ms, p90 90,1 ms ;
- rendu médian du rail 4,5 ms ; snapshot médian 0,2 ms.

Le chemin événementiel est très inférieur aux 15 secondes actuelles. Il n'est
cependant pas instantané. Une contre-mesure sur 473 passes donne environ 249 ms
au p95 avant le watcher et le rendu. La cible bout en bout est donc 400 ms.

## Décision

Une destruction confirmée marque le membre persistant comme fermé dès que le
fournisseur ne le présente plus. Le navrail exclut ce membre immédiatement,
mais le `StageStore` le garde pour le rattachement SPEC-016 après relance.
Si CoreGraphics présente encore l'identifiant, Roadie
programme des reprises à 50 ms. Elles sont bornées à dix. La preuve utilisable
pour l'appartenance expire après cinq secondes. Une preuve ancienne ne peut
donc pas supprimer plus tard une fenêtre seulement masquée.

La grâce de 15 secondes reste inchangée pour une absence non confirmée. Elle
protège les changements de stage, de Space et le plein écran natif.

Une terminaison d'application peut produire les mêmes événements AX. Le
marquage visuel reste compatible avec ce cas, car le membre persistant n'est
pas supprimé. Une fenêtre restaurée peut donc retrouver sa stage.

## Solutions écartées

- Mettre la grâce globale à zéro : cela créerait des disparitions transitoires.
- Ajouter un polling rapide : le watcher existant fournit déjà le bon signal.
- Invalider seulement le snapshot : le filtre du navrail garderait la carte.
- Ajouter un second registre : l'observateur et le `StageStore` suffisent.
- Supprimer immédiatement le membre persistant : cela casserait le contrat de
  restauration SPEC-016 après la relance d'une application.

## Références externes

- WCAG 2.2 demande un état visible cohérent et déterminable.
- INP utilise 200 ms comme repère web. La session retient 400 ms au p95 pour le
  pipeline natif, le watcher et le rendu monolithique.
- Testing Library et Playwright recommandent de vérifier le résultat visible.
