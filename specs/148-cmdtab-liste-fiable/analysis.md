# Cohérence et revue148

FR1 : nil et vrai snapshot vide sont distincts. Le modèle n’est créé que sur snapshot présent ; après épuisement, message d’indisponibilité au lieu d’absence de fenêtres. FR2 : quatre acquisitions au plus, trois pauses100ms annulables, pas de boucle au repos ni cache ancien ; servicecommunouverture/reload. FR3 : mêmes profils et filtres, pas en attente et acceptation au relâchement conservés dans la machine d’état existante. FR4 : test rouge/vert, sept tests de récupération/annulation/vide/UI, série native et limites dans validation.

Relecture locale : gardes sessionID et loadRevision pour les retours tardifs, Task.isCancelled avant/après le relevé et les étatsAX, anciennes cartes conservées si un reload échoue, Tabrelance une nouvelle acquisition bornée. Une tâche AX déjà engagée n’est pas supposée annulable ; elle n’ouvre plus le panneau après annulation. Les tests de fermeture attendent le fondu existant au lieu de supposer orderOut synchrone.

Complexité : O(w) par acquisition, quatre acquisitions au plus, mémoire O(w). ConcurrenceAX existante bornée à quatrePID. Un événement compact par tentative ou résultat, aucun titre/contenu ajouté. Aucun minuteur permanent nouveau.

Revue indépendante : request_id86fc0a66-308c-4cac-bc65-9bc2148ee00f, expected_base_commit389b3f59f1510b7ac4ad24d78472b6a50236a645, discovery/shared. Refus routing_candidate_unavailable,18capability_unavailable/11workspace_diverged, souscauseunobserved, not_recorded, aucun taskID. Aucun changement de base/hôte/compte/droits ni délégation de contournement.

Signalement selon compétence bridget-signalement du01nov2026 à bridge1016, identité bc833746-3f24-41cd-bc64-46d60f4c0769 résolue dans l’annuaire. Reçu id8cac53e7-c08e-4b4a-a1b2-2d9d9314f997, delivery1d7100bc-ef8c-4485-bc7f-9c32c1e51edf, issued_at1793505040, in_flight. Il prouve l’envoi en cours, pas la lecture/réparation. Aucun rappel périodique.

Compétences utilisées :
/Users/moi/.codex/skills/bridget/SKILL.md
/Users/moi/.agents/skills/bridget-signalement/SKILL.md

Tests exécutés : deux tests rouges avant correction (nil transitoire et absence de reprises),105tests ciblés verts,7tests148 verts,2438tests/365suites en séquentiel et28tests de scripts verts. Les deux premières assertionsUI de fermeture étaient prématurées face au fondu existant ; correction du test avec attente bornée, pas de modification de l’animation.
