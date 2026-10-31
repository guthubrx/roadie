# Revue du code — ronde 1

Demande Bridget `roadie142-code-review-20261031-01`, tâche `8ef9883d-0386-438a-9147-17a57979b289`, message `ee0a1b17-7d79-4b43-81eb-8748ea066ba1`. Source d96e303cf60d7eacdd4d64e27a377c1f72468467. Réviseur sélectionné automatiquement ; lecture seule. Verdict APPROVE_WITH_CHANGES.

Limites explicites : fichiers finaux lus, sans shell ni comparaison Git ; writer et registre non relus en diff ; aucun test exécuté par le réviseur. Les affirmations sur la fluidité restent des hypothèses, sans mesure après installation.

| Constat | Vérification locale | Décision |
|---|---|---|
| HIGH : deux décodages JSON par image | Faux : JSONPersistence.read, lignes 215–230, rend la valeur décodée en cache quand readSigned renvoie unchanged. readSigned, lignes 240–260, ouvre et vérifie fstat sans relire les octets si la signature correspond. StageStore et LayoutIntentStore utilisent ce chemin. | Ne pas ajouter une nouvelle couche de cache ni espacer à 250 ms la vérification des commandes concurrentes. Coût de signature hors MainActor ; aucun gain de décodage revendiqué. |
| Fin suspendue si toutes les observations vieillissent >100 ms | Reproductible par le contrat : la seule branche acceptée terminait le geste. | Retenu : watchdog de clôture à 2 s dans pulse, annulation et repli normal. Test endingWatchdogReleasesLayoutWithoutAcceptingOldObservation. |
| Un nil WindowServer annule trop vite | Une absence unique passait par la garde commune. | Retenu : tolérer deux observations invalides et annuler à la troisième ; contexte invalidé toujours immédiat. Tests absence unique et absence persistante. |
| À vérifier : geste terminé laissé après annulation | C’est le repli volontaire : aucune proportion native n’a été enregistrée, le chemin ordinaire doit pouvoir adopter la taille finale. Effacer systématiquement perdrait ce geste. Un scope obsolète est déjà rejeté par validPendingGesture. | Conserver le repli. Test persistentMissingObservationFallsBackToOrdinaryGestureExactlyOnce : arbre inchangé, un geste disponible puis nil. |
| Position de départ absente acceptée | Possible pour un appel public synthétique ; production la fournit toujours. | Retenu : refuser nil. Test absentPointerLocationCannotStartNativeSession. |
| Un appel AX engagé peut survivre à la clôture bornée | Réel et documenté dans ADR 022 : un appel engagé n’est pas annulable. Permission contrôlée entre attributs et publication rejetée si invalide. | Compromis conservé : ne pas attendre indéfiniment une application. Aucun arrêt immédiat d’un appel engagé promis. |
| Poignée concurrente | UserInputActivity.claimExplicitResize efface la session native d’entrée ; la prochaine génération de la poignée invalide son permis. | Vérifications communes et tests des poignées conservés ; pas de second écrivain bas niveau. |

Tests ciblés après changements : 21 tests / 4 suites réussis. Dernière suite complète après corrections : **2375 tests / 355 suites réussis**, 61,099 s. Deuxième revue ciblée à suivre. Source installée initiale C23CEE51-20D3-3847-A9A0-B955D1D88943, santé 5/5. Le Mac s’est verrouillé avant l’essai après installation ; aucune validation visuelle après revendiquée.
