# Variantes : délai court imposé à une opération voulue par l'utilisateur

Mécanisme de départ : une opération que l'utilisateur a demandée explicitement, et qui peut durer,
passe par un lanceur borné (`AlfredScriptRunner`, 10 s par défaut, ou `LauncherBrowsers.run`,
2 s par défaut). Au délai, le processus reçoit SIGTERM (puis SIGINT pour les scripts) : l'opération
s'arrête et sa suite ne s'exécute pas.

Commandes : `grep -n "LauncherBrowsers.run(" Sources/RoadieDaemon/*.swift` et
`grep -n "AlfredScriptRunner.run(\|AlfredScriptRunner.start(" Sources/RoadieDaemon/*.swift`,
puis lecture de chaque appel (révision 3c9d66d9). 8 appels osascript, 7 appels de scripts.

| Appel | Délai | Verdict |
|---|---|---|
| AlfredWorkflowEngine.swift:169, objet `action.script` (Run Script) | 10 s (défaut) | **Variante confirmée** (constat F-RUNSCRIPT). La spec 088 ne fixe 10 s qu'aux Script Filters (FR-004) ; FR-008 n'en fixe aucun. |
| AlfredWorkflowEngine.swift:180, objet Run NSAppleScript | 10 s (défaut) | **Variante confirmée**, même cause, même constat (instance `nsapplescript`). |
| AlfredAutomationTasks.swift:58, tâches d'automatisation | 10 s (défaut) | **Variante confirmée**, même cause (instance `automation-task`). |
| AlfredLiveEffects.swift:205, Run Shortcut | 30 s | Variante possible, plus large : un raccourci de plus de 30 s est arrêté. Gardée comme limite, sans constat séparé. |
| LauncherSystemCommands.swift:125, « Reconstruire l'index Spotlight » (`with administrator privileges`) | 10 s | **Constat F-SPOTLIGHT** : le mot de passe doit être saisi en moins de 10 s. |
| LauncherSystemCommands.swift:125, autres commandes système (corbeille, éjection, volume, session) | 10 s | Réfuté : l'Apple Event est remis au Finder ou à System Events avant l'arrêt d'osascript ; l'arrêt n'annule pas l'opération. |
| AlfredWorkflowEngine.swift:395 et TargetModeRuntimeController.swift:832/992 (Script Filter, File Filter, vues de grille) | 10 s | Conforme à FR-004 (filtres pendant la frappe). |
| AlfredLiveEffects.swift:90/180/215, notifications, Terminal, dialogue | 3 s, 5 s, 600 s | Conforme : opérations courtes, ou dialogue laissé 10 minutes. |
| LauncherTerminal.swift:81, TargetModeRuntimeController.swift:1154/1504/1560 | 5 s ou 2 s | Conforme : ouverture d'une fenêtre ou lecture d'onglets. |

Limite : le comportement d'Alfred (aucun délai pour Run Script) est tiré de sa documentation et de son
usage, pas d'un essai dans Alfred. La boîte de mot de passe n'a pas été ouverte sur le poste de
l'utilisateur ; la reproduction utilise un script `delay 12` avec le même lanceur et le même délai.
