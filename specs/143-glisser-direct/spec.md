# Spécification — Réorganisation réelle pendant le glisser

Branche : `session-143-glisser-direct`. Date : 2026-10-31. Statut : In Progress.
Demande : vraies fenêtres qui font place pendant le glisser, réglage oui/non validé par « go ».

## Scénarios utilisateur
### US1 — Voir le résultat avant de lâcher (P1)
Glisser une fenêtre par sa barre de titre ou depuis le rail vers une fenêtre du bureau actif. Les voisines prennent les places annoncées par le fantôme avant le relâchement. La fenêtre tenue reste sous le contrôle de la souris. La visée reste stable quand les voisines bougent.
### US2 — Choisir le comportement (P1)
Dans Tuilage, désactiver « Réorganiser les fenêtres pendant le glisser » conserve le fantôme et n’écrit aucun aperçu réel. Réactiver permet le suivi au prochain mouvement, sans relance. Le réglage est conservé après redémarrage. Le redimensionnement par les bords reste indépendant.
### US3 — Annuler sans perdre la disposition (P1)
Sortir d’une destination valide restaure les voisines. Échap ou abandon restaure la disposition initiale ; relâcher sur une destination valide applique le dépôt normal. Changer de bureau, fermer une fenêtre ou lancer une autre commande ne doit pas réappliquer un aperçu ancien.

## Exigences
- FR-001 : utiliser exactement les places annoncées par l’aperçu du dépôt existant, sans écrire la fenêtre tenue.
- FR-002 : visée fondée sur la disposition initiale, pas sur les fenêtres déplacées par l’aperçu.
- FR-003 : un réglage global immédiat, persistant, français/anglais dans Tuilage ; activé par défaut pour répondre au besoin demandé, fantôme seul si désactivé.
- FR-004 : ne modifier ni affectation, ni ordre, ni arbre persistant pendant l’aperçu.
- FR-005 : restaurer les voisines après sortie/annulation ; attendre une clôture bornée avant le dépôt définitif.
- FR-006 : coalescer les cibles, isoler les applications lentes et invalider les écritures anciennes ; respecter refus et identités.
- FR-007 : annuler sur changement de contexte ; ne jamais restaurer une ancienne disposition par-dessus une commande nouvelle.
- FR-008 : préserver les dépôts dans le rail et la vue d’ensemble. Cette session modifie l’aperçu des vraies fenêtres du bureau, pas les miniatures internes de la vue d’ensemble.

## Réussite et cas limites
SC-001 : trois fenêtres dédiées ; au moins une voisine change de cadre avant le relâchement en mode actif, aucune en mode désactivé.
SC-002 : dix changements de destination ; dernier aperçu seul retenu, pas d’oscillation de la cible.
SC-003 : annulation/sortie : cadres initiaux retrouvés à la tolérance habituelle ; état persistant identique.
SC-004 : dépôt normal conserve la place obtenue et le réglage survit à une relecture.
SC-005 : suite et revue, preuve native avant/après ; aucune fluidité mesurée annoncée sans observation réelle.
Cas : source flottante ou non redimensionnable, fenêtre disparue, minimum imposé, application lente, écran retiré, nouveau clic pendant clôture, changement de réglage pendant geste.

## Entités et hypothèses
Contexte figé du glisser ; candidat de dépôt ; session d’aperçu réversible ; réglage global. Aucun nouveau raccourci. Pas de nouvelle dépendance. La source n’est jamais déplacée par l’aperçu.
