# Livraison — session 029

## Résultat livré

La fermeture confirmée d'une fenêtre actualise maintenant le navrail sans
attendre la grâce générale de 15 secondes. Le navrail masque le membre absent.
Il masque aussi la stage dans la même reconstruction quand elle ne contient
plus aucune fenêtre représentée.

Roadie garde le membre dans son état persistant jusqu'à la purge normale. Une
application relancée peut donc encore retrouver sa stage selon SPEC-016.

## Source et Git

- Base : `6a901de1dd0256dd50abd3e65607a7bce34a7860`.
- Source vérifiée : `94e15e7cc6d5b682329a5efb9fe697f1ed938db9`.
- Intégration dans `main` : `4b1f4171564997355c99f09bf659b405cf12c09e`.
- `origin/main` égalait le commit d'intégration après le premier push.

## Vérifications

- Tests ciblés : 117 tests, 5 suites, succès.
- Suite complète : 1466 tests, 156 suites, succès.
- Revue de code finale : APPROVE, aucun défaut P0, P1 ou P2.
- Audit v14 : A, aucun finding.
- Validateur de l'audit : 0 erreur et 0 avertissement.
- Contrôle Git des espaces : succès.
- Build Release des produits `roadied` et `roadie` : succès.
- Signature de l'application : valide et conforme à son exigence désignée.

## Installation et runtime

- Application : `/Users/moi/Applications/Roadie.app`.
- Version : `0.5.0`, build `1`.
- SHA-256 du démon :
  `e889539d110a6656e8dfe0a670f9c6b37d2a0f54c64972b29ffc454590522945`.
- SHA-256 du client :
  `62d342a0bb38511eda630544d5e35158fee4f39ef5b715cb1c153605992985ca`.
- Ancien PID arrêté proprement : 56325.
- Nouveau PID actif : 93111, depuis le 2026-10-14 à 10:16:47 CEST.
- Santé finale : processus, démon, auto-test et audit d'état au niveau `ok`.
- Accessibilité du démon : active.

## Preuve réelle de fermeture

La fenêtre TextEdit 48425 a fermé après l'activation du nouveau démon.

- `windows.missing_reconciled` : `1791965810247` ms.
- `rail_refresh` pour `stage_store` : `1791965810337` ms.
- Délai observé : 90 ms.
- Durée du rendu du rail : 17,0 ms.
- Latence interne du rafraîchissement : 26,9 ms.
- `missingSince` et `confirmedClosedAt` sont présents pour le membre 48425.

Cette preuve couvre une fermeture réelle dans une stage à plusieurs fenêtres.
Le cas de la dernière fenêtre est couvert par le test déterministe qui vérifie
la disparition simultanée du membre et de la stage.

Le runtime actif est monolithique. Le mode modulaire n'a pas été lancé en
parallèle, car Roadie autorise un seul propriétaire de l'état. Les deux modes
utilisent le même `StageStore`, le même marqueur et le même filtre du rail. Les
tests ciblés couvrent donc leur contrat partagé sans lancer un second daemon.

## Limites conservées

Le client CLI lancé séparément ne possède pas sa propre permission
Accessibilité. Son sous-test isolé peut donc signaler
`accessibilityTrusted=false`. Cette limite ne concerne pas le démon installé.
Le contrôle `query health` confirme `accessibility=true` pour le PID 93111.

L'avertissement Swift existant sur `currentRailSettings` reste inchangé. Il est
hors du périmètre de la session 029.
