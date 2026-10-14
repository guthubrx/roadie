import collections
import datetime
import hashlib
import json
import pathlib
import subprocess

S = pathlib.Path(__file__).resolve().parent
R = S.parents[2]
P = pathlib.Path('/Users/moi/Nextcloud/10.Scripts/00.Generic/audit-code-v14')
def read(p): return json.loads(p.read_text())
def write(name, value): (S/name).write_text(json.dumps(value, ensure_ascii=False, indent=2)+'\n')
def absolute(p): return str(pathlib.Path(p) if p.startswith('/') else R/p)
def path_of(x): return x if isinstance(x, str) else x.get('file', x.get('path', ''))
def normalize_paths(x):
    if isinstance(x,list): return [normalize_paths(y) for y in x]
    if isinstance(x,dict): return {k:(absolute(v) if k=='file' and isinstance(v,str) else normalize_paths(v)) for k,v in x.items()}
    return x
old = read(R/'audits/2026-10-13/full-codebase-01/cycle-1/aggregated-findings.json')
previous = read(R/'audits/2026-10-13/full-codebase-02/cycle-1/aggregated-findings.json')
previous_grade = read(R/'audits/2026-10-13/full-codebase-02/grade.json')
inventory = read(S/'source-inventory.json')
manifest = read(S/'manifest.json')
decisions = read(S/'review-decisions.json')
raw_paths = sorted(S.glob('raw-*.json'), key=lambda p: ('completion' in p.name, p.name))
statuses, findings, full, partial, positives, warnings = {}, [], set(), set(), [], []
for path in raw_paths:
    data = read(path)
    for x in data.get('original_statuses', []): statuses[x['id']] = x
    for x in data.get('files_read_full', []): full.add(absolute(path_of(x)))
    for x in data.get('files_read_partial', []): partial.add(absolute(path_of(x)))
    positives += normalize_paths(data.get('positive_findings', []))
    warnings += data.get('warnings', [])
    for source in data.get('findings', []):
        key = path.name+':'+source['id']
        if key in decisions['excluded']: continue
        f = dict(source)
        f.update(decisions.get('overrides', {}).get(key, {}))
        f['source_id'] = source['id']
        f['source_artifact'] = str(path)
        f['id'] = decisions['id_map'][key]
        f['absolute_file'] = absolute(f['file'])
        f['file'] = str(pathlib.Path(f['absolute_file']).relative_to(R))
        f['category'] = {'simplification':'minimalism'}.get(f['category'], f['category'])
        f['regression_risk'] = {'NONE':'LOW'}.get(f.get('regression_risk','LOW'),f.get('regression_risk','LOW'))
        f.setdefault('status', 'open')
        f.setdefault('path_type','hot')
        f.setdefault('effort','S')
        f.setdefault('verification_status','confirmé par lecture ; scénario système non exécuté')
        f.setdefault('exploitation_scenario',f.get('scenario','Sans objet'))
        f['status']='open'
        f['origin'] = 'résiduel' if f['id'] in {x['id'] for x in old['findings']} else 'nouveau pour les audits 01/02 ; date d’introduction non déduite'
        source_text = pathlib.Path(f['absolute_file']).read_text()
        assert f['evidence'] in source_text, (f['id'],'preuve non littérale')
        assert 0 < f['line'] <= len(source_text.splitlines()), f['id']
        assert len(f['title']) < 100, f['id']
        findings.append(f)
statuses.update(decisions.get('status_overrides', {}))
initial = {f['id']: f for f in old['findings']}
tracked = list(old['findings']) + [f for f in previous['findings'] if f['id'] not in initial]
assert len(tracked)==65
assert {x['id'] for x in tracked} <= statuses.keys(), {x['id'] for x in tracked}-statuses.keys()
assert len({f['id'] for f in findings})==len(findings)
for f in findings:
    if f['severity'] in ('HIGH','CRITICAL'):
        verdict=decisions['counter_audits'][f['id']]
        assert verdict['verdict']=='CONFIRMED'
        f['counter_audit']='CONFIRMED'
        f['counter_audit_artifact']=verdict['artifact']
        assert f.get('remediation_code')
findings = json.loads(subprocess.run(['python3',str(P/'scripts/fingerprint.py'),'--batch'],input=json.dumps({'findings':findings}),text=True,capture_output=True,check=True).stdout)['findings']
rank={'CRITICAL':0,'HIGH':1,'MEDIUM':2,'LOW':3}
findings.sort(key=lambda f:(rank[f['severity']],f['id']))
weights={'security':3,'supply_chain':1,'observability':1,'reliability':2,'tests':1,'performance':2,'complexity':2,'quality':2,'architecture':1,'ai_hygiene':1,'duplication':1,'minimalism':1,'ux':1}
def domain(f): return 'complexity' if f.get('subcategory')=='algorithmic_complexity' else f['category']
def grade(n): return next(g for t,g in [(90,'A'),(85,'A-'),(80,'B+'),(75,'B'),(60,'C'),(40,'D'),(0,'F')] if n>=t)
metrics={}
for dom in weights:
    fs=[f for f in findings if domain(f)==dom]
    numeric=max(0,100-sum({'CRITICAL':25,'HIGH':10,'MEDIUM':3,'LOW':1}[f['severity']] for f in fs))
    metrics[dom]={'grade':grade(numeric),'numeric':numeric,'findings_count':len(fs),'by_severity':dict(collections.Counter(f['severity'] for f in fs))}
metrics['llm_security']={'grade':'N/A','findings_count':0}
score=round(sum(weights[k]*metrics[k]['numeric'] for k in weights)/sum(weights.values()),2)
counts=collections.Counter(f['severity'].lower() for f in findings)
blocked=bool(counts['high'] or counts['critical'])
comparisons=[]
for f in tracked:
    x=dict(statuses[f['id']])
    if f['id']=='PERF-001': x['reason']=x['reason'].replace('RUNTIME-NEW-001','PERF-011')
    if f['id']=='PERF-008': x['reason']=x['reason'].replace('Config.swift:154','BSPLayoutStrategy.swift:154')
    if f['id']=='REL-021': x['reason']=x['reason'].replace(' Le statut résolu du premier raw-commands doit être remplacé.','')
    x.update(title=f['title'],original_severity=f['severity'],original_fingerprint=f['fingerprint'],source_audit='01' if f['id'] in initial else '02')
    for ev in x.get('evidence',[]): ev['file']=absolute(ev['file'])
    x['active_finding_id']=f['id'] if x['status']!='résolu' else None
    comparisons.append(x)
comparison={'original_findings':comparisons[:50],'audit02_new_findings':comparisons[50:],'all_findings':comparisons,'summary':dict(collections.Counter(x['status'] for x in comparisons)),'original_summary':dict(collections.Counter(x['status'] for x in comparisons[:50])),'audit02_new_summary':dict(collections.Counter(x['status'] for x in comparisons[50:])),'baseline_score':83.16,'previous_score':93.21,'current_score':score,'method':'Lecture actuelle et suivi des scénarios, même si les empreintes changent. Nouveaux sites et causes distingués des anciens.','new_finding_ids':[f['id'] for f in findings if f['id'] not in {x['id'] for x in tracked}]}
write('comparison.json',comparison)
production={str(R/p) for p in inventory['production']}
missing=production-full
assert not missing, ('lecture intégrale manquante',sorted(missing))
coverage=100.0*len(full&production)/len(production)
write('read-inventory.json',{'definition':'Couverture de lecture des fichiers Swift de production. Tests, scripts, docs et specs lus selon les risques; ce taux ne mesure ni les tests instrumentés ni toutes les lignes du dépôt.','production_count':len(production),'production_read_full':len(full&production),'full':sorted(full),'partial_only':sorted(partial-full)})
limits=read(S/'validation/results.json')['limitations']
now=datetime.datetime.now(datetime.timezone.utc);start=datetime.datetime.fromisoformat(read(S/'started.json')['start']);duration=int((now-start).total_seconds()*1000)
meta={'version':'v14.0','timestamp':now.isoformat(),'start_timestamp':start.isoformat(),'end_timestamp':now.isoformat(),'duration_ms':duration,'audit_scope':str(R),'audit_mode':'readonly','audit_grid':'all','modules_actifs':manifest['modules_actifs'],'score_global':grade(score),'score_numeric':score,'release_blocked':blocked,'scores':{k:v['grade'] for k,v in metrics.items()},'repository':manifest['repo'],'commit':manifest['audit_meta']['head']}
aggregate={'$schema':'audit-code-v14/aggregated-findings','meta':meta,'execution_metrics':{'files_scanned':len(production),'files_total':len(production),'lines_analyzed':sum(len(pathlib.Path(p).read_text().splitlines()) for p in production),'tools_used':['rg','git-readonly','Swift compiler','Swift Testing','manual-full-read','independent counter-review','fingerprint.py','validate_session.py'],'coverage_estimate_percent':coverage,'sampling_method':None,'phases_completed':['00','01','02','03','04','05','06','07','08','10','11','12'],'phases_skipped':['09 (readonly)'],'warnings':limits+[f'contre-audit {k}: CONFIRME ({v["artifact"]})' for k,v in decisions['counter_audits'].items()]},'summary':{**{s:counts[s] for s in ['critical','high','medium','low']},'info':0,'total':len(findings),'by_category':dict(collections.Counter(f['category'] for f in findings))},'supply_chain':{'slsa_level':None,'slsa_target':2,'sbom_ready':None,'vulnerable_deps_count':None,'license_issues_count':None,'note':'TOMLKit verrouillée ; absence de scan CVE externe.'},'duplicated_code':{'jscpd_percentage':None,'duplicated_lines':None,'max_block_lines':None,'total_occurrences':None,'critical_blocks':[],'method':'Lecture manuelle ; pas de taux inventé.'},'ai_hygiene':{'suspected_ai_ratio_percent':None},'llm_governance':{'applicable':False},'slos':manifest['slos'],'findings':findings,'suppressed':[],'positive_findings':positives,'roadmap':{'immediate':[f['id'] for f in findings if f['severity'] in ('HIGH','CRITICAL')],'short_term':[f['id'] for f in findings if f['severity']=='MEDIUM'],'medium_term':[],'long_term':[f['id'] for f in findings if f['severity']=='LOW']}}
write('cycle-1/aggregated-findings.json',aggregate)
for name,module,domains in [('securite','03',{'security','supply_chain','observability'}),('complexite','04',{'complexity'}),('qualite','05',{'quality','architecture','ai_hygiene'}),('tests','06',{'tests','reliability'}),('duplication','07',{'duplication'}),('performance','08',{'performance','ux'}),('minimalisme','12',{'minimalism'})]:
    write(f'cycle-1/findings_{name}.json',{'module':module,'findings':[f for f in findings if domain(f) in domains]})
md=['# Audit Roadie v14 — troisième audit complet','',f'Racine : {R}',f'Branche : 022-audit-remediation. Commit : {meta["commit"]}. 46 commits au-dessus de main.',f'Mode readonly ; un cycle ; date 2026-10-13 ; durée {duration/60000:.1f} minutes.',f'**Note : {grade(score)} — {score:.2f}/100. Livraison bloquée : {"OUI" if blocked else "NON"}.**','', '## Résumé exécutif','',f'{len(findings)} constats actifs : {counts["high"]} HIGH, {counts["medium"]} MEDIUM, {counts["low"]} LOW ; aucun CRITICAL.' if not counts['critical'] else str(counts),f'Comparaison des 65 constats : {comparison["summary"]}. Origine (50) : {comparison["original_summary"]}. Nouveaux audit02 (15) : {comparison["audit02_new_summary"]}.','La moyenne ne lève pas le blocage des HIGH. Les nouveaux constats étaient absents des deux rapports précédents ; cela ne prouve pas une régression du quatrième tour.','', '## Tendance','', '| Domaine | Audit02 | Actuel | Écart |','|---|---:|---:|---:|',f'| Global | A 93,21 | {grade(score)} {score:.2f} | {score-93.21:+.2f} |']
for k,v in metrics.items():
    before=previous_grade['metrics'].get(k,{});a=v.get('numeric');b=before.get('numeric')
    md.append(f'| {k} | {before.get("grade","N/A")} {b if b is not None else ""} | {v["grade"]} {a if a is not None else ""} | {a-b if a is not None and b is not None else "N/A"} |')
md+=['','Calcul identique : 100 − 25×CRITICAL − 10×HIGH − 3×MEDIUM − LOW par domaine, plancher zéro. Moyenne pondérée, somme des poids 19. Les constats de complexité sont comptés une seule fois, dans complexity. Aucune suppression par baseline.','', '## Périmètre et vérifications','',f'{len(production)} fichiers Swift de production lus intégralement. Tests et documentation par risque. Couverture de lecture production : {coverage:.0f} %. Cette mesure ne certifie pas chaque ligne des tests et documents.', 'Compilation réussie via swift test. 1112 tests verts, puis 4 tests sûrs de la suite T6 : **1116 tests distincts réussis**. 47 tests non exécutés : 42 dans trois suites à sockets hors scratch et 5 tests du cycle de vie qui arrêtent leurs processus. Les 1163 annoncés ne sont donc pas présentés comme réexécutés intégralement.',f'Journaux : {S}/validation/test.log et {S}/validation/safe-t6-test.log',f'Nettoyage du scratch : {S}/validation/cleanup.json','', '## Tableau des 65 constats','', '| Audit | ID | Sévérité initiale | Constat | Statut actuel | Preuve et motif |','|---|---|---|---|---|---|']
for x in comparisons:
    ev=x.get('evidence',[]);e=ev[0] if ev else {};proof=f'{e.get("file","")}:{e.get("line","")}'
    md.append(f'| {x["source_audit"]} | {x["id"]} | {x["original_severity"]} | {x["title"]} | **{x["status"]}** | {proof} — {x.get("reason","").replace(chr(10)," ").replace("|","/")} |')
md+=['','## Findings par sévérité','', '| ID | Sévérité | Origine | Constat | Emplacement |','|---|---|---|---|---|']
for f in findings:md.append(f'| {f["id"]} | {f["severity"]} | {f["origin"]} | {f["title"]} | {f["absolute_file"]}:{f["line"]} |')
md+=['','## Détail des findings','']
for f in findings:
    md += [f'### {f["id"]} — {f["severity"]} — {f["title"]}','',f'Fichier : {f["absolute_file"]}:{f["line"]}',f'Statut : {f["verification_status"]}.',f'Description : {f["description"]}',f'Scénario : {f.get("exploitation_scenario","Sans objet")}',f'Impact : {f["impact"]}','', '```',f['evidence'],'```','',f'Correction : {f["remediation"]}',f'Validation : {f["verification"]}',f'Effort : {f["effort"]}. Risque : {f["regression_risk"]}.']
    if f.get('counter_audit'):md += [f'Contre-audit : {f["counter_audit"]} — {f["counter_audit_artifact"]}']
    for p in f.get('related_locations',[]) + f.get('supporting_evidence',[]):md += [absolute(p['file'])+f':{p.get("line","")} — '+p.get('note',p.get('description',''))]
    if f.get('remediation_code'):md += ['','Exemple de correction proposé, non appliqué :','','```',f['remediation_code'],'```']
    md += ['']
md += ['## Complexité algorithmique et performance','',decisions['complexity_note'],'Aucune latence utilisateur mesurée. Les classes de coût proviennent des parcours réels. Chaque correction doit conserver résultats et ordre, puis comparer les mêmes entrées avant/après. Revenir au code précédent si les invariants régressent.','', '## Minimalisme & Frugalité','',f'Potentiel minimalisme : ~{decisions["minimalism_lines"]} lignes suppressibles à comportement constant',decisions['minimalism_note'],'Checklist : helpers, wrappers, état dérivé, branches mortes, abstractions anticipées, dépendances, code hors besoin. Pas de framework proposé pour les corrections.','', '## Vertus LLM & Responsabilité Future','', 'Les résultats explicites et les transactions réduisent les règles implicites. Les tests de pannes rendent les invariants plus lisibles. Leur application reste incomplète aux chemins signalés. Le volume de correction répond aux scénarios précis, mais le vert des tests ne suffit pas à certifier les autres appelants. Aucune origine du code n’est déduite de son style. Pas d’intégration LLM détectée dans Roadie.','', '## Points positifs','']
for x in positives:
    md.append('- '+(x if isinstance(x,str) else json.dumps(x,ensure_ascii=False)))
md+=['','## Dépendances et sécurité','', 'TOMLKit est verrouillée à une révision. Aucun scan externe de vulnérabilités, aucune conclusion d’absence de CVE. Socket Unix et processus locaux relus. Pas d’API web, paiement ni SQL applicable. Deux scans des chemins sensibles. Les permissions réelles du HOME et les protections système contre les liens symboliques ne sont pas certifiées.','', '## Findings supprimés par la baseline','', 'Aucun. Les candidats réfutés ou non retenus sont documentés séparément et ne sont pas des risques acceptés.','', '## Roadmap de remédiation','', '1. Corriger les HIGH de complexité et valider leurs invariants par tests de tailles croissantes.', '2. Terminer REL-021 et les adaptations des statuts de résultat. Ajouter les cas métier absents.', '3. Traiter les LOW sans refonte générale.','', '## Ce qui n’a pas été vérifié','']
md += ['- '+x for x in limits]
md += ['', '## Intégrité et artefacts','',f'Aucun code source modifié. Aucun commit, stash, checkout ou reset. Contrôle : {S}/integrity-check.json',f'Validation canonique : {S}/validation/session-validator.log',f'Comparaison : {S}/comparison.json',f'Candidats arbitrés : {S}/deferred-and-merged.json',f'Rapport : {S}/scoring.md','']
(S/'scoring.md').write_text('\n'.join(md))
write('grade.json',{'grade':grade(score),'date':'2026-10-13','spec':'all','scope':'Tout le dépôt Roadie à HEAD 4643ae4d, worktree 022-audit-remediation','coverage_percent':coverage,'score_numeric':score,'release_blocked':blocked,'justification':'Score canonique v14 des constats actifs. Lecture intégrale production; tests/docs par risque. Les HIGH bloquent indépendamment du score global.','metrics':metrics})
write('counter-audit.json',decisions['counter_audits'])
write('deferred-and-merged.json',{'not_retained':decisions['excluded'],'merged':decisions.get('merged',[]),'baseline_suppressions':[]})
print(json.dumps({'score':score,'grade':grade(score),'blocked':blocked,'counts':dict(counts),'comparison':comparison['summary'],'production':len(full&production)},ensure_ascii=False))
