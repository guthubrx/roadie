"""Renseigne les observations V15 ; les notes et la décision restent calculées par le moteur."""
from pathlib import Path
import hashlib
import json

session = Path(__file__).resolve().parent.parent
root = Path("/Users/moi/Nextcloud/10.Scripts/39.roadie")
manifest = json.loads((session / "manifest.json").read_text())
data = json.loads((session / "input.json").read_text())
runs = []
for path in sorted((session / "runs").glob("*/run.json")):
    run = json.loads(path.read_text())
    runs.append((path.parent, run))

def artifact(relative):
    path = session / relative
    return {"kind": "artifact", "path": str(relative), "sha256": hashlib.sha256(path.read_bytes()).hexdigest()}

def run_output(predicate, current=False):
    matching = [(folder, run) for folder, run in runs if predicate(run) and run["status"] == "completed"
                and (not current or run["revision"] == manifest["revision"])]
    if not matching:
        raise RuntimeError("Exécution attendue introuvable")
    folder, run = matching[-1]
    return artifact((folder / run["output"]).relative_to(session))

def custom_contains(part, current=False):
    return run_output(lambda run: run["tool"] == "custom" and part in " ".join(run["argv"]), current=current)

context = artifact("notes/contexte.md")
cycles = artifact("notes/cycles-et-limites.md")
workflow = artifact("notes/variantes-workflow.md")
values = artifact("notes/variantes-valeurs.md")
persistence = artifact("notes/variantes-persistance.md")
replacement = artifact("notes/variantes-remplacement.md")
swift = artifact("notes/controle-swift.md")
review = artifact("notes/revue-independante.md")
counter = artifact("notes/contre-audit-workflow.md")
final_tests = custom_contains("Audit022R4LotT6Tests|Spec088ScriptRunnerTests|Settings027IPCTests", current=True)
additional_scan = custom_contains("--no-git-ignore", current=True)
script_folder, script_run = [(folder, run) for folder, run in runs if run["revision"] == manifest["revision"]
                             and run["status"] == "completed" and "unittest discover -s scripts/tests" in " ".join(run["argv"])][-1]
script_tests = artifact((script_folder / "stderr.log").relative_to(session))
before_paths = custom_contains("repro-workflow-path.swift")
before_numbers = custom_contains("repro-valeurs.py")
before_ranking = custom_contains("repro-ranking.py")
before_review = custom_contains("repro-postreview.py")

for control in data["controls"]:
    if control.get("tool"):
        if control["id"] == "security.static" and control["status"] == "pass":
            if additional_scan not in control["evidence"]:
                control["rationale"] += " Les quatre nouveaux fichiers ont été analysés séparément avec les mêmes règles figées."
                control["evidence"].append(additional_scan)
        continue  # Les adaptateurs ont renseigné les outils réellement exécutés.
    control.update(status="unknown", rationale="Contrôle partiel : le dépôt entier n'a pas été lu fonction par fonction ; voir les limites.", evidence=[])
    if control["id"] == "tests.regression":
        control.update(status="pass", rationale="Suite Swift séquentielle et tests de scripts exécutés sur la dernière révision ; trois suites Swift exclues pour les signaux et notifications système.", evidence=[final_tests, script_tests, cycles])

checks = {
    "axes.security.01": (2, "Semgrep et cinq règles SwiftLint ; une seule règle Semgrep Swift, lecture manuelle partielle.", [swift, additional_scan]),
    "axes.security.02": (2, "Recherche locale des secrets des fichiers ; configuration d'exclusion figée, pas de contrôle continu démontré.", [run_output(lambda r: r["tool"] == "gitleaks", current=True)]),
    "axes.security.03": (2, "Historique examiné depuis v0.4.0 ; commits antérieurs exclus.", [run_output(lambda r: r["tool"] == "gitleaks-history", current=True)]),
    "axes.security.04": (2, "Socket local 0600 examiné ; scripts de workflow exécutés avec les droits de l'utilisateur, sans isolement démontré.", [context]),
    "axes.security.05": (2, "OSV a examiné une dépendance Swift verrouillée ; suivi continu non démontré.", [run_output(lambda r: r["tool"] == "osv-scanner", current=True)]),
    "axes.reliability.01": (2, "Fichiers illisibles conservés et écritures transactionnelles testées sur cinq magasins ; restauration globale non testée.", [persistence, final_tests]),
    "axes.reliability.02": (2, "Échange atomique et panne injectée testés ; interruption réelle pendant l'échange non testée.", [replacement, final_tests]),
    "axes.tests.01": (3, "Sources et tests Swift compilés ; avertissements existants et suites exclues conservés.", [final_tests]),
    "axes.tests.02": (2, "Semgrep et SwiftLint ciblé exécutés ; toutes les règles Swift et tous les signaux ne sont pas qualifiés.", [swift]),
    "axes.tests.03": (2, "Suite Swift et tests ciblés réussis ; trois suites exclues et parcours graphique non exécuté.", [final_tests, cycles]),
    "axes.performance.03": (2, "Délai et annulation du lanceur lus ; tests de signaux groupés exclus.", [context, cycles]),
    "axes.complexity.01": (2, "Quelques chemins critiques lus ; inventaire des complexités de tous les points d'entrée incomplet.", [swift, cycles]),
    "axes.complexity.02": (2, "Borne de récursion et allocations examinées sur les calculs et sorties de scripts ; reste du dépôt partiel.", [values, context]),
    "axes.quality.01": (2, "Erreurs explicites de stockage et notifications ajoutées ; résultat CLI de projet toujours asynchrone.", [persistence, review]),
    "axes.quality.02": (2, "Échec de remplacement injecté et ancienne donnée conservée ; interruption réelle non simulée.", [replacement, final_tests]),
    "axes.architecture.01": (2, "Dépendances de modules et accès aux fichiers lus sur les chemins audités ; frontières internes non exhaustives.", [context]),
    "axes.architecture.02": (2, "Graphe des cibles Swift lu ; aucune analyse complète des cycles internes.", [context]),
    "axes.ai_hygiene.01": (2, "Invariants et limites des corrections expliqués ; tous les invariants historiques ne sont pas relus.", [cycles]),
    "axes.ai_hygiene.02": (2, "Patch ciblé avec tests ; la maintenabilité globale reste partiellement examinée.", [review, final_tests]),
    "axes.ai_hygiene.03": (3, "Contre-audit et revues indépendantes documentés ; aucun essai macOS côté relecteurs.", [review, counter]),
    "axes.minimalism.01": (2, "Une dépendance Swift directe verrouillée ; aucune preuve exhaustive d'absence de dépendances évitables.", [context]),
    "axes.business.01": (2, "Conservation des fichiers et lecture de workflows testées sur des données synthétiques ; usage réel non rejoué.", [persistence, final_tests]),
    "axes.business.02": (2, "Installation, remplacement et suppression ordinaires testés ; idempotence générale non démontrée.", [workflow, final_tests]),
    "axes.traceability.01": (2, "Reproductions, corrections et tests reliés ; couverture des spécifications historiques incomplète.", [cycles, final_tests]),
}
for check in data["axis_checks"]:
    check.pop("level", None)
    check.pop("rating_rationale", None)
    if check["axis"] == "llm_security":
        check.update(status="not_applicable", rationale="Aucun appel à un service LLM trouvé dans les sources et dépendances du produit.", evidence=[])
    elif check["id"] in checks:
        level, reason, evidence = checks[check["id"]]
        check.update(status="pass", rationale=reason, level=level, rating_rationale=reason + " Le niveau supérieur exige une qualification plus complète.", evidence=evidence)
    else:
        check.update(status="unknown", rationale="Non vérifié pour l'ensemble du dépôt ; preuve ou mesure insuffisante.", evidence=[])

def finding(rule, file, symbol, instance, title, severity, reason, evidence, variant, axes, counter_review=False):
    text = (root / file).read_text().splitlines()
    line = next((i for i, row in enumerate(text, 1) if symbol.split(".")[-1] in row), 1)
    item = {"rule_id": rule, "file": file, "symbol": symbol, "instance": instance, "line": line,
            "category": "security" if "security" in axes else "reliability", "title": title,
            "severity": severity, "confidence": "high", "status": "fixed", "rationale": reason,
            "remediation": "Correction ciblée appliquée et vérifiée par les tests référencés.", "evidence": evidence,
            "variants": {"status": "done", "rationale": "Recherche des variantes documentée ; limites conservées.", "evidence": [variant]},
            "fix_validation": {"status": "done", "rationale": "Reproduction ou code initial conservé ; test du correctif dans un environnement synthétique, sans installation.", "evidence": [final_tests]},
            "axes": axes}
    if counter_review:
        item["counter_audit"] = {"reviewer": "Bridget : revue indépendante documentée", "independent": True,
                                 "verdict": "confirmed", "rationale": "Revue indépendante par lecture ; reproduction locale distincte.", "evidence": [counter if rule == "SEC-WORKFLOW-PATH" else review]}
    return item

items = [
    finding("SEC-WORKFLOW-PATH", "Sources/RoadieDaemon/CLICommandRouter.swift", "workflowDirectoryName", "reserved-component", "Suppression hors du dossier des workflows", "HIGH", "Les composants . et .. pouvaient viser le dossier des workflows ou son parent.", [before_paths, workflow], workflow, ["security", "reliability"], True),
    finding("REL-WORKFLOW-REPLACE", "Sources/RoadieDaemon/StagedFileReplacement.swift", "install", "delete-before-move", "Perte de l'ancien workflow si le remplacement échoue", "HIGH", "L'ancien dossier était supprimé avant le déplacement ; l'échange prépare maintenant la copie et conserve l'ancienne en cas d'échec.", [before_review, review], replacement, ["reliability", "business"], True),
    finding("REL-TASKS-REPLACE", "Sources/RoadieDaemon/AlfredAutomationTasks.swift", "install", "delete-before-move-tasks", "Mise à jour incomplète des tâches d'automatisation", "MEDIUM", "La variante Tasks et LICENSE supprimait les éléments installés avant leur remplacement.", [replacement, artifact("notes/original/AlfredAutomationTasks.swift")], replacement, ["reliability", "business"]),
    finding("SEC-PLIST-INTEGER", "Sources/RoadieDaemon/AlfredWorkflow.swift", "int", "double-out-of-range", "Arrêt sur un nombre de workflow hors plage", "MEDIUM", "Un réel plist de 1e100 provoquait une conversion fatale ; les valeurs hors plage sont refusées.", [before_numbers, values], values, ["security", "quality"]),
    finding("REL-KEYCODE", "Sources/RoadieDaemon/AlfredLiveEffects.swift", "keyCombo", "keycode-out-of-range", "Arrêt sur un code de touche hors plage", "MEDIUM", "La conversion d'un entier supérieur à UInt16 arrêtait le processus ; le test remplace l'émetteur réel.", [before_numbers, values], values, ["reliability", "tests"]),
    finding("REL-CALCULATOR-DEPTH", "Sources/RoadieDaemon/LauncherCalculator.swift", "unary", "unbounded-recursion", "Arrêt sur une expression très imbriquée", "MEDIUM", "Une expression de 50 000 parenthèses arrêtait le sous-processus ; la profondeur est bornée.", [before_numbers, values], values, ["reliability", "performance"]),
    finding("REL-RANK-OVERFLOW", "Sources/RoadieDaemon/LauncherRanking.swift", "prefixUses", "counter-overflow", "Débordement des compteurs de classement", "LOW", "Un compteur Int.max pouvait provoquer un arrêt à l'incrément ou à la somme.", [before_ranking, swift], values, ["reliability", "complexity"]),
    finding("REL-RANK-ANCHOR", "Sources/RoadieDaemon/LauncherRanking.swift", "updatedAnchor", "nonfinite-anchor", "Ancre extrême rendant le classement non encodable", "MEDIUM", "Une ancre finie extrême produisait une valeur infinie ; les scores et ancres restent finis.", [before_review, review], values, ["reliability", "business"]),
]
for file, symbol, instance, title in [
    ("LauncherHistory.swift", "record", "history", "Historique de saisie"),
    ("LauncherMemory.swift", "update", "memory", "Mémoire des déplacements"),
    ("LauncherAliases.swift", "save", "aliases", "Abréviations enregistrées"),
    ("LauncherRanking.swift", "recordVisit", "ranking", "Classement du lanceur"),
    ("StageProjects.swift", "save", "projects", "Projets de stages"),
]:
    items.append(finding("DATA-TRANSACTION", "Sources/RoadieDaemon/" + file, symbol, instance,
        title + " : écriture non transactionnelle", "MEDIUM",
        "Lecture et écriture séparées pouvaient écraser une modification concurrente ou un état illisible.",
        [persistence, artifact("runs/20261027T052611780366Z/stdout.json")], persistence, ["reliability", "business"]))

data["findings"] = items
data["minimalism"] = "Potentiel minimalisme : non mesuré pour tout le dépôt ; une suppression présumée a été annulée après échec de compilation."
data["responsibility"] = "Correctifs ciblés, reproductions et revues conservées ; l'ensemble des invariants du dépôt et la compréhension de l'auteur humain ne sont pas démontrés."
(session / "input.json").write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n")
print("observations et preuves préparées :", len(items), "constats")
