from pathlib import Path
from collections import Counter
import datetime
import hashlib
import json
import os
import re
import subprocess

ROOT = Path('/Users/moi/Nextcloud/10.Scripts/39.roadie')
OUT = ROOT / 'audits/2026-10-13/full-codebase-01'
PROTOCOL = Path('/Users/moi/Nextcloud/10.Scripts/00.Generic/audit-code-v14')
ENV = {**os.environ, 'PYTHONDONTWRITEBYTECODE': '1'}

def write_json(path, value):
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + '\n')

raw = {p.name: json.loads(p.read_text()) for p in sorted(OUT.glob('raw-*.json'))}
findings = []
deferred = []
for name, doc in raw.items():
    for original in doc['findings']:
        f = dict(original)
        f['source_artifact'] = str(OUT / name)
        f['source_id'] = f['id']
        if f['source_id'].startswith('DUP-'):
            f['category'] = 'duplication'
        if name == 'raw-security.json' and f['id'] == 'REL-305':
            deferred.append({'reason': 'Plausible, non reproduit. Piste conservée dans le sous-rapport, écartée des constats prouvés.', **f})
            continue
        if name == 'raw-commands.json' and f['id'] == 'PERF-102':
            continue  # Même calcul planGroup que PERF-DQ-002 : cause fusionnée.
        f['absolute_file'] = str(ROOT / f['file'])
        f['verification_status'] = f.get('verification_status', 'confirmé par lecture du code')
        f['status'] = 'open'
        f['remediation_applied'] = False
        if f['category'] == 'performance':
            f['measurement_status'] = 'Complexité établie par lecture; aucune latence ni allocation mesurée sur le bureau réel.'
            f['performance_validation'] = 'Comparer durée et allocations sur la même entrée, avant/après. Vérifier les résultats et leur ordre. Retirer le correctif ciblé si un comportement ou une mesure régresse.'
        findings.append(f)

def get(source, identifier):
    return next(f for f in findings if f['source_artifact'].endswith(source) and f['source_id'] == identifier)

group = get('raw-docs-quality.json', 'PERF-DQ-002')
group['description'] += ' La même implémentation apparaît dans WindowCommands.swift:1159. Les deux sites sont regroupés dans ce constat.'
group.setdefault('related_locations', []).append({'file': 'Sources/RoadieDaemon/WindowCommands.swift', 'line': 1159})
group['merged_source_findings'] = ['raw-commands.json:PERF-102']

crash = get('raw-commands.json', 'REL-101')
crash['title'] = 'Des arguments stage invalides peuvent arrêter le daemon'
crash['description'] += ' Un second chemin atteint une précondition fatale : stage create avec une chaîne vide construit StageID sans vérifier son contenu. Ces deux cas relèvent de la validation des arguments avant appel aux primitives.'
crash['exploitation_scenario'] += " Autre cas : roadie stage create ''. Aucun de ces appels destructifs n’a été exécuté sur le daemon."
crash['remediation'] += ' Refuser aussi les identifiants vides dans chaque entrée CLI qui construit StageID. Garder les préconditions internes comme garde-fous.'
crash['remediation_code'] += '\n\n// Dans le cas create du routeur, avant StageCommandService.create :\nguard let stageID = args.dropFirst().first, !stageID.isEmpty else {\n    err("roadie: stage create requires a nonempty stage id")\n    return 64\n}'
crash.setdefault('related_locations', []).extend([{'file': 'Sources/RoadieCore/Identifiers.swift', 'line': 33}, {'file': 'Sources/RoadieDaemon/CLICommandRouter.swift', 'line': 971}])

proof_cases = [('raw-models.json', 'REL-202'), ('raw-security.json', 'REL-301'), ('raw-snapshot.json', 'REL-SNAPSHOT-001')]
for source, identifier in proof_cases:
    f = get(source, identifier)
    f['verification_status'] = 'confirmé par lecture et sonde isolée sur le code compilé'
    f['runtime_proof'] = str(OUT / 'validation/probe-results.log')

counter = json.loads((OUT / 'counter-audit.json').read_text())
counter_by_file = {f['relative_file']: f for f in counter['findings']}
runtime_counter = json.loads((OUT / 'counter-runtime-perf.json').read_text())
for f in findings:
    if f['severity'] in ('HIGH', 'CRITICAL'):
        if f['file'] == 'Sources/RoadieDaemon/LayoutMaintainer.swift':
            f['counter_audit'] = runtime_counter['counter_audit']
            f['counter_audit_detail'] = runtime_counter['summary']
        else:
            verdict = counter_by_file[f['file']]
            f['counter_audit'] = verdict['verdict']
            f['counter_audit_detail'] = verdict['reason']
        assert f['counter_audit'] == 'CONFIRMED'
        assert f.get('remediation_code')

priority_files = ['Sources/RoadieDaemon/StageStore.swift', 'Sources/RoadieDaemon/StateAudit.swift', 'Sources/RoadieDaemon/TargetModeRuntimeController.swift', 'Sources/RoadieDaemon/DaemonSnapshot.swift', 'Sources/RoadieTiler/SpatialBSPLayoutStrategy.swift', 'Sources/RoadieDaemon/DropPreviewController.swift', 'Sources/RoadieDaemon/LayoutMaintainer.swift']
rank = {'CRITICAL': 0, 'HIGH': 1, 'MEDIUM': 2, 'LOW': 3}
findings.sort(key=lambda f: (rank[f['severity']], priority_files.index(f['file']) if f['file'] in priority_files else 99, f['category'], f['file'], f['line']))
counts = Counter()
prefix = {'reliability': 'REL', 'performance': 'PERF', 'quality': 'QUAL', 'tests': 'TEST', 'minimalism': 'MIN', 'duplication': 'DUP', 'observability': 'OBS', 'security': 'SEC'}
for f in findings:
    k = prefix[f['category']]
    counts[k] += 1
    f['id'] = f'{k}-{counts[k]:03d}'
    # Vérification déterministe des citations avant fingerprint.
    actual = (ROOT / f['file']).read_text()
    assert ' '.join(f['evidence'].split()) in ' '.join(actual.split()), (f['id'], 'preuve absente')
    assert 0 < f['line'] <= len(actual.splitlines())

with (OUT / 'cycle-1/aggregated-findings.pending.json').open('w') as handle:
    json.dump({'findings': findings}, handle, ensure_ascii=False)
encoded = subprocess.run(['python3', '-B', str(PROTOCOL / 'scripts/fingerprint.py'), '--batch'], input=json.dumps({'findings': findings}), text=True, capture_output=True, check=True, env=ENV)
findings = json.loads(encoded.stdout)['findings']
(OUT / 'cycle-1/aggregated-findings.pending.json').unlink()

baseline = ROOT / 'audits/baseline.json'
baseline_entries = json.loads(baseline.read_text()).get('entries', []) if baseline.exists() else []
assert not baseline_entries, 'Examiner la baseline avant de livrer'

weights = {'security': 3, 'supply_chain': 1, 'observability': 1, 'reliability': 2, 'tests': 1, 'performance': 2, 'complexity': 2, 'quality': 2, 'architecture': 1, 'ai_hygiene': 1, 'duplication': 1, 'minimalism': 1, 'ux': 1}
penalty = {'CRITICAL': 25, 'HIGH': 10, 'MEDIUM': 3, 'LOW': 1}
def domain(f):
    return 'complexity' if f['category'] == 'performance' and f.get('subcategory') == 'algorithmic_complexity' else f['category']
def grade(n):
    return next(g for threshold, g in [(90,'A'), (85,'A-'), (80,'B+'), (75,'B'), (60,'C'), (40,'D'), (0,'F')] if n >= threshold)
metrics = {}
for d in weights:
    fs = [f for f in findings if domain(f) == d]
    numeric = max(0, 100 - sum(penalty[f['severity']] for f in fs))
    metrics[d] = {'grade': grade(numeric), 'numeric': numeric, 'findings_count': len(fs), 'by_severity': dict(Counter(f['severity'] for f in fs))}
metrics['llm_security'] = {'grade': 'N/A', 'findings_count': 0}
global_numeric = sum(metrics[d]['numeric'] * w for d,w in weights.items()) / sum(weights.values())
global_grade = grade(global_numeric)

manifest = json.loads((OUT / 'manifest.json').read_text())
inventory = json.loads((OUT / 'read-inventory.json').read_text())
fully_read = set(inventory['fully_read'])
fully_read.update(['Sources/RoadieDaemon/RoadieScreenCoordinate.swift', 'Package.swift', 'scripts/measure-layout-reactivity', 'scripts/tests/fixtures/layout-reactivity.jsonl', 'scripts/tests/test_measure_layout_reactivity.py'])
inventory = {'fully_read': sorted(fully_read), 'production_unread': [], 'tests_review': '33 fichiers de tests lus intégralement; autres tests lus par scénarios et inventaire. Tous les tests Swift sauf un exécutés.'}
write_json(OUT / 'read-inventory.json', inventory)
manifest['production_source_coverage_percent'] = 100
manifest['tests_read_entirely'] = 33
manifest['hot_paths'] = ['Notification AX → TickScheduler → LayoutMaintainer → writes AX', 'CLI → socket Unix → MainActor → mutations persistantes', 'snapshot/reconcile → plan/invariant géométrique', 'Hyper+F → scan AX concurrent → modèle et overlay MainActor', 'Activation cible → focus AX → injection CGEvent', 'Rail et glisser → sélection écran/stage → géométrie', 'Modification config → validation/rechargement', 'Changement écran → parking/restauration', 'Macros → capture/replay', 'Journaux → rotation/abonnement']
manifest['threat_model'] = {'assets': ['fenêtres/focus/clavier/souris utilisateur', 'associations persistantes et signets', 'configuration', 'titres de fenêtres et journaux'], 'attackers': ['processus local du même utilisateur', 'commande shell erronée', 'application Accessibility lente ou incohérente'], 'surfaces': ['socket Unix privé', 'arguments CLI', 'TOML/JSON sur disque', 'réponses AX', 'événements Carbon/CGEvent'], 'non_applicable': ['service HTTP public', 'authentification web', 'paiements', 'base SQL', 'service LLM embarqué']}
manifest['test_results'] = {'swift_build': 'PASS 29.62s', 'swift_tests_selected': 880, 'swift_tests_total_expected': 881, 'swift_initial_passed': 879, 'swift_initial_failed': 1, 'swift_rechecked_passed': 1, 'swift_final_unresolved_failures': 0, 'swift_skipped': ['CLICommandRouterTests.socketRoundTripRunsRouterAndRefusesOthers : socket écrit sous /tmp en dur, hors dossier autorisé'], 'python_measure_tests': '7 PASS', 'pure_probes': '5 scénarios exécutés; mauvais types bool et chaîne = deux variantes'}
manifest['warnings'].extend(['Premier lancement SwiftPM bloqué par sandbox-exec imbriqué; compilation réussie avec --disable-sandbox SwiftPM, sandbox de session conservé.', 'Premier test exemple échoué car examples/ manquait dans la copie; copie des exemples originaux puis unique test réexécuté avec succès.', 'Les constats HIGH algorithmiques suivent Article XVIII. Ils ne sont pas des mesures de latence.', 'Lecture détaillée de toutes les sources de production; revue des tests et docs ciblée, pas lecture ligne à ligne de tous les artefacts historiques.'])
write_json(OUT / 'manifest.json', manifest)

now = datetime.datetime.now(datetime.timezone.utc)
start = datetime.datetime.fromisoformat(manifest['start_timestamp'])
warnings = list(manifest['warnings']) + ['Aucun test UI réel, aucun clic injecté, aucun hotkey Carbon enregistré, aucun branchement/débranchement écran.', 'Pas de Thread Sanitizer, Address Sanitizer, fuzzing, profil CPU/mémoire, mutation testing ou couverture de branches instrumentée.', 'Aucun scan CVE/SBOM de TOMLKit, aucune revue complète du code de dépendances externes.', 'Les corrections proposées ne sont pas appliquées ni compilées comme corrections.', 'Le test socket et les tests de cycle de vie Python ne sont pas exécutés.', 'La piste annulation tardive du socket reste plausible et hors des 50 constats; détail raw-security.json REL-305.']
warnings.extend(f"contre-audit {f['id']}: CONFIRME" for f in findings if f['severity'] == 'HIGH')
positives = []
for doc in raw.values():
    positives.extend(doc.get('positive_findings', []))
summary = {s.lower(): sum(f['severity'] == s for f in findings) for s in rank}
summary.update(total=len(findings), by_category=dict(Counter(f['category'] for f in findings)))
modules = ['00','01','02','03','04','05','06','07','08','10','11','12']
aggregated = {'$schema': 'audit-code-v14/aggregated-findings', 'meta': {'version':'v14.0','timestamp':now.isoformat(),'start_timestamp':start.isoformat(),'end_timestamp':now.isoformat(),'duration_ms':int((now-start).total_seconds()*1000),'audit_scope':str(ROOT),'audit_mode':'readonly','audit_grid':'all','modules_actifs':modules,'score_global':global_grade,'score_numeric':round(global_numeric,2),'release_blocked':True,'scores':{d:m['grade'] for d,m in metrics.items()},'repository':manifest}, 'execution_metrics': {'files_scanned':manifest['files_count'],'files_total':manifest['files_count'],'production_sources_read_entirely':96,'lines_analyzed':38217,'coverage_estimate_percent':100,'coverage_definition':'Toutes les sources de production ont été lues. Les autres fichiers ont été inventoriés et contrôlés par risques; revue des tests partielle explicitée dans read-inventory.json. Ce pourcentage n’est pas une couverture de tests.','tools_used':['rg','git read-only','swift build','swift test','python3','Swift pure probes','manual review','independent counter-audit','fingerprint.py','validate_session.py'],'sampling_method':None,'phases_completed':modules,'phases_skipped':['09: corrections interdites'],'warnings':warnings}, 'summary':summary,'findings':findings,'suppressed':[],'positive_findings':positives,'supply_chain':{'direct_dependencies':1,'sbom_ready':False,'vulnerable_deps_count':None,'note':'TOMLKit 0.6.0 fixé dans Package.resolved; vulnérabilités non recherchées par scanner.'},'duplicated_code':{'jscpd_percentage':None,'note':'Analyse manuelle; aucun pourcentage global calculé.'},'ai_hygiene':{'suspected_ai_ratio_percent':None,'note':'Aucune origine IA déduite du style.'},'llm_governance':{'applicable':False},'roadmap':{'immediate':[f['id'] for f in findings if f['severity']=='HIGH'],'short_term':[f['id'] for f in findings if f['severity']=='MEDIUM'],'medium_term':[f['id'] for f in findings if f['severity']=='LOW'],'long_term':[]}}
write_json(OUT / 'cycle-1/aggregated-findings.json', aggregated)
module_for = {'security':'03','supply_chain':'03','observability':'03','reliability':'06','tests':'06','quality':'05','architecture':'05','ai_hygiene':'05','performance':'08','complexity':'04','duplication':'07','minimalism':'12','ux':'08'}
for number, label in [('03','securite'),('04','complexite'),('05','qualite'),('06','tests'),('07','duplication'),('08','performance'),('12','minimalisme')]:
    write_json(OUT / f'cycle-1/findings_{label}.json', {'module':number,'findings':[f for f in findings if module_for[domain(f)] == number]})
write_json(OUT / 'deferred-and-merged.json', {'deferred':deferred,'merged':[{'source':'raw-commands.json:PERF-102','into':group['id'],'reason':'Même planGroup et même correction que le site DropPreviewController.'}]})

doc = []
def add(text=''):
    doc.append(text)
add('# Audit de code v14 — Roadie — dépôt complet')
add(f'\nDate : 2026-10-13. Commit vérifié : acc10e13c41026ce444fe38933840b1ea9e2c976. Branche : main. Mode : readonly. Un cycle.\n\nDépôt : {ROOT}\n\nRapport : {OUT}/scoring.md')
add(f'\n## Résumé exécutif\n\n**Note globale v14 : {global_grade} ({global_numeric:.2f}/100).** Cette note est la moyenne pondérée imposée par le protocole. Le domaine fiabilité vaut **{metrics["reliability"]["grade"]} ({metrics["reliability"]["numeric"]}/100)**. **La livraison reste bloquée selon la règle v14**, car des constats HIGH subsistent. Une bonne moyenne ne neutralise pas ces défauts.\n\n{summary["total"]} constats : {summary["critical"]} CRITICAL, {summary["high"]} HIGH, {summary["medium"]} MEDIUM, {summary["low"]} LOW. Aucun correctif appliqué.')
add('\nPérimètre : 96 fichiers Swift de production, 38 217 lignes, toutes les cibles et les scripts. Les 96 sources ont été lues entièrement, réparties entre les relectures. Les 71 fichiers de tests ont été inventoriés; 33 ont été lus entièrement, les autres par scénarios et recherches. La documentation courante a été comparée au code. Les anciennes specs ont servi de contexte ciblé. Le taux de 100 % porte sur les sources de production, pas sur les branches testées ni sur une lecture intégrale de chaque document historique.')
add('\nBuild réussi. 880 tests Swift distincts exécutés sur 881. Le lancement initial donne 879 succès et un échec de copie de fixture; le test concerné passe après copie de l’exemple original. Aucun échec produit ne reste observé. Un test socket est exclu, car son chemin /tmp est codé en dur. Sept tests Python du script de mesure passent. Cinq sondes pures confirment des défauts sans modifier les fenêtres réelles.')
add('\n| Domaine | Note | Score | HIGH | MEDIUM | LOW |\n|---|---:|---:|---:|---:|---:|')
for d,m in metrics.items():
    c=m.get('by_severity',{})
    add(f'| {d} | {m["grade"]} | {m.get("numeric","—")} | {c.get("HIGH",0)} | {c.get("MEDIUM",0)} | {c.get("LOW",0)} |')
add('\nCalcul : 100 moins 25/10/3/1 points par constat CRITICAL/HIGH/MEDIUM/LOW, plancher zéro. Pondérations : sécurité 3; fiabilité, performance, complexité et qualité 2; autres domaines 1. Les constats algorithmiques alimentent le domaine complexité une seule fois. L’absence de constat ne prouve pas une absence universelle de défaut. Le domaine LLM Security ne s’applique pas à ce programme.')
add('\n## Les cinq corrections prioritaires\n\n1. Valider les arguments des commandes avant les primitives : position Int.min et identifiant de stage vide. Ajouter des tests du routeur complet.\n2. Préserver les associations lors de state heal tant que la fermeture n’est pas prouvée. Tester minimisation et changement de Space macOS.\n3. Activer exactement la cible affichée. Arrêter un clic si le focus échoue ou si la fenêtre a disparu.\n4. Fiabiliser les transitions multi-écrans : restaurer par écran et bureau, respecter --no-follow, utiliser l’écran de la fenêtre visée.\n5. Supprimer les recherches répétées des chemins interactifs. Commencer par le contrôle des trous, le plan BSP et les aperçus de groupe. Mesurer ensuite sur les mêmes entrées.')
add('\n## Tendance\n\nDernier audit complet trouvé : '+str(ROOT/'audits/2026-05-09/session-2026-05-09-all-04/scoring.md')+'. Il annonçait A sous v13, sur environ 14 000 lignes et 174 tests. Le présent audit utilise v14, 38 217 lignes et 881 tests inventoriés. Les deux notes ne mesurent pas une évolution à périmètre constant. Aucun delta « corrigé/nouveau » fiable n’est calculable sans fingerprints comparables. Les audits 018 et 020 couvraient seulement leurs sessions. La baseline '+str(baseline)+' est absente : aucune suppression de constat.')
add('\n## Session 021 : concurrence, fils d’exécution et fonctions système\n\nLe stockage WindowScanBatch est alloué une fois. Chaque itération de concurrentPerform écrit dans une case distincte. La lecture finale attend la fin du groupe. Aucune course mémoire n’a été démontrée sur ce stockage. Les retours de scan arrivent sur DispatchQueue.main. Les objets de présentation sont isolés par MainActor. Les callbacks utilisent des références faibles et refusent les ajouts après fermeture. Cela ne constitue pas une certification Thread Sanitizer.\n\nLa recherche conserve bien la cible sélectionnée. Le défaut de réinterprétation de lettre touche le mode interactif classique. La recherche reste concernée par la fenêtre devenue obsolète avant un clic. Le délai d’attente de focus ne renvoie pas de réussite et le clic peut partir après son expiration. Les tests portent surtout sur les fonctions pures, pas sur cette frontière avec le système.\n\nLes appels AX exécutés en arrière-plan ne sont pas déclarés fautifs par leur seul emplacement. Aucun contrat complet de sûreté multi-thread des applications tierces n’a été vérifié. Les délais de scan n’incluent pas toute la préparation des index AX; aucune latence de bout en bout n’a été mesurée. Les badges ont une recherche de positions quadratique, mais le modèle limite les résultats à 500 : profil à faire avant de chiffrer le coût.\n\nCarbon est appelé depuis un objet MainActor. La résolution des touches est testée. Aucun essai réel de conflit de raccourci, de disposition clavier ou de livraison du callback n’a été fait. Aucun CGEvent n’a été injecté pendant cet audit. Les contrats API consultés servent de référence limitée : [AXUIElementSetMessagingTimeout](https://developer.apple.com/documentation/applicationservices/1459345-axuielementsetmessagingtimeout) et [CGEvent](https://developer.apple.com/documentation/coregraphics/cgevent).')
add('\n## Constats classés du plus grave au moins grave\n\n« Confirmé » signifie prouvé par le chemin de code. Les cinq sondes sont signalées séparément. Cela ne signifie pas que le scénario a été rejoué sur le bureau réel. Les corrections sont proposées, sans application ni validation de compilation de ces corrections.\n\n| ID | Sévérité | Fichier et ligne | Problème |\n|---|---|---|---|')
for f in findings:
    add(f'| {f["id"]} | {f["severity"]} | {f["absolute_file"]}:{f["line"]} | {f["title"]} |')
add('\n## Détail des constats')
for f in findings:
    add(f'\n### {f["id"]} — {f["severity"]} — {f["title"]}\n\nFichier : {f["absolute_file"]}:{f["line"]}\n\nStatut : {f["verification_status"]}. Correction : non appliquée.\n\n{f["description"]}\n\nScénario : {f.get("exploitation_scenario", f.get("impact"))}\n\nConséquence : {f["impact"]}\n\nPreuve :\n\n```\n{f["evidence"]}\n```\n\nCorrection proposée : {f["remediation"]}\n\nVérification proposée : {f["verification"]}\n\nEffort : {f["effort"]}. Risque de régression : {f["regression_risk"]}.')
    if f.get('counter_audit_detail'):
        add('\nContre-audit indépendant : CONFIRMED. '+f['counter_audit_detail'])
    if f.get('runtime_proof'):
        add('\nPreuve exécutée : '+f['runtime_proof'])
    if f.get('performance_validation'):
        add('\nMesure et retour arrière : '+f['performance_validation']+' '+f['measurement_status'])
    if f.get('remediation_code'):
        add('\nProposition de code, non appliquée :\n\n```swift\n'+f['remediation_code']+'\n```')
    for location in f.get('related_locations', []):
        if isinstance(location,dict) and location.get('file'):
            loc = Path(location['file'])
            add('\nAutre site : '+str(loc if loc.is_absolute() else ROOT/loc)+':'+str(location.get('line','—')))

add('\n## Complexité algorithmique — Article XVIII\n\nContrôles effectués : boucles imbriquées, recherches linéaires dans les boucles, appels AX répétés, tris, concaténations, I/O, récursions et copies. Les parcours quadratiques/cubiques signalés ont des scénarios atteignables et un correctif ciblé. Le coût de réparation de voisinage est conditionnel à un refus de taille; il ne survient pas à chaque tick. Les usages de Set/Dictionary et le groupement par PID réduisent déjà plusieurs coûts. Aucun gain de latence chiffré n’est promis. Les annotations des fonctions publiques ont été examinées par chemins importants, sans inventaire automatisé exhaustif. Aucune base SQL ni API réseau par ligne n’existe dans ce périmètre.')
add('\n## Minimalisme & Frugalité\n\n**Potentiel minimalisme : ~300 lignes suppressibles à comportement constant.**\n\nEstimation statique dédoublonnée : environ 28 lignes de validations inatteignables, 110 lignes de helpers/menus du rail, 60 lignes des pipelines de déplacement de bureau, 56 lignes des encodeurs JSON répétés et 45 lignes de nettoyage/émission d’événements de cibles. Total estimé : 299, arrondi à 300. Il ne s’agit pas d’un diff implémenté.\n\nChecklist appliquée : helpers sans règle propre, états dérivés, wrappers, abstractions, défenses inutiles, dépendances et fonctions sans besoin prouvé. Les protocoles de layout ont quatre implémentations. Les abstractions AX servent les tests et les garde-fous. Les aliases persistés et les migrations assurent la compatibilité. Ils ne sont pas comptés comme suppressibles. Les heuristiques Electron/CEF ont des cas concrets et des tests. Aucun retrait de fonctionnalité n’est proposé sans besoin validé.')
add('\n## Vertus LLM & Responsabilité Future\n\nLa séparation Core/AX/Stages/Tiler et les tests des invariants réduisent la charge future. La charge augmente toutefois dans les contrôleurs longs, les pipelines dupliqués et les résultats de succès qui ne représentent pas l’effet réel. Les tests des seuls flags changed, noms de requêtes et chaînes d’indicateurs laissent passer des défauts visibles.\n\nLe volume des moteurs est en partie justifié par les contraintes macOS, le plein écran, les arrondis et les fenêtres qui refusent de changer de taille. Il n’est pas intégralement justifié : les suppressions estimées et les tests peu discriminants sont détaillés ci-dessus. Les abstractions signalées servent généralement des frontières réelles. Une suppression massive ne serait pas adaptée.\n\nLes invariants sont expliqués dans les ADR et les tests. Les contre-exemples montrent où le mainteneur doit compléter le contrat. Aucun jugement sur l’origine IA du code, sur la compréhension d’un auteur ou sur une absence de relecture humaine n’est tiré du style. Aucune intégration LLM applicative n’a été trouvée. L’historique de génération n’a pas fait l’objet d’une preuve indépendante.')
add('\n## Points positifs vérifiés\n\n- Socket créé en 0600, taille de requête limitée et commandes à flux refusées.\n- État JSON écrit atomiquement; mutations principales sous verrou; fichier corrompu conservé. La remontée du succès reste à corriger.\n- Délais AX et quarantaine par PID. Écritures groupées par application.\n- Horloge simulée dans les tests du scheduler; couverture de la coalescence et des suspensions.\n- Tests de projection BSP, tailles minimales et limites d’arrondi.\n- Bonne couverture des règles pures de recherche et des collisions CFEqual/CFHash.\n- Reprise des fenêtres : appels AX hors verrou et revérification du propriétaire avant validation.')
add('\n## Sécurité et dépendances\n\nAucune injection shell ni exposition réseau non autorisée confirmée dans les chemins lus. Les processus sont lancés avec arguments séparés aux sites examinés. La surface prioritaire est locale : le processus du même utilisateur, les arguments erronés et les actions système déjà autorisées à Roadie. Les protections de socket ne neutralisent pas un crash produit par une commande acceptée. Les titres de fenêtres et journaux ont été inclus dans les recherches de données sensibles. Aucun secret confirmé dans les sources et scripts analysés.\n\nTOMLKit 0.6.0 est la seule dépendance SwiftPM directe, fixée par révision dans '+str(ROOT/'Package.resolved')+'. Aucun scan de vulnérabilités des dépendances n’a été effectué. Les cases OWASP web, paiement et LLM sont sans objet pour ce binaire local. Les contrôles de permissions, fichiers, processus et état persistent dans le périmètre. Aucun pourcentage JSCPD n’est annoncé : duplication étudiée manuellement.')
add('\n## Tests, preuves et limites\n\nLes commandes et leurs sorties restent dans '+str(OUT/'validation')+'. Le code a été copié sous ce dossier avec les manifests, les fixtures et la dépendance déjà présente. Les caches et TMPDIR ont été redirigés dans ce même dossier. HOME n’a pas été modifié. Le répertoire de build du dépôt n’a pas servi de destination d’écriture.\n\nRésultats :\n\n- swift build : succès, 29,62 s selon SwiftPM.\n- swift test : 880 tests sélectionnés, premier passage 879 succès + 1 échec dû à l’exemple absent de la copie. Reprise ciblée : 1 succès. Aucun échec produit restant.\n- Test socket exclu : CLICommandRouterTests.socketRoundTripRunsRouterAndRefusesOthers. Son chemin court est codé en dur sous /tmp, hors périmètre d’écriture autorisé.\n- Python measure-layout-reactivity : 7 tests réussis. Les tests Python de cycle de vie ne sont pas exécutés.\n- Sondes compilées : mauvais type numérique accepté avec valeur par défaut; cadre hors écran avec gap excessif; écran gauche pris pour une zone cachée; succès de mutation malgré fichier corrompu; config reload sans changement du service partagé.\n\nJournaux :\n\n'+str(OUT/'validation/build-no-nested-sandbox.log')+'\n\n'+str(OUT/'validation/test.log')+'\n\n'+str(OUT/'validation/test-example-recheck.log')+'\n\n'+str(OUT/'validation/probe-results.log')+'\n\n'+str(OUT/'validation/test-measure.log'))
add('\nNon vérifié : interaction réelle avec Firefox/Electron/CEF; clics CGEvent; enregistrement et conflit Carbon; autorisations TCC; changements physiques d’écran; charge et mémoire; analyseurs de courses/mémoire; fuzzing; toutes les branches de tests; CVE des dépendances; exactitude de chaque ancienne spec. Les correctifs proposés sont non exécutés. La course de suppression tardive du socket reste plausible, écartée du scoring et conservée dans '+str(OUT/'deferred-and-merged.json')+'.')
add('\n## Traçabilité et conformité\n\nAucun code, test, document ou fichier de configuration du dépôt n’a été modifié. Aucune branche, aucun commit, aucun push. Aucun processus existant arrêté, tué ou relancé. Aucun make install/restart. Les fichiers générés sont uniquement sous '+str(OUT)+'. Le pointeur '+str(ROOT/'audits/latest')+' reste inchangé pour respecter cette contrainte.\n\nLes identifiants de constats des sous-rapports pouvaient entrer en collision. Ils ont été renumérotés ici. source_artifact/source_id préservent leur origine dans le JSON. Les fingerprints sont calculés par le script canonique. Les propositions planGroup identiques ont été fusionnées. La baseline absente n’a pas été créée.\n\nArtefacts principaux :\n\n'+str(OUT/'grade.json')+'\n\n'+str(OUT/'cycle-1/aggregated-findings.json')+'\n\n'+str(OUT/'counter-audit.json')+'\n\n'+str(OUT/'counter-runtime-perf.json')+'\n\n'+str(OUT/'read-inventory.json'))
human_report = '\n'.join(doc) + '\n'
# Les citations de code restent exactes. Les chemins dans la prose sont absolus.
source_by_name = {p.name: str(p) for p in (ROOT/'Sources').rglob('*.swift')}
source_by_name.update({p.name: str(p) for p in (ROOT/'Tests').rglob('*.swift')})
chunks = human_report.split('```')
for i in range(0, len(chunks), 2):
    for basename, absolute in source_by_name.items():
        chunks[i] = re.sub(r'(?<![\w/])'+re.escape(basename)+r'\b', absolute, chunks[i])
human_report = '```'.join(chunks)
(OUT/'scoring.md').write_text(human_report)

write_json(OUT/'grade.json', {'grade':global_grade,'date':'2026-10-13','spec':'all','scope':'Tout le dépôt Roadie au commit acc10e1 : sources, scripts, tests et documentation; audit readonly v14','coverage_percent':100,'coverage_definition':'96/96 fichiers Swift de production lus intégralement. Tests et docs revus par risque, avec limites explicites dans scoring.md. Pas une mesure de couverture des tests.','justification':f'Moyenne pondérée canonique {global_numeric:.2f}/100. Fiabilité {metrics["reliability"]["grade"]}; {summary["high"]} HIGH non corrigés : release_blocked=true.','release_blocked':True,'metrics':metrics})
write_json(OUT/'validation/results.json',manifest['test_results'])
(OUT/'01_Decouverte.md').write_text('# Découverte du dépôt\n\nPérimètre : '+str(ROOT)+'\n\nMode S, lecture complète de 96 fichiers de production Swift (38 217 lignes). Inventaire global : '+str(manifest['files_count'])+' fichiers source/scripts/tests. Swift 6, SwiftPM, macOS 14+, AppKit/SwiftUI, AX et Carbon. JSON persistant, aucun serveur web ni service LLM intégré. Aucun pipeline CI du dépôt détecté.\n\n## Chemins fréquents\n\n'+'\n'.join('- '+x for x in manifest['hot_paths'])+'\n\n## Modèle de menace\n\n'+json.dumps(manifest['threat_model'],ensure_ascii=False,indent=2)+'\n\n## Vérification croisée\n\nTous les HIGH ont été soumis à un lecteur distinct en posture de réfutation. Les preuves sont dans '+str(OUT/'counter-audit.json')+' et '+str(OUT/'counter-runtime-perf.json')+'. Les sources associées ont été relues intégralement.\n\nMémoire projet absente dans /Users/moi/.Codex/projects. Constitution globale et pont projet lus. Les specs 018/020/021 et les ADR pertinents servent de contexte, sans restreindre le périmètre à la dernière session.\n')
print(json.dumps({'grade':global_grade,'numeric':round(global_numeric,2),'summary':summary,'minimalism_estimate':299},ensure_ascii=False))
