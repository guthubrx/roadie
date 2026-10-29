"""Renseigne les observations V15 de l'audit du 29 octobre 2026 ; notes et décision calculées par le moteur."""
from pathlib import Path
import hashlib, json

session = Path(__file__).resolve().parent.parent
root = Path("/tmp/roadie-audit-129")
data = json.loads((session / "input.json").read_text())
runs = {p.parent.name: json.loads(p.read_text()) for p in sorted((session / "runs").glob("*/run.json"))}

def sha(path): return hashlib.sha256(path.read_bytes()).hexdigest()
def artifact(rel): return {"kind": "artifact", "path": rel, "sha256": sha(session / rel)}
def source(rel, line): return {"kind": "source", "path": rel, "sha256": sha(root / rel), "line": line}
def run_file(run_id, name=None):
    run = runs[run_id]
    name = name or run["output"]
    return artifact(f"runs/{run_id}/{name}")

context = artifact("notes/contexte.md")
findings_note = artifact("notes/constats.md")
delays = artifact("notes/variantes-delais.md")
index_variants = artifact("notes/variantes-index-et-parcours.md")
swift = artifact("notes/controle-swift.md")
complexity = artifact("notes/complexite.md")
minimal = artifact("notes/minimalisme-responsabilite.md")
repro = artifact("notes/repro-audit129.swift")
scan = artifact("notes/nested.txt")
tests = run_file("20261029T180536484946Z")
scripts = run_file("20261029T180935866623Z", "stderr.log")
lint = run_file("20261029T180949045528Z")
repro_run = run_file("20261029T181537082575Z")
isolate_run = run_file("20261029T181646448678Z")

manual = {
    "security.authorization": ("unknown", "Entrées ajoutées depuis le 27 octobre lues (ordres à Alfred, réglages gardés, terminal, commandes système, chemins de workflows) ; socket 0600 inchangé. La centaine de commandes CLI n'a pas été relue une à une.", [context, findings_note]),
    "correctness.logic": ("unknown", "Lecture ciblée des sources modifiées et des appelants ; trois défauts de logique confirmés par reproduction. Le reste du dépôt n'est pas relu fonction par fonction.", [context, findings_note, repro_run]),
    "correctness.concurrency": ("unknown", "46 déclarations Sendable non vérifiées recensées, verrous et files des nouveaux magasins relus, gardes des résultats tardifs de la barre vérifiées ; pas d'essai de concurrence.", [context, findings_note]),
    "performance.complexity": ("unknown", "Heuristique sur tout Sources (181 signaux) et relecture des chemins chauds ; un parcours quadratique borné confirmé ; aucune mesure.", [complexity, scan, index_variants]),
    "tests.regression": ("pass", "Suite Swift séquentielle 2 267 tests / 331 suites et 28 tests de scripts réussis au commit figé ; deux suites exclues (signaux forcés, notification globale).", [tests, scripts, swift]),
    "architecture.dependencies": ("pass", "Graphe SwiftPM lu : 5 bibliothèques, 2 exécutables, une dépendance verrouillée (TOMLKit 0.6.0), cycles de modules impossibles ; couplage interne de RoadieDaemon non cartographié.", [swift, context]),
    "quality.minimalism": ("unknown", "Checklist exécutée sur un échantillon de fonctions d'enrobage : ~10 lignes suppressibles ; pas de mesure sur tout le dépôt.", [minimal]),
    "quality.llm": ("unknown", "Volume, abstractions et traduction en lot examinés ; aucune revue indépendante (Bridget indisponible) ; compréhension humaine non démontrable.", [minimal, context]),
    "reliability.observability": ("unknown", "Journal sans saisie de l'utilisateur et rotation existante ; deux échecs silencieux relevés ; aucune observation de production.", [minimal, findings_note]),
    "spec.traceability": ("unknown", "Specs 088 (délais) et 127 (traduction) rapprochées du code ; les 126 autres dossiers ne sont pas revérifiés.", [delays, findings_note]),
}
for control in data["controls"]:
    if control.get("tool"):
        continue  # renseignés par les adaptateurs
    status, reason, evidence = manual[control["id"]]
    control.update(status=status, rationale=reason, evidence=evidence if status in ("pass", "fail") else [])

S = "Le niveau supérieur exige une qualification plus complète."
checks = {
    "axes.security.01": (2, "Semgrep (0 signal), SwiftLint 6 règles (45 signaux relus) et lecture des nouvelles entrées ; peu de règles Swift.", [swift, lint, context]),
    "axes.security.02": (2, "Gitleaks sur les fichiers figés : 0 signal ; aucun contrôle continu démontré.", [run_file("20261029T180009036146Z")]),
    "axes.security.03": (2, "Historique depuis v0.4.0 sans signal ; l'historique complet a dépassé 300 s.", [run_file("20261029T180533513743Z"), swift]),
    "axes.security.04": (2, "Socket local 0600, chemins de workflows et réglages gardés protégés ; scripts de workflow exécutés avec les droits de l'utilisateur, par conception.", [context, findings_note]),
    "axes.security.05": (2, "OSV : une dépendance verrouillée sans avis ; suivi continu non démontré.", [run_file("20261029T180010451804Z")]),
    "axes.reliability.02": (2, "Groupes de processus arrêtés au délai ou à la frappe, pause BTT rétablie au démarrage ; délais inadaptés pour Run Script et Spotlight, pas d'escalade si un script ignore SIGTERM et SIGINT.", [findings_note, delays, repro_run]),
    "axes.tests.01": (3, "Sources et tests Swift compilés au commit figé ; avertissements existants conservés.", [tests, swift]),
    "axes.tests.02": (2, "Semgrep et SwiftLint ciblé exécutés ; tous les signaux et règles Swift ne sont pas qualifiés.", [swift, lint]),
    "axes.tests.03": (2, "2 267 tests réussis, mais trois défauts confirmés n'étaient couverts par aucun test et le test d'équivalence de l'index n'a pas vu la valeur vide.", [tests, repro_run, isolate_run]),
    "axes.performance.01": (2, "Barre : attente de 100 ms entre frappes, une requête Spotlight à la fois, relance des filtres bornée à 0,1-5 s ; pas d'essai de saturation.", [findings_note, complexity]),
    "axes.performance.03": (2, "Délais, annulation et plafonds de sortie présents ; deux délais contredisent l'usage (F-RUNSCRIPT, F-SPOTLIGHT).", [delays, repro_run]),
    "axes.complexity.01": (2, "Points d'entrée chauds relus après une heuristique sur tout Sources ; annotations de complexité absentes sur plusieurs recherches.", [complexity, scan]),
    "axes.complexity.02": (2, "Parcours AX bornés, caches bornés ; un parcours quadratique (n ≤ 4 000) et une requête de fichiers récents sans plafond.", [complexity, index_variants]),
    "axes.complexity.03": (2, "Index TOML O(L) puis O(1), copies SQLite hors du fil principal avec cache ; coût disque des copies non mesuré.", [complexity]),
    "axes.quality.01": (2, "Messages traduits et refus explicites ; reconstruction Spotlight et commandes système sans retour d'échec.", [findings_note]),
    "axes.quality.02": (2, "Retour arrière des tâches d'automatisation et échange atomique relus ; interruption réelle non simulée.", [context]),
    "axes.architecture.01": (2, "Frontières SwiftPM claires ; RoadieDaemon de 62 730 lignes sans frontières internes mesurées.", [swift, minimal]),
    "axes.architecture.02": (2, "Cycles de modules impossibles par SwiftPM ; cycles internes au module non analysés.", [swift]),
    "axes.architecture.04": (2, "Symboles privés de macOS chargés par dlsym et protégés par des optionnels ; leur disparition dégraderait la fonction sans arrêt, non testé sur d'autres versions.", [context]),
    "axes.ai_hygiene.01": (2, "Invariants, bornes et complexités commentés dans le code récent ; plusieurs recherches sans annotation.", [minimal, complexity]),
    "axes.ai_hygiene.02": (2, "Changements ciblés par session et tests associés ; trois fichiers de plus de 2 000 lignes alourdissent la maintenance.", [minimal]),
    "axes.ai_hygiene.03": (1, "Aucune revue indépendante : délégation Bridget absente du catalogue ; relecture par le même agent.", [context]),
    "axes.minimalism.01": (3, "Une seule dépendance d'exploitation, verrouillée et utilisée pour la configuration.", [swift, run_file("20261029T180010451804Z")]),
    "axes.minimalism.03": (2, "~10 lignes suppressibles relevées sur un échantillon ; pas de recherche de code mort sur tout le dépôt.", [minimal]),
    "axes.business.01": (2, "Signets et historiques lus sur copie ; affichage d'une valeur non appliquée pour un fichier TOML invalide (F-LITERAL-EMPTY).", [findings_note, isolate_run]),
    "axes.business.03": (2, "Spec 088 et 127 rapprochées : Run Script plus restrictif que la spec, traduction complète vérifiée par recherche des textes restants.", [delays, findings_note]),
    "axes.traceability.01": (2, "Chaque constat relié à sa reproduction, ses exécutions et ses variantes.", [findings_note, repro, repro_run]),
    "axes.traceability.02": (1, "Exigences de 2 spécifications sur 128 vérifiées.", [delays]),
}
for check in data["axis_checks"]:
    check.pop("level", None); check.pop("rating_rationale", None)
    if check["axis"] == "llm_security":
        check.update(status="not_applicable", rationale="Aucun appel à un service LLM dans les sources ni dans les dépendances du produit.", evidence=[])
    elif check["id"] in checks:
        level, reason, evidence = checks[check["id"]]
        check.update(status="pass", rationale=reason, level=level, rating_rationale=reason + " " + S, evidence=evidence)
    else:
        check.update(status="unknown", rationale="Non vérifié dans cet audit ; preuve ou mesure insuffisante.", evidence=[])

def finding(rule, file, symbol, instance, line, title, severity, confidence, category, reason, remediation, evidence, variants, axes):
    return {"rule_id": rule, "file": file, "symbol": symbol, "instance": instance, "line": line, "category": category,
            "title": title, "severity": severity, "confidence": confidence, "status": "confirmed", "rationale": reason,
            "remediation": remediation, "evidence": evidence,
            "variants": {"status": "done", "rationale": "Recherche du même mécanisme documentée avec ses motifs, témoins et limites.", "evidence": [variants]},
            "axes": axes}

engine = "Sources/RoadieDaemon/AlfredWorkflowEngine.swift"
data["findings"] = [
    finding("REL-SCRIPT-TIMEOUT", engine, "AlfredWorkflowEngine.process", "run-script-default-timeout", 169,
            "Action Run Script arrêtée après 10 secondes", "MEDIUM", "high", "reliability",
            "Run Script reçoit le délai par défaut des Script Filters (10 s) ; la spec 088 ne le fixe qu'aux filtres. Reproduit : arrêt à 10,67 s, suite non exécutée.",
            "Passer un délai propre aux filtres et laisser Run Script aller à son terme (ou un délai long réglable), annulation explicite conservée.",
            [source(engine, 169), findings_note, repro, repro_run], delays, ["reliability", "business"]),
    finding("REL-SCRIPT-TIMEOUT", engine, "AlfredWorkflowEngine.process", "nsapplescript-default-timeout", 180,
            "Action Run NSAppleScript arrêtée après 10 secondes", "MEDIUM", "high", "reliability",
            "Même appel sans délai que Run Script, pour l'objet Run NSAppleScript ; même cause que le cas reproduit.",
            "Même correction que pour Run Script.", [source(engine, 180), delays], delays, ["reliability", "business"]),
    finding("REL-SCRIPT-TIMEOUT", "Sources/RoadieDaemon/AlfredAutomationTasks.swift", "AlfredAutomationTasks.run", "automation-task-default-timeout", 58,
            "Tâche d'automatisation arrêtée après 10 secondes", "MEDIUM", "high", "reliability",
            "Les tâches d'automatisation passent par AlfredScriptRunner.run sans délai : une tâche longue est arrêtée à 10 s.",
            "Délai adapté aux tâches longues, ou aucun délai avec annulation explicite.",
            [source("Sources/RoadieDaemon/AlfredAutomationTasks.swift", 58), delays], delays, ["reliability", "business"]),
    finding("REL-AUTH-TIMEOUT", "Sources/RoadieDaemon/LauncherSystemCommands.swift", "LauncherSystemCommand.run", "rebuild-spotlight-auth-timeout", 109,
            "Reconstruction Spotlight interrompue si le mot de passe prend plus de 10 s", "LOW", "medium", "reliability",
            "La commande `with administrator privileges` passe par un osascript arrêté à 10 s ; reproduit avec le même lanceur. Fermeture de la boîte d'authentification non observée.",
            "Délai long ou absent pour cette commande, et message en cas d'échec ou d'annulation.",
            [source("Sources/RoadieDaemon/LauncherSystemCommands.swift", 109), source("Sources/RoadieDaemon/LauncherSystemCommands.swift", 125), findings_note, repro_run], delays, ["reliability", "quality"]),
    finding("DATA-LITERAL-INDEX", "Sources/RoadieDaemon/ConfigFileEditor.swift", "ConfigFileEditor.literalIndex", "empty-value-duplicate", 132,
            "Index des littéraux : doublon non refusé après une valeur vide", "LOW", "high", "business",
            "Une clé à valeur vide n'est pas notée ; sa redéfinition est indexée au lieu d'être refusée comme doublon, contrairement à readLiteral. Test différentiel : une seule cause.",
            "Noter la clé (ou la refuser) avant `continue` quand la valeur est vide, puis ajouter le cas au test d'équivalence.",
            [source("Sources/RoadieDaemon/ConfigFileEditor.swift", 132), findings_note, repro_run, isolate_run], index_variants, ["business", "tests"]),
    finding("PERF-QUADRATIC-BFS", "Sources/RoadieDaemon/LauncherOpenItems.swift", "FirefoxTabSelector.select", "array-removefirst-bfs", 160,
            "Parcours en largeur quadratique des onglets de Firefox", "LOW", "high", "performance",
            "removeFirst() sur un Array à chaque pas : O(n²) pour n ≤ 4 000 éléments par fenêtre ; borne écrite, complexité non annotée ; durée non mesurée.",
            "Lire la file avec un indice (ou un ArraySlice) pour revenir à O(n).",
            [source("Sources/RoadieDaemon/LauncherOpenItems.swift", 160), complexity], index_variants, ["complexity", "performance"]),
]
data["minimalism"] = "Potentiel minimalisme : ~10 lignes suppressibles à comportement constant, estimé sur un échantillon de fonctions d'enrobage (voir notes/minimalisme-responsabilite.md) ; non mesuré sur tout le dépôt."
data["responsibility"] = "Code récent commenté avec bornes et complexités ; volume ajouté au service des fonctions demandées ; trois fichiers de plus de 2 000 lignes augmentent la charge cognitive ; aucune revue indépendante dans cet audit."
(session / "input.json").write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n")
print("constats :", len(data["findings"]))
