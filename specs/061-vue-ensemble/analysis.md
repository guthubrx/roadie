# Analyze 061 - 2026-10-24

Primitive : protocole speckit-analyze lu ; comparaison directe spec/plan/tasks/constitution, suivie d’une seconde lecture. Le script de prérequis refuse le préfixe session- imposé localement ; son option documentée SPECIFY_FEATURE=061-vue-ensemble résout les chemins sans changer les scripts.

| Exigences | Tâches | Couverture prévue |
|---|---|---|
| FR01, US1 | T002,T003 | inventaire partagé, identité, activation existante |
| FR02,FR04,SC01,SC02 | T004 | deux dispositions, quatre combinaisons, dense |
| FR03,FR05 | T003,T005 | tâche annulée, mouvement réel stabilisé, capture bornée |
| FR06 | T006 | CLI stricte et récepteur indépendant |
| FR07 | T001,T007 | défauts et persistance, touche vide |
| FR08,SC03 | T008,T009,T010,T011 | BTT, natif, docs et livraison |

Correction conservatrice avant code : transmettre aussi l’état persistant déjà lu par load, car le DaemonSnapshot ne représente que le bureau actif. Cela évite une deuxième lecture et conserve les bureaux inactifs nommés. Contrat status : état de configuration/disponibilité, sans présenter une visibilité asynchrone comme confirmée. En forte densité le document défile : aucune promesse que tous les titres restent lisibles sur une page.

Seconde passe : 8/8 exigences et 3/3 stories couvertes. Aucun CRITICAL ni violation constitutionnelle trouvée. Gate de réutilisation PASS. Les preuves restent à produire, pas encore acquises.

Compléments pendant implémentation : registre de composant overview dédié pour éviter un faux succès face à un ancien démon ; colonnes de stages adaptées à la largeur ; réglage de pourcentage sur surface, gardes de minima ; aucun événement disque de survol. Les mêmes exigences sont conservées.

Retour utilisateur : T013/T014/T015 ajoutées après l’essai réel. La carte étirait ses cartes parce que le calcul choisissait les colonnes sur la largeur seule et distribuait toute la hauteur disponible. Le correctif conserve l’ordre, pondère les stages par leur contenu et maximise la surface d’image sur les deux axes. La loupe de fenêtre réutilise le cache et le délai de survol. Le clic de loupe vise son contenu plutôt que les cartes cachées derrière. Les critères de densité et de survol sont renforcés, sans nouveau transport ou dépendance.

Amendements T016/T017 : abandon du panneau de loupe flottant. Port des règles split/grid de la référence, palettes sRGB et fixture de 32 fenêtres. Épuration du bandeau, retrait du pied et overlay sans Space. Test de fermeture Échap ajouté. Suite finale 1918 tests /238 suites réussis en32,863s. Les preuves antérieures sont historiques ; le reçu final identifie le binaire et le parcours qualifiés.
