# Validation152 — correction active, choix visuel en attente

Le 3 novembre2026. Version de validation installée avec signature conservée, UUID17271ADC-FBA2-33F8-A288-0AD631C2EDD2, PID90280, santé5/5. Configuration utilisateur inchangée à l'octet près.535 empreintes Sources/Tests conformes avant activation. Ce travail n'est pas encore intégré dans main.

13 tests ciblés /4 suites verts, puis2485 tests /377 suites verts en75,638s. Cas : ordre non numérique, next/prev au bouclage, pixel de parking déclaré onScreen, propagation réelle de la commande au runtime, masquage d'une fenêtre déjà parkée, effets désactivés et tests existants d'annulation/retarget. Une première compilation de test a détecté un argument StageID à la place du String attendu ; corrigé dans le test avant exécution.

## Observations natives
Deux applications AppKit fictives avec une fenêtre chacune, dans deux stages du même écran interne. Avant : arrivée horizontale depuis le parking x5351 vers x150 dans les deux sens. Les premières séquences après activation ont été interrompues par des pressions réelles de souris ; les journaux effects.frames_cancelled et drag.real_router_press l'établissent. Elles ne sont pas comptées comme validation du trajet. Une commande de préparation a aussi visé l'autre écran sous changement de focus ; une stage vide temporaire homonyme reste à nettoyer.

Séquence complète after-up3 : B→A dans l'ordre persistant A,B. Fenêtre entranteA : parking(5351,32), puis(150,49),(150,39),(150,32). Arrivée depuis le bas et mouvement montant observés. La fenêtre quittéeB ne peut pas se déplacer plus haut que y32 avant le parking.

Séquence complète after-down3 : A→B. SortanteA :(150,32),(150,42),(150,46),(150,52),(150,57), puis parking. EntranteB : parking, puis directement(150,32). Le déplacement descendant est demandé, mais l'application/macOS garde le bord supérieur à32. Le trajet au-dessus de l'écran n'est donc pas observé avec ces vraies fenêtres tuilées.

Conclusion : le trajet de parking droit est supprimé et le sens est transmis correctement. La contrainte du bord supérieur empêche une translation physique complète dans tous les cas. Une capture animée permettrait le rendu complet, mais figerait brièvement le contenu. Question de préférence envoyée à l'utilisateur ; pas de pipeline de capture ajouté sans sa réponse. Les fenêtres fictives ont reçu une demande d'arrêt propre. Les stages et fichiers de construction restent à nettoyer à la clôture.

Preuves partielles : captures pendant le mouvement non enregistrées ; cadres observés par les clients fictifs et commandes réelles de Roadie conservés. Appuis de navigation physiques non enregistrés. Originaux : /Users/moi/.local/state/roadies/validation/2026-11-03-152.

## Compléments après revue

La revue de e3392f5 confirme le calcul du sens et signale un risque de cache d'écrans vide. La commande fournit maintenant les écrans observés au runtime ; un appel sans observation explicite peut lire NSScreen sans AX. Test cache vidé, retarget avec sens opposés et bouclage par la vraie commande ajoutés.15tests ciblés /4suites, puis2487tests /377suites verts en80,105s. Détail : revue.md. Ces compléments de code ne sont pas encore chargés ; le binaire actif reste UUID17271ADC-FBA2-33F8-A288-0AD631C2EDD2. Les deux applications fictives ont terminé proprement ; les trois occurrences de stages temporaires ont été retirées. Configuration initiale identique. Finalisation en attente du choix utilisateur sur les captures animées.

## Capture acceptée et implémentée
L'utilisateur a accepté la capture temporaire à condition de garder une transition courte et réactive. Deux captures ScreenCaptureKit bornées, panneau sans focus et sans clic, vraies fenêtres placées une fois par le dispatcher existant. Images locales en mémoire uniquement. 21 tests ciblés /5 suites verts en3,604s, dont six tests de délais, annulation et source/cible tardives. Une compilation a signalé la visibilité du nouveau type passé à apply ; corrigée. Les anciens tests de commande attendaient un trajet AX intermédiaire ; ils attendent maintenant le placement direct quand la capture est absente, avec ordre/bouclage final conservé. Suite complète, revue et mesures natives en cours. Aucun gain CPU/GPU revendiqué.
