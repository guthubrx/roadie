# Revue153 — première ronde

Source9cc9a8ee, lecture seule du worktree dédié. Le relecteur n’a pas eu de shell, n’a pas isolé le diffGit et n’a exécuté aucun test. Verdict borné : aucun défaut bloquant trouvé par lecture, un défaut moyen confirmé et plusieurs risques faibles.

- D1 : copie Ctrl+glisser encore visible pendant le drainage de l’écrivain, jusqu’à2s. Corrigé : retrait immédiatement après la soumission des dernières cibles, avant le drainage. L’état de repli reste disponible jusqu’au calcul de ces cibles. Tests avec écrivain bloqué au relâchement et à Échap.
- D2 : capture qui ne revient jamais. Corrigé côté interface : après300ms, échec déclaré et repli sur une vraie fenêtre visible. Un retour tardif reste rejeté. Le SDK ne permet pas d’annuler de force sa requête ; le garde global reste donc occupé jusqu’au vrai retour, pour empêcher une file illimitée de captures. Les gestes suivants utilisent le repli si le SDK reste occupé.
- D3 : une capture peut partir au simple clic éligible sur un titre, afin de garder le contenu initial avant le premier mouvement. Ce coût des clics seuls n’est pas mesuré. Aucune activité de capture n’est ajoutée au repos.
- D4 : callback synchrone inutile en mode contour/aucun. Retiré. La cadence existante et le premier mouvement déclenchent le traitement.
- D5 : mises à jour de position à chaque événement livré, avec regroupement existant du tap ; pas de nouvelle garantie de fréquence. Le panneau ne demande plus son passage devant à chaque mouvement. Les couches graphiques ne sont pas recapturées. Le coût de deux gestes est mesuré dans validation.md ; pas de gain ni de coûtGPU revendiqué.

Risque d’onglet Chrome proposé, non reproduit : la qualification AX refuse déjà les rôles de contrôles et d’onglets. Un groupe réduit de titre doit être sans action et sans enfant ; sinon, refus. Le chemin par mouvement exige la même identitéCG/PID et une taille stable. Les fonctions de qualification sont couvertes par les tests144. Un essai réel d’onglet Chrome n’est pas revendiqué.

Le rapport complet et les reçus natifs sont conservés horsGit dans le dossier de validation153. Les mesures et tests du parent ne sont pas attribués au relecteur. Une seconde lecture ciblée des corrections reste à demander après publication.


## Seconde ronde
Lecture de e3f41477, sans shell, diffGit ni tests exécutés. Aucun défaut concret prouvé. D1 etD2 confirmés corrigés ; callbacksynchrone retiré, passage devant limité à l'ouverture du panneau. Les limites SDK, coût des clics, test temporel et absence de rendu Mac surLinux restent explicites. Rapport complet et reçu horsGit.

Après cette lecture, deux protections minimales ajoutées par le responsable : conserver le cadre initial de la source même si les voisines sont désactivées en mode destinationcontour ; retirer la copie quand le writer invalide sa portée ou sa génération.80tests ciblés verts, dont les deux variantes du suivi des voisines, puis2512tests /380suites verts. Ces dernières lignes n'ont pas fait l'objet d'une troisième revue. L'essai natif de changement de stage a visé une surface autre que le client fictif dans une session concurrente : écarté, aucun succès revendiqué pour cet essai.
