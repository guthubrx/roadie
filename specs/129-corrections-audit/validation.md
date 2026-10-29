# Validation 129 - Corrections de l'audit du 29 octobre 2026

- Avant correction (audit, copie de laboratoire au commit 3c9d66d9) : Run Script `sleep 11` arrêté à
  10,67 s avec « délai dépassé » ; osascript `delay 12` arrêté à 10,67 s ; test différentiel de l'index :
  écarts tous causés par une valeur vide. Preuves : `audits/2026-10-29/session-2026-10-29-codebase-01/notes/constats.md`.
- Après correction : `Spec129AuditFixesTests` - Run Script, Run NSAppleScript et tâche d'automatisation de
  10,5 s menés à terme en parallèle (10,57 s) ; script sans délai ; scripts système gardés (réussite « ok »,
  erreur 42 signalée, -128 muet) par un vrai osascript. `Spec107LiteralIndexTests` - valeur vide puis
  redéfinition refusée, test différentiel de 3 000 fichiers sans écart.
- Suite complète : 2 272 tests / 332 suites réussis (`--skip Audit022R4LotT6Tests|Settings027IPCTests`),
  puis ces deux suites seules : 11 tests réussis. Scripts Python : 28 tests réussis.
- Installation signée `roadied-cert`, PID 79678, santé 5/5. UUID FBD0750B-87C6-34F7-81AF-CDE0F912ED3B.
  Configuration non modifiée.
- Revue indépendante : non lancée. `bridget_auto_delegate` est absent du catalogue Bridget depuis le
  chargement de Bridget211 (incident remis à bridge1016, `mcp-86565-6ae38c5b-1`, sans réponse). Relecture
  du diff complet par le responsable.
- Non vérifié : notification d'échec affichée à l'écran ; boîte de mot de passe de Spotlight réelle ;
  parcours Firefox sur une vraie fenêtre (refonte sans changement de résultat, aucun test AX).
- Preuves : pas de diaporama, clics simulés refusés sur ce poste et notification d'échec non provoquée
  sur le poste de l'utilisateur.
