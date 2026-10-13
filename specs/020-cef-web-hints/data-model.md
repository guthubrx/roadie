# Data Model: Lettres d'accès dans Bluejay

## Ajouts à `AppTargetScanStats` (spec 018)

| Champ | Type | Règle |
|---|---|---|
| `focusableAdded` | Int | candidats ajoutés par la règle « feuille focalisable » (dernière passe) |
| `rejectedRoles` | String | 5 rôles les plus fréquents parmi les éléments lus et non retenus, `ROLE=n` séparés par des virgules, tri décroissant puis alphabétique |

## Règle « feuille focalisable »

Un élément E devient candidat si :
1. E est dans une zone web (E ou un ancêtre a le rôle `AXWebArea`), et E n'est pas lui-même `AXWebArea` ;
2. E n'est pas déjà candidat (action utile ou rôle de `include_roles`) ;
3. `AXFocused` est modifiable sur E ;
4. aucun élément focalisable n'est descendant de E ;
5. son cadre recoupe la fenêtre (règle 018) ;
6. si une cible de zone web retenue l'enveloppe, E en couvre moins de 80 % (sinon c'est le même élément cliquable et seule la cible garde sa lettre, `duplicatesTarget`) ;
7. sa partie visible dépasse 4 points dans les deux sens (`isHintable`).

Parcours en zone web : pas de descente dans un élément visible sur 4 points ou moins ; il compte comme sous-arbre inconnu seulement s'il est réduit à 1 point ou hors fenêtre (`hidesContent`). Dédoublonnage des éléments : `CFIdentitySet` (hash puis `CFEqual`).

Lecture des enfants en zone web : `AXChildren` seul, sans attributs boost (mesure research.md).

« Focalisable » pour le point 4 : élément de zone web déjà candidat, ou `AXFocused` modifiable.

Fonction pure : `keepsFocusableLeaf(path:nextFocusablePath:)` = `next == nil || !next.hasPrefix(path + ".")`, la liste étant en préordre.
