"""Observations V15 de la session 131 ; notes et décision calculées par le moteur."""
from pathlib import Path
import hashlib, json
session = Path(__file__).resolve().parent.parent
data = json.loads((session / "input.json").read_text())
runs = {p.parent.name: json.loads(p.read_text()) for p in sorted((session / "runs").glob("*/run.json"))}
def sha(path): return hashlib.sha256(path.read_bytes()).hexdigest()
def artifact(rel): return {"kind": "artifact", "path": rel, "sha256": sha(session / rel)}
def run_by(pred, name=None):
    rid = [k for k, r in runs.items() if r["status"] == "completed" and pred(r)][-1]
    return artifact(f"runs/{rid}/{name or runs[rid]['output']}")
analysis = artifact("notes/analyse.md")
measure = artifact("notes/mesure-dictionnaire.swift")
trial = artifact("notes/essai-utilisateur.md")
runtime = artifact("notes/mesures-runtime.md")
root = session.parent.parent.parent
def source(rel, line): return {"kind": "source", "path": rel, "sha256": sha(root / rel), "line": line}
def fixed(rule, rel, symbol, instance, line, category, title, severity, rationale, remediation, variants, extra=()):
    return {"rule_id": rule, "file": rel, "symbol": symbol, "instance": instance, "line": line, "category": category,
            "title": title, "severity": severity, "confidence": "high", "status": "fixed", "rationale": rationale,
            "remediation": remediation, "evidence": [source(rel, line), trial, *extra],
            "variants": {"status": "done", "rationale": variants, "evidence": [trial]},
            "fix_validation": {"status": "done", "rationale": "Corrigé après le commit audité (6d17d0da), test ou rendu de contrôle, confirmé par l'utilisateur.", "evidence": [trial, *extra]}}
tests = run_by(lambda r: r["tool"] == "custom" and r["argv"][0].endswith("scripts/test"))
scripts = run_by(lambda r: r["tool"] == "custom" and "unittest" in " ".join(r["argv"]), "stderr.log")
lint = run_by(lambda r: r["tool"] == "custom" and "swiftlint" in r["argv"][0])
manual = {
    "security.authorization": "Diff lu : aucune nouvelle entrée ; écritures de fichiers sur verbe explicite, corbeille seule suppression, menus de l'application mémorisée seulement.",
    "correctness.logic": "Diff et appelants lus ; tables d'Alfred prouvées ou déduites et documentées ; numéro inconnu refusé ; convergence FR-003 ajoutée et testée.",
    "correctness.concurrency": "États partagés ajoutés sous verrou ou sur le fil principal ; boîte Sendable justifiée ; session de barre neuve à chaque ouverture.",
    "performance.complexity": "Recherches O(n) sur listes préparées, menus bornés, dictionnaire mesuré (92 ms à froid, 10 ms ensuite).",
    "tests.regression": "Suite complète 2 318 tests / 343 suites et 28 tests de scripts au commit audité.",
    "architecture.dependencies": "Aucune dépendance ajoutée ; six fichiers pour des responsabilités distinctes ; réutilisations listées.",
    "quality.minimalism": "Checklist exécutée sur le diff : ~3 lignes suppressibles ; réutilisations préférées aux créations.",
    "quality.llm": "Diff relu, invariants et limites écrits ; pas de revue indépendante (Bridget indisponible).",
    "reliability.observability": "Événements ajoutés sans saisie ni chemin (nombres, durées, verbe) ; échecs de verbes notifiés.",
    "spec.traceability": "FR-001 à FR-016 reliées au code et aux tests (Converge) ; SC-003 non mesuré, journalisé.",
}
for control in data["controls"]:
    if control.get("tool"): continue
    evidence = [analysis] + ([tests, scripts] if control["id"] == "tests.regression" else [])
    if control["id"] == "performance.complexity": evidence.append(measure)
    control.update(status="pass", rationale=manual[control["id"]], evidence=evidence)
S = " Le niveau supérieur exige une qualification plus complète."
checks = {
    "axes.security.01": (3, "Semgrep sans signal, SwiftLint sur les sources changées (2 signaux nouveaux, protégés), diff lu en entier.", [analysis, lint]),
    "axes.security.02": (2, "Gitleaks sans signal sur les fichiers figés.", [run_by(lambda r: r["tool"] == "gitleaks")]),
    "axes.security.03": (3, "Historique de la session (depuis a9c627fc) sans signal.", [run_by(lambda r: r["tool"] == "gitleaks-history")]),
    "axes.security.04": (3, "Actions locales sur verbe explicite, sans shell, arguments séparés, application ciblée mémorisée.", [analysis]),
    "axes.security.05": (2, "Aucune dépendance ajoutée ; OSV sans avis.", [run_by(lambda r: r["tool"] == "osv-scanner")]),
    "axes.reliability.02": (2, "Tâches téléchargées une fois par processus ; échecs notifiés ; reprise après échec non testée en réel.", [analysis]),
    "axes.tests.01": (3, "Sources et tests compilés au commit audité.", [tests]),
    "axes.tests.02": (2, "Semgrep et SwiftLint ciblés ; règles Swift limitées.", [lint]),
    "axes.tests.03": (3, "Tests de chaque exigence, dont mise en page réelle des tableaux et données réelles de macOS ; suite complète réussie.", [tests, analysis]),
    "axes.tests.05": (2, "Rendus hors écran regardés (grille, tableau) ; parcours graphiques réels non rejoués.", [analysis]),
    "axes.performance.01": (2, "Menus lus une fois par ouverture, raccourcis Apple gardés 10 minutes ; pas d'essai de charge.", [analysis]),
    "axes.performance.03": (3, "Lectures AX bornées (0,25 s par appel, 0,8 s au total), osascript borné, empreinte hors du fil principal.", [analysis]),
    "axes.performance.04": (2, "Dictionnaire mesuré ; durée des menus seulement journalisée.", [measure, analysis]),
    "axes.complexity.01": (3, "Complexités annotées sur chaque fonction publique ajoutée.", [analysis]),
    "axes.complexity.02": (3, "Parcours bornés (menus, symboles 600 résultats, taille de dossier 50 000 éléments).", [analysis]),
    "axes.complexity.03": (2, "Catalogue SF Symbols lu une fois ; empreinte par blocs ; coût du très gros fichier non borné en durée.", [analysis]),
    "axes.quality.01": (3, "Refus explicites (destination, homonyme, numéro inconnu) et notifications d'échec.", [analysis]),
    "axes.quality.02": (2, "Bilan par source pour les lots ; « en remplaçant » met l'ancien à la corbeille avant l'écriture.", [analysis]),
    "axes.tests.04": (2, "Runtime livré installé et signé, santé 5/5 ; parcours réels de l'utilisateur sur ce runtime (C1 à C4 trouvés et corrigés).", [runtime, trial]),
    "axes.performance.02": (2, "Catalogue SF Symbols mesuré (environ 5 Mio, chargé à l'ouverture du navigateur) ; roadied 246 Mio sans référence antérieure.", [runtime, artifact("notes/mesure-memoire.swift")]),
    "axes.minimalism.02": (2, "Binaire +2,4 % (+506 112 octets) contre la 0.11.1 publiée ; aucune dépendance ajoutée.", [runtime]),
    "axes.business.02": (2, "Clés ajoutées facultatives, défauts identiques à l'existant, valeur inconnue ramenée au défaut ; fichier d'épinglage absent = vide.", [runtime, tests]),
    "axes.quality.03": (2, "Parcours réels essayés par l'utilisateur (29-30 octobre) : quatre défauts trouvés (C1 à C4), corrigés après le commit audité et confirmés ; fiche Informations remplacée par la fenêtre du Finder.", [trial]),
    "axes.architecture.01": (3, "Logique pure dans des fichiers dédiés, contrôleur réduit à l'aiguillage.", [analysis]),
    "axes.architecture.04": (2, "Données SF Symbols et dictionnaire de macOS lus au besoin, repli vide si absents.", [analysis]),
    "axes.ai_hygiene.01": (3, "Invariants, preuves et limites écrits (research, analyse, validation).", [analysis]),
    "axes.ai_hygiene.02": (3, "Changements par lot, commits par lot, tests par exigence.", [analysis, tests]),
    "axes.ai_hygiene.03": (1, "Pas de revue indépendante : délégation Bridget indisponible.", [analysis]),
    "axes.minimalism.01": (3, "Aucune dépendance ajoutée.", [run_by(lambda r: r["tool"] == "osv-scanner")]),
    "axes.minimalism.03": (3, "~3 lignes suppressibles relevées sur tout le diff.", [analysis]),
    "axes.business.01": (3, "Données de macOS lues telles quelles (symboles, catégories, versions), testées sur ce Mac.", [analysis, tests]),
    "axes.business.03": (2, "Format d'Alfred : numéros prouvés ou déduits et documentés.", [analysis]),
    "axes.traceability.01": (3, "Défauts trouvés reliés à leur preuve et à leur correction ; exigences reliées aux tests.", [analysis]),
    "axes.traceability.02": (3, "Toutes les exigences obligatoires de la spec 131 vérifiées, sauf SC-003 mesuré à l'essai.", [analysis]),
}
for check in data["axis_checks"]:
    check.pop("level", None); check.pop("rating_rationale", None)
    if check["axis"] == "llm_security":
        check.update(status="not_applicable", rationale="Aucun appel à un service LLM ajouté (IA d'Alfred 6 écartée).", evidence=[])
    elif check["id"] in checks:
        level, reason, evidence = checks[check["id"]]
        check.update(status="pass", rationale=reason, level=level, rating_rationale=reason + S, evidence=evidence)
    else:
        check.update(status="not_applicable", rationale="Sans objet pour ce diff : aucune sauvegarde, bascule ou restauration, ni ergonomie de parcours ou séparation construction/exécution touchée.", evidence=[]) if check["id"] in ("axes.reliability.01","axes.reliability.03","axes.reliability.04","axes.architecture.03","axes.architecture.02") else check.update(status="unknown", rationale="Non vérifié dans cet audit.", evidence=[])
data["findings"] = [
    fixed("REL-TEXTVIEW-CONSTRAINT", "Sources/RoadieDaemon/WorkflowTextPanel.swift", "WorkflowTextPanel.layout", "input-width-without-input", 117,
          "reliability", "Vue Texte sans champ de saisie : exception de mise en page puis plantage", "HIGH",
          "La largeur du champ de saisie est contrainte même quand il n'est pas dans la pile ; l'exception AppKit traverse Swift et corrompt l'état d'exécution (plantage à la minuterie suivante, 4 essais sur 4).",
          "Ne contraindre que les lignes présentes dans la pile.", "NSStackView(views: rows) unique ; ajouts conditionnels limités à ce panneau."),
    fixed("UX-BAR-SCROLL", "Sources/RoadieDaemon/TargetOverlayPresenter.swift", "TargetSearchDismissal.eventMask", "no-scroll-wheel", 861,
          "quality", "Barre sans défilement au trackpad", "MEDIUM",
          "Le tap de la barre n'écoute pas scrollWheel : la liste et la grille apps ne défilent pas.",
          "Écouter la molette en recherche et déplacer la sélection.", "Aucun autre tap de la barre ne gère de liste défilante."),
    fixed("UX-SEARCHFIELD-BEZEL", "Sources/RoadieDaemon/WorkflowTextPanel.swift", "WorkflowViewStyle.decorate", "search-field-without-bezel", 376,
          "quality", "Champ de recherche SF Symbols : loupe sur le texte", "LOW",
          "Le style retire le cadre natif, qui réserve la place de la loupe d'un NSSearchField ; reproduit hors écran.",
          "Garder le cadre natif des champs de recherche.", "decorate n'est appelé que sur deux champs, dont un seul de recherche.",
          (artifact("notes/recherche-symboles-avant.png"), artifact("notes/recherche-symboles-apres.png"))),
    fixed("UX-ALIAS-FEEDBACK", "Sources/RoadieDaemon/TargetModeRuntimeController.swift", "TargetModeRuntimeController.performFileAction", "alias-without-feedback", 1973,
          "quality", "Créer un alias sans retour visible", "LOW",
          "L'alias est créé sur disque mais rien ne le montre à l'utilisateur.",
          "Montrer les alias créés sélectionnés dans le Finder.", "Seul verbe de fichier sans effet visible ailleurs que sur disque."),
]
data["minimalism"] = "Potentiel minimalisme : ~3 lignes suppressibles à comportement constant (conformités CaseIterable réservées aux tests), mesuré sur tout le diff."
data["responsibility"] = "Diff relu en entier ; logique pure séparée et testée ; deux défauts trouvés et corrigés avant figement, quatre autres à l'essai réel puis corrigés ; pas de revue indépendante."
(session / "input.json").write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n")
print("ok")
