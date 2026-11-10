# Décisions - 155 Consolidation du projet

## Contrat actif — décision utilisateur du 10 novembre 2026

Cette reprise remplace les limites de la préparation conservée ci-dessous. Le travail va
jusqu'au développement complet, à la correction des constats, puis à la release 0.14.0,
à son installation et au nettoyage. Les recettes historiques restent une base de travail ;
le responsable peut corriger leurs défauts après diagnostic. Les contrôles par story restent
séquentiels. Les commits de code attendent convergence et audit (skill my-specify-all).
Aucune dépense, aucun compte développeur Apple, aucune CI automatique ni lancement CI.
Les preuves retirées de la publication sont sauvegardées localement, avec empreintes.


Ce fichier sépare ce qui appartient à l'utilisateur de ce que l'implémenteur exécute.

- **Bloquante** : aucune tâche n'existe tant que l'utilisateur n'a pas choisi.
- **Par défaut** : une valeur est appliquée par les tâches ; l'utilisateur peut la changer.
- **Exclue** : hors du périmètre, avec la raison.

**Règle pour l'implémenteur** : ne traite aucune décision bloquante ou exclue. N'ajoute
aucune tâche. Si une tâche semble dépendre d'une décision de ce fichier, arrête-toi et
signale-le.

## Décisions bloquantes (à prendre par l'utilisateur)

### D1 - Licence du dépôt

- **Constat** : le dépôt public n'a pas de fichier `LICENSE`. Sans licence, le droit
  d'auteur s'applique en entier : personne ne peut légalement réutiliser ou modifier le
  code.
- **Choix** : MIT (court, permissif, celui de la dépendance TOMLKit) ; Apache-2.0
  (permissif, avec clause de brevets) ; GPL-3.0 (les dérivés restent libres) ; rester sans
  licence.
- **Recommandation** : MIT.
- **Suite après le choix** : créer `LICENSE` à la racine avec le texte officiel, l'année
  2026 et le nom de l'auteur choisi par l'utilisateur ; ajouter une ligne « Licence » en
  bas de `README.md` et `README.fr.md`.

### D2 - Publier une version 0.14.0

- **Constat** : les sessions 142 à 153 sont installées chez l'utilisateur mais non
  publiées. La dernière release est 0.13.0.
- **Pourquoi c'est une décision** : une publication est une action sortante.
- **Suite après le choix** : session de release dédiée, sur le modèle de
  `specs/141-release-0130/`.

### D3 - Section `[launcher]` dans la configuration

- **Constat** : les réglages du lanceur sont rangés sous d'autres sections.
- **Pourquoi ce n'est pas une tâche** : un alias de section crée deux écritures possibles
  pour le même réglage. Les Paramètres réécrivent le fichier ; il faut décider quelle forme
  gagne. Ce choix demande une spécification dédiée.
- **Recommandation** : ne rien faire maintenant.

### D4 - Signature Apple et notarisation

- **Constat** : le DMG est signé ad hoc. macOS affiche un avertissement au premier
  lancement.
- **Pourquoi c'est une décision** : il faut un compte Apple Developer payant (99 USD par
  an).

### D5 - Lancer la CI automatiquement

- **Valeur livrée par les tâches** : workflow présent, déclenchement manuel seul (US8).
- **Décision restante** : faire le premier essai manuel sur GitHub, puis activer ou non le
  déclenchement sur chaque push.
- **Non vérifié** : présence de Swift 6.2 sur la machine GitHub ; comportement des tests
  sans écran ni permission d'accessibilité.

### D8 - Retirer des images ou des preuves publiées

- **Valeur livrée par les tâches** : inventaire seul (US11).
- **Décision restante** : l'utilisateur relit la liste et décide. Un retrait de
  l'historique Git est une réécriture ; il se décide à part.

## Décisions par défaut (appliquées par les tâches)

### D6 - Événements de clic du journal

- **Défaut appliqué** : retirer `drag.real_press` et `drag.real_router_press` (US6).
- **Raison** : aucun lecteur dans `Sources/`, `Tests/`, `scripts/` et `docs/` ; environ
  21 % des lignes du journal ; ils enregistrent la position de chaque clic.
- **Pour changer** : retirer les tâches de la phase US6 avant l'implémentation.

### D15 - Emplacement du journal des sessions

- **Défaut appliqué** : `.specify/memory/sessions/journal.md` (US4).
- **Raison** : le dossier existe déjà et contient les archives de sessions.

### D16 - Premier appel réseau de Roadie

- **Défaut appliqué** : `roadie update check` seulement, à la demande, dans le processus
  de la commande et jamais dans le daemon (US10). Une décision d'architecture (ADR 031)
  l'enregistre.
- **Pour changer** : retirer les tâches de la phase US10 avant l'implémentation.

## Exclusions (aucune tâche)

| Réf. | Sujet | Raison |
|------|-------|--------|
| D7 | Purge automatique des fichiers | Mesure du 10 novembre 2026 : 80 actions, 2,35 Mo, toutes des sauvegardes de configuration, dont des sauvegardes nommées à la main. Le journal tourne déjà seul à 10 Mo. Les 865 Mo de `~/.roadies/diagnostics` et `~/.local/state/roadies/validation` sont des preuves de sessions, que la règle du projet demande de conserver. |
| D9 | Formule Homebrew | Demande un dépôt de formules et une release signée ; dépend de D2 et D4. |
| D10 | Binaire universel (Intel + Apple Silicon) | Aucun poste Intel pour vérifier. |
| D11 | Découpage complet de `LayoutMaintainer.swift` | 4 462 lignes avec un état privé partagé ; un découpage par extensions oblige à élargir la visibilité de dizaines de membres. Risque de régression élevé, gain non mesuré. US9 livre un seul extrait autonome. |
| D12 | Formatage automatique de tout le code | Diff massif sur 540 fichiers, sans gain de comportement ; rend l'historique Git illisible. |
| D13 | Numéros de specs en double (029, 093) et noms de tests par session | Références historiques citées dans les journaux et les reçus ; les renommer casse ces références. |
| D14 | Numéro de version dans `stages.json` | Aucun gain avant le premier changement cassant ; « champ absent = version 1 » fonctionnera de la même façon plus tard. |
| D17 | Aide partagée pour les lectures d'accessibilité | Deux usages seulement ; la règle du projet demande trois usages réels avant une abstraction. |
| D18 | Déclaration unique de chaque réglage | Refonte de la configuration (313 réglages) ; US3 pose des gardes à la place. |
| D19 | Événements `live_tick` et `layout.preparation` | Utilisés par les mesures de performance des sessions 048, 123 et 149. |

## Décisions actées le 10 novembre 2026 (prioritaires)

D1 Apache-2.0. D2 Release 0.14.0 après les développements et corrections.
D3 Section [launcher] acceptée, compatibilité et priorité par clé précisées dans FR-026.
D4 Aucun compte développeur ; avertissement macOS accepté ; signature locale conservée.
D5 CI strictement manuelle, aucun lancement demandé. D8 Retrait des preuves inutiles
autorisé après archive locale ; images utiles conservées ; historique Git inchangé.
