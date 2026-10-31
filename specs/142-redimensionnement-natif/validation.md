# Installation vérifiée, essai natif après en attente — Session 142

## Base et parcours avant correction
Source initiale : b223718ff9bedc101035cfd5fb0edc0d8704763f. Version installée 0.13.0 avant changement.
Trois fenêtres AppKit fictives dans une stage dédiée `validation142`. Geste réel sur le bord gauche natif de A, envoyé par l’API officielle BetterTouchTool et observé dans les événements AppKit de la fixture. `cliclick` a été refusé par macOS ; ses premiers essais ne sont pas utilisés comme preuves.

Avant valide : 431 échantillons de cadres entre les bornes du geste. A passe de x=977, largeur=817 à x=857, largeur=937 pendant l’appui. B reste x=977, largeur=817 et C reste largeur=817 pendant cet appui. Après relâchement, B passe à x=857, largeur=937 et C à largeur=697. Cela démontre la suspension actuelle du suivi des voisines.

Les captures originales, événements et échantillons restent hors Git dans le dossier temporaire local de validation. Aucune capture du bureau privé n’est publiée.

## Tests
- Baseline gestes existants : 7 tests réussis.
- Tests ciblés puis non-régression : 77 tests / 11 suites réussis avant élargissement des scénarios.
- Première suite parallèle : 2370 tests / 355 suites, cinq issues. Deux viennent du test socket existant Audit022LotITests. Trois tests nouveaux dépendaient de délais muraux courts sous blocage du MainActor ; synchronisation corrigée, attente du mock rendue explicite et observation ancienne désormais rejetée avant clôture.
- Suite séquentielle : **2370 tests / 355 suites réussis** en 62,736 s.
- Scripts : **28 tests réussis**.
- Contrôles ciblés après durcissement : **105 tests / 14 suites réussis**. Dernière suite complète, incluant la sélection des bords et la publication de la frame native : **2371 tests / 355 suites réussis** en 63,172 s.

## Revue et limites
Revue indépendante du plan traitée dans review-plan.md. Première revue du code traitée dans review-code.md ; seconde revue non admise. Build Release et installation signée vérifiés. Comparaison native après en attente ; diaporama partiel disponible. Aucune latence p95 native ni supériorité de fluidité encore revendiquée.

Analyse croisée SpecKit : 8 exigences couvertes par les 6 tâches ; aucun point critique restant avant implémentation. Self-review : point d’écriture commun, arbre sur MainActor, permission sous verrou, publication validée sur MainActor ; pas de dépendance, format persistant ni réglage ajouté. Les champs transitoires inutilisés et le journal par image ont été retirés.

## Corrections après revue et limites natives
Les trois nouveaux tests de fin/absence et le refus d’un geste sans position passent. Dernière suite après revue : **2375 tests / 355 suites réussis** en 61,099 s ; 21 tests ciblés réussis. Source du build initial installé : d96e303, UUID C23CEE51-20D3-3847-A9A0-B955D1D88943, PID 54558, santé 5/5 ; certificat et configuration identiques.

Le Mac s’est verrouillé avant le parcours après installation : `CGSSessionScreenIsLocked=1`. Aucune tentative de déverrouillage. La stage de travail d’origine a été rétablie ; la fixture a été arrêtée et la stage `validation142` a été supprimée par la commande normale. Le diaporama est **partiel** : trois captures natives avant, clic enregistré et repère vérifié ; étape après explicitement non vérifiée. Aucun gain de latence après installation revendiqué. La comparaison native après et SC-005 restent en attente de bureau déverrouillé.

Le premier contrôle santé après redémarrage a été demandé avant l’ouverture du socket. Le même PID a répondu quelques secondes plus tard ; aucun deuxième changement de version pour cette attente.

## Installation finale après corrections de revue
Source : **f2644698482d638bba3de145073ae3542df00530**. Build Release réussi : roadied 128,87 s, CLI 2,09 s. Installation finale et redémarrage réussis le 31 octobre 2026. UUID **4ED973A1-25AE-39EA-86B7-DA47F3FC7E6D**, PID **81878**, santé **5/5**. Certificat identique et configuration TOML inchangée, empreintes comparées avant/après.

La requête d’état finale confirme la stage d’origine active et l’absence de `validation142`. Aucun raccourci BetterTouchTool permanent n’a été ajouté. Sauvegarde de l’installation précédente conservée hors Git. Commit local sur `session-142-redimensionnement-natif` ; aucune release publiée.

Seconde contre-revue : demande `roadie142-code-review-20261031-02`, source f264469. Admission refusée avec `routing_candidate_unavailable` : `capability_unavailable` et `workspace_diverged`. Aucune tâche créée (`task_id=null`, admission `not_recorded`). Aucun autre moteur ou hôte utilisé pour contourner ce refus.

Preuves **incomplètes** : Mac verrouillé avant l’essai après installation. Le diaporama `preuves-corrections/2026-10-31-142-redimensionnement-natif/preuves.html` montre le symptôme avant et indique explicitement l’étape après non vérifiée. T005 et SC-005 restent ouverts pour cette comparaison. La santé et les tests ne constituent pas une mesure de fluidité native.
