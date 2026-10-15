# Implémentation 037

## Corrections

- Le fournisseur rejouable transmet l'inventaire CG/PID et le rejoue une seule fois,
  y compris son état indisponible. La conservation ne dépend plus du lecteur du rail.
- L'attente AX couvre le même écran. Une première résolution réussie est mémorisée
  par identité/PID, dans la limite des membres conservés. Une résolution perdue avant
  écriture invalide cette preuve. Les refus ultérieurs et retours de Space gardent
  leurs délais et protections.
- Le patch 035 est importé avec ses sept familles de tests. Les 13 sites de validation,
  publication, décodage et lecture de journaux sont présents dans la nouvelle version.
- Les observations sont collectées par identifiant puis appliquées en une passe aux
  membres, pins et signets. Les groupes, le focus, l'ordre et les dates inchangées sont
  conservés. La géométrie des fenêtres cachées reste exclue. Les métadonnées des stages
  et les pins sont indexés pendant la passe, sans état durable supplémentaire.
- Le panneau natif est reproduit : un AXSheet attaché contient une autre fenêtre CG
  appartenant au contenu XPC AppKit. L'index recense ces identités sous leur feuille ;
  le filtre écarte AXSheet. Une fenêtre principale titrée File Upload reste gérée.
  La lecture est bornée à 256 éléments et quatre niveaux ; aucun titre n'est filtré.
- Les mutations du fichier de glisser utilisent FileLock. La lecture d'une expiration
  ne supprime plus le fichier partagé. Le dépôt expiré est ignoré avec la même horloge
  que le mainteneur. Un reset désactivé ne touche pas au fichier utilisateur.

## Tests

Avant : les nouvelles régressions de disponibilité et présence échouent sur 18 assertions.
Après : 1587 tests, 183 suites, tous réussis. Le premier élargissement de l'attente a
révélé des restaurations déjà connues ; la mémorisation d'une résolution initiale a
préservé ces parcours. Les doubles qui simulent des écritures refusées exposent désormais
leur lecture de cadre. Les compteurs du parcours de redimensionnement démarrent après
l'initialisation ; leurs limites et assertions de geste ne sont pas augmentées.

Le test de lot compare ses résultats à l'ancien parcours. Mesures Debug, trois essais
après échauffement, mêmes fenêtres :

| Fenêtres | Ancienne boucle, médiane ms | Lot, médiane ms |
| --- | ---: | ---: |
| 20 | 0,061 | 0,024 |
| 200 | 2,900 | 0,186 |
| 800 | 43,603 | 0,797 |
| 1600 | 177,008 | 1,622 |

Le temps inclut la préparation des dictionnaires du lot. Ce benchmark isolé ne mesure
pas la durée complète d'un placement sur le Mac. Les résultats et l'ordre sont identiques.

## Revue locale

Onze fichiers produit diffèrent du binaire installé. Les autres écarts à la branche 036
sont les sources de la version combinée déjà installée, copiées depuis son reçu à 265
empreintes. Le worktree parallèle n'est pas modifié. Aucune dépendance, aucun moteur,
aucune purge d'état et aucun nouveau format persistant.

Contre-lecture locale, non indépendante. Le fournisseur de production, le repli nil,
le rejeu, le même écran, les résolutions perdues, les groupes hors Space, les fenêtres
principales, les feuilles XPC, la profondeur et les mutations du glisser sont examinés.
Les preuves brutes restent hors Git. Installation et preuves natives : reçu de validation.
