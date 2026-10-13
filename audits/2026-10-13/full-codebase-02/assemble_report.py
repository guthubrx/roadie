from pathlib import Path
from collections import Counter
import json, datetime, subprocess, hashlib, re
R=Path('/Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation')
S=R/'audits/2026-10-13/full-codebase-02'
P=Path('/Users/moi/Nextcloud/10.Scripts/00.Generic/audit-code-v14')
def write(name,value):
    (S/name).write_text(json.dumps(value,ensure_ascii=False,indent=2)+'\n')
raw={p.stem:json.loads(p.read_text()) for p in sorted(S.glob('raw-*.json'))}
old=json.loads((R/'audits/2026-10-13/full-codebase-01/cycle-1/aggregated-findings.json').read_text())
old_by_id={f['id']:f for f in old['findings']}
previous=json.loads((R/'audits/2026-10-13/full-codebase-01/grade.json').read_text())
manifest=json.loads((S/'manifest.json').read_text())
inv=json.loads((S/'source-inventory.json').read_text())
manifest['repo']['files_count']=len(inv['production'])+len(inv['tests'])+sum(p.startswith('scripts/') and p.endswith('.py') for p in inv['tracked'])
manifest['audit_meta']['mode']='S / LIGHT'
manifest['audit_meta']['parallelism_note']='Six lectures thématiques et une contre-lecture indépendante; mêmes règles de sévérité et de notation que le premier audit.'
write('manifest.json',manifest)
status={x['id']:x for d in raw.values() for x in d['original_statuses']}
assert set(status)==set(old_by_id) and len(status)==50
idmap={
'REL-101':'REL-001','REL-102':'REL-021','REL-201':'REL-012','REL-301':'REL-032',
'PERF-MODELS-001':'PERF-008','PERF-901':'PERF-009',
'REL-MODELS-001':'REL-033','REL-MODELS-002':'REL-034','REL-901':'REL-035','REL-902':'REL-036',
'REL-202':'REL-037','REL-203':'REL-038','REL-UI-001':'REL-039','REL-UI-002':'REL-040',
'REL-302':'REL-041','REL-ROOT-001':'REL-042','OBS-301':'OBS-002','OBS-302':'OBS-003','MIN-MODELS-001':'MIN-005'}
findings=[]
for name,d in raw.items():
    for orig in d['findings']:
        f=dict(orig); f['source_id']=f['id'];f['id']=idmap[f['id']];f['source_artifact']=str(S/(name+'.json'))
        f['absolute_file']=str(R/f['file']);f['status']='open';f['remediation_applied']=False
        f['origin']='résiduel d’un constat initial' if f['id'] in old_by_id else 'nouveau constat de cet audit; antériorité Git non attribuée sauf précision'
        if f['id'] in old_by_id:
            f['original_finding_id']=f['id'];f['original_fingerprint']=old_by_id[f['id']]['fingerprint']
        if f['severity']=='HIGH':f['counter_audit']='CONFIRMED'
        findings.append(f)
fby={f['id']:f for f in findings}
# Fusion des deux entrées fatales : même famille de validation de commandes stage.
f=fby['REL-001']
f['title']='Des arguments stage peuvent encore arrêter le daemon'
f['description']+=' Un second chemin accepte UInt32(0) pour stage summon puis construit WindowID(0), dont la précondition arrête le processus. Ces commandes sont routées au daemon.'
f['exploitation_scenario']+=' Variante directe avec écran actif : roadie stage summon 0. Le routeur accepte zéro et atteint la précondition WindowID > 0. Aucun crash réel provoqué pendant l’audit.'
f.setdefault('related_locations',[]).extend([
 {'file':'Sources/RoadieDaemon/CLICommandRouter.swift','line':1064,'note':'UInt32(0) accepté; WindowID construit ligne1076.'},
 {'file':'Sources/RoadieCore/Identifiers.swift','line':48,'note':'Précondition rawValue > 0.'}])
f['remediation_code']+='\n\n// Dans runStageCommand, branche summon, remplacer le guard existant :\nguard let rawWindowID = args.dropFirst().first, let id = UInt32(rawWindowID), id > 0 else {\n    err("roadie: stage summon requires a positive window id")\n    return 64\n}'
f['verification']+=' Ajouter stage summon 0 : code64 et aucune fin de processus. Tester aussi les conversions WindowID des commandes group.'
f['verification_status']='confirmé par lecture et contre-audit indépendant; StageID Int.max et débordement démontrés par sonde non fatale; aucun crash daemon exécuté'
status['REL-001']['reason']+=' Deux chemins fatals restent ouverts : génération après Int.max et stage summon 0.'
status['REL-001']['evidence'].append({'file':str(R/'Sources/RoadieDaemon/CLICommandRouter.swift'),'line':1064,'note':'Zéro accepté puis WindowID(0) à1076.'})
# Fusion de la persistance au même constat, sans compter chaque entrée séparément.
f=fby['REL-021']
f.setdefault('related_locations',[]).extend([
 {'file':'Sources/RoadieDaemon/WindowContextActions.swift','line':373,'note':'État persistant modifié avant retrait faillible de l’intent.'},
 {'file':'Sources/RoadieDaemon/StateAudit.swift','line':82,'note':'heal conserve mutate non checked et peut compter des réparations non persistées.'},
 {'file':'Sources/RoadieDaemon/CLICommandRouter.swift','line':366,'note':'state heal déduit le code seulement de report.audit.failed.'}])
f['description']+=' StateAudit.heal conserve aussi mutate non checked : un échec de stockage peut laisser un nombre de réparations positif sans écriture effective.'
f['exploitation_scenario']+=' Variante heal : état sans activeDisplayID et répertoire non inscriptible, snapshot non persistant avec un écran; mutate calcule une réparation, l’écriture échoue, active-display reste warn/none et le rapport peut encore sortir en succès.'
f['verification']+=' Injecter ces pannes dans WindowContextActions et StateAudit.heal; aucune réparation non persistée ne doit être déclarée réussie.'
# Reproductions isolées sur les objets compilés de la branche.
for fid in ['REL-033','REL-036','REL-042','OBS-002']:
    fby[fid]['verification_status']='confirmé par lecture et sonde isolée utilisant le code compilé de la branche; aucun effet sur le bureau'
    fby[fid]['runtime_evidence']=str(S/'validation/probe-results.log')
fby['REL-042']['origin']='résiduel connu FR-039/R2-06, préexistant à la session, nouvel ID dans cet audit complet; non supprimé par baseline'
# Les constats qualité relèvent de la règle canonique de l’outil, pas d’une estimation de latence.
for fid in ['PERF-008','PERF-009']:
    fby[fid]['severity_rationale']='HIGH selon le module04 v14, comme l’audit initial : parcours quadratique évitable sur un chemin de disposition non borné. Aucune latence réelle mesurée; usage local, pas endpoint réseau distant.'
# Garder des titres lisibles et compatibles avec le schéma.
fby['PERF-008']['title']='Le plan BSP dwindle reste quadratique sans priorité de redimensionnement'
# Correspondance contrôlée des preuves.
for f in findings:
    text=(R/f['file']).read_text(); assert f['evidence'] in text,(f['id'],'preuve absente')
    assert 0<f['line']<=len(text.splitlines())
    assert len(f['title'])<100,(f['id'],'titre trop long')
# Empreintes via l’implémentation de référence obligatoire.
batch=subprocess.run(['python3',str(P/'scripts/fingerprint.py'),'--batch'],input=json.dumps({'findings':findings}),text=True,capture_output=True,check=True)
findings=json.loads(batch.stdout)['findings']
rank={'CRITICAL':0,'HIGH':1,'MEDIUM':2,'LOW':3}
findings.sort(key=lambda f:(rank[f['severity']],f['id']))
sev=Counter(f['severity'] for f in findings);cats=Counter(f['category'] for f in findings)
weights={'security':3,'supply_chain':1,'observability':1,'reliability':2,'tests':1,'performance':2,'complexity':2,'quality':2,'architecture':1,'ai_hygiene':1,'duplication':1,'minimalism':1,'ux':1}
def domain(f):return 'complexity' if f.get('subcategory')=='algorithmic_complexity' else f['category']
def grade(v):
    return next(g for threshold,g in [(90,'A'),(85,'A-'),(80,'B+'),(75,'B'),(60,'C'),(40,'D'),(0,'F')] if v>=threshold)
metrics={}
for dom in weights:
    fs=[f for f in findings if domain(f)==dom];counts=Counter(f['severity'] for f in fs)
    numeric=max(0,100-sum({'CRITICAL':25,'HIGH':10,'MEDIUM':3,'LOW':1}[f['severity']] for f in fs))
    metrics[dom]={'grade':grade(numeric),'numeric':numeric,'findings_count':len(fs),'by_severity':dict(counts)}
metrics['llm_security']={'grade':'N/A','findings_count':0}
score=round(sum(metrics[k]['numeric']*w for k,w in weights.items())/sum(weights.values()),2)
blocked=bool(sev['HIGH'] or sev['CRITICAL'])
full=set();partial=set();warnings=[];positives=[]
for d in raw.values():
    for key,out in [('files_read_full',full),('files_read_partial',partial)]:
        for x in d[key]:
            x=x if isinstance(x,str) else x.get('file',x.get('path',''))
            if x:out.add(str(R/x) if not x.startswith('/') else x)
    for x in d['positive_findings']:
        if isinstance(x,str):positives.append(x)
        else:
            ev=x.get('evidence',x)
            positives.append(f"{ev.get('file','')}:{ev.get('line','')} — {x.get('description',x.get('text',x.get('practice',x.get('note',str(x)))))}")
    warnings.extend(d['warnings'])
assert all(str(R/p) in full for p in inv['production'])
read_inventory={'definition':'Lecture intégrale des 96 fichiers Swift de production; tests, scripts, docs et specs par risque. La couverture de lecture ne mesure pas la couverture des tests.','production_count':len(inv['production']),'production_read_full':len(inv['production']),'full':sorted(full),'partial_only':sorted(partial-full)}
write('read-inventory.json',read_inventory)
now=datetime.datetime.now(datetime.timezone.utc);start=datetime.datetime.fromisoformat(manifest['audit_meta']['timestamp'])
duration=int((now-start).total_seconds()*1000)
limits=[
 '42 tests exclus (CLICommandRouterTests, Audit022LotITests, Audit022R2LotCTests), car leurs sockets imposent des chemins /tmp hors scratch. 1044 tests exécutés avec succès.',
 'Aucune interaction réelle AX/AppKit, aucun glisser réel, aucun écran branché/débranché, aucun clic ou macro sur le bureau.',
 'Aucun processus existant arrêté ou relancé. Désinstallation et cycle de vie modulaire vérifiés par lecture seulement.',
 'Aucun profil CPU/mémoire ni benchmark de latence réelle; HIGH de complexité = règle structurelle du protocole, pas preuve de ralentissement ressenti.',
 'Aucun taux global JSCPD, mutation testing, couverture instrumentée ou scanner CVE. Dépendance TOMLKit non expertisée en profondeur; historique Git complet non scanné pour secrets.',
 'Packaging, signature et Gatekeeper non exécutés; permissions et ACL réelles du HOME non auditées.',
 'Documentation et tests lus selon les risques; seuls les 96 fichiers Swift de production ont tous une lecture intégrale.',
 'Pointeur audits/latest non modifié, conformément à la restriction utilisateur des écritures.',
 'Avertissement de compilation existant : modificateur internal dans extension private de DaemonSnapshot.swift:2193; compilation réussie.',
]
warning_summary=limits+[f'contre-audit {fid}: CONFIRME (voir {S}/counter-audit.json)' for fid in ['REL-001','PERF-008','PERF-009']]
comparisons=[]
for orig in old['findings']:
    x=dict(status[orig['id']]);x.update({'title':orig['title'],'original_severity':orig['severity'],'original_fingerprint':orig['fingerprint'],'active_finding_id':orig['id'] if x['status']!='résolu' else None})
    
    for previous_id, canonical_id in sorted(idmap.items(),key=lambda item:-len(item[0])):
        x['reason']=x['reason'].replace(previous_id,canonical_id)
    comparisons.append(x)
comp={'baseline_path':str(R/'audits/2026-10-13/full-codebase-01'),'baseline_score':83.16,'current_score':score,'summary':dict(Counter(x['status'] for x in comparisons)),'method':'Lecture du scénario de chaque constat et de son correctif; correspondance manuelle conservée même si l’empreinte change. L’absence d’empreinte n’est pas utilisée comme preuve de résolution.','original_findings':comparisons,'new_finding_ids':[f['id'] for f in findings if f['id'] not in old_by_id]}
write('comparison.json',comp)
meta={'version':'v14.0','timestamp':now.isoformat(),'start_timestamp':start.isoformat(),'end_timestamp':now.isoformat(),'duration_ms':duration,'audit_scope':str(R),'audit_mode':'readonly','audit_grid':'all','modules_actifs':manifest['modules_actifs'],'score_global':grade(score),'score_numeric':score,'release_blocked':blocked,'scores':{k:v['grade'] for k,v in metrics.items()},'repository':manifest['repo'],'commit':manifest['audit_meta']['head']}
aggregate={'$schema':'audit-code-v14/aggregated-findings','meta':meta,'execution_metrics':{'files_scanned':96,'files_total':96,'lines_analyzed':sum(len((R/p).read_text().splitlines()) for p in inv['production']),'coverage_definition':read_inventory['definition'],'tools_used':['rg','git-readonly','Swift compiler','Swift Testing','isolated probes','manual-full-read','fingerprint.py','validate_session.py'],'coverage_estimate_percent':100,'sampling_method':None,'phases_completed':['00','01','02','03','04','05','06','07','08','10','11','12'],'phases_skipped':['09 (readonly)'],'warnings':warning_summary},'summary':{'critical':sev['CRITICAL'],'high':sev['HIGH'],'medium':sev['MEDIUM'],'low':sev['LOW'],'info':0,'total':len(findings),'by_category':dict(cats)},'supply_chain':{'slsa_level':None,'slsa_target':2,'sbom_ready':None,'vulnerable_deps_count':None,'license_issues_count':None,'note':'Lockfile TOMLKit0.6.0 présent; aucun scan externe CVE ni attestation de build.'},'duplicated_code':{'jscpd_percentage':None,'duplicated_lines':None,'max_block_lines':None,'total_occurrences':None,'critical_blocks':[],'method':'Lecture manuelle ciblée; pas de pourcentage global inventé.'},'ai_hygiene':{'suspected_ai_ratio_percent':None,'note':'Aucune origine de code déduite du style.'},'llm_governance':{'applicable':False},'slos':manifest['slos'],'findings':findings,'suppressed':[],'positive_findings':positives,'roadmap':{'immediate':[f['id'] for f in findings if f['severity'] in ('HIGH','CRITICAL')],'short_term':[f['id'] for f in findings if f['severity']=='MEDIUM'],'medium_term':[],'long_term':[f['id'] for f in findings if f['severity']=='LOW']}}
write('cycle-1/aggregated-findings.json',aggregate)
modulemap={'securite':('03',{'security','supply_chain','observability'}),'complexite':('04',{'complexity'}),'qualite':('05',{'quality','architecture','ai_hygiene'}),'tests':('06',{'tests','reliability'}),'duplication':('07',{'duplication'}),'performance':('08',{'performance','ux'}),'minimalisme':('12',{'minimalism'})}
for name,(module,doms) in modulemap.items():write(f'cycle-1/findings_{name}.json',{'module':module,'findings':[f for f in findings if domain(f) in doms]})
minimal=sum(d.get('minimalism',{}).get('removable_lines_estimate',0) for d in raw.values())
# Markdown : preuve absolue, scénario et remédiation pour chaque constat actif.
a=['# Audit de code Roadie — v14 après corrections','',f'**Date :** 2026-10-13. **Mode :** readonly, périmètre complet, un cycle.',f'**Racine :** {R}',f'**Branche :** 022-audit-remediation. **Commit :** {meta["commit"]}. 34 commits au-dessus de main.',f'**Score global : {grade(score)} — {score:.2f}/100. Blocage de livraison : OUI.**',f'**Durée :** {duration/60000:.1f} minutes. **Constats actifs :** {len(findings)} ({sev["HIGH"]} HIGH, {sev["MEDIUM"]} MEDIUM, {sev["LOW"]} LOW).','', '## Résumé exécutif','',f'Les 50 constats initiaux ont été vérifiés : **46 résolus, 4 partiels, 0 ouvert sans progrès**. {len(comp["new_finding_ids"])} nouveaux constats s’ajoutent aux quatre résiduels. « Nouveau » signifie absent du premier rapport ; cela ne prouve pas une régression introduite par cette session.', 'Les six anciens HIGH autres que REL-001 sont résolus. REL-001 reste HIGH avec deux autres entrées fatales. Deux nouveaux HIGH de complexité maintiennent aussi le blocage v14. Aucun CRITICAL.',f'La note A est une moyenne pondérée. **La fiabilité reste {metrics["reliability"]["grade"]} ({metrics["reliability"]["numeric"]}/100)** ; elle ne doit pas être masquée par la moyenne.', '', '## Tendance','', '| Domaine | Avant | Maintenant | Écart de score |','|---|---:|---:|---:|',f'| Global | B+ 83,16 | {grade(score)} {score:.2f} | +{score-83.16:.2f} |']
for k,v in metrics.items():
    prev=previous['metrics'].get(k,{});val=v.get('numeric');pv=prev.get('numeric');a.append(f'| {k} | {prev.get("grade","N/A")} {pv if pv is not None else ""} | {v["grade"]} {val if val is not None else ""} | {val-pv if val is not None and pv is not None else "N/A"} |')
a+=['','Méthode identique au premier audit : domaine = 100 − 25×CRITICAL − 10×HIGH − 3×MEDIUM − LOW, plancher zéro. Moyenne pondérée des domaines applicables (somme des poids : 19). Les constats algorithmiques vont dans complexity et ne sont pas comptés une seconde fois dans performance. Les HIGH bloquent indépendamment de la moyenne. Aucune suppression par baseline (fichier absent).','', '## Périmètre et vérifications','',read_inventory['definition'],f'Inventaire : {S}/read-inventory.json',f'Compilation via swift test réussie. **1044 tests passés**, 42 exclus de trois suites pour respecter les chemins autorisés. Le total de 1086 annoncé par la session n’est donc pas présenté comme réexécuté intégralement ici.',f'Journal : {S}/validation/test.log',f'Sondes réelles isolées : {S}/validation/probe-results.log', 'Les sondes confirment le faux code de sortie, le débordement de géométrie bsp, la suspension après release et la lecture UTF-8 vide. Elles confirment aussi l’acceptation de StageID Int.max et le dépassement suivant sans provoquer le trap.',f'Le dossier temporaire /tmp/roadie-build-022-audit2 a été supprimé. Preuve : {S}/validation/cleanup.json','', '## Tableau des 50 constats d’origine','', '| ID | Sévérité initiale | Constat | Statut actuel | Preuve actuelle |','|---|---|---|---|---|']
for x in comparisons:
    ev=x.get('evidence',[]);e=ev[0] if ev else {};loc=f"{e.get('file','')}:{e.get('line','')}"
    a.append(f'| {x["id"]} | {x["original_severity"]} | {x["title"]} | **{x["status"]}** | {loc} — {x["reason"].replace(chr(10)," ").replace("|","/")} |')
a+=['','Les éléments résolus sont confirmés sur leurs scénarios précis. Exemple : PERF-004 est résolu dans la réparation des voisines ; PERF-009 identifie une autre boucle de calcul des minima. REL-031 est résolu pour masterStack ; REL-033 vise le moteur bsp. Ces distinctions évitent de compter deux fois le même défaut.','', '## Findings par sévérité','', '| ID | Sévérité | Origine | Constat | Fichier et ligne |','|---|---|---|---|---|']
for f in findings:a.append(f'| {f["id"]} | {f["severity"]} | {"Résiduel" if f["id"] in old_by_id else "Nouveau"} | {f["title"]} | {f["absolute_file"]}:{f["line"]} |')
a+=['','## Détail des findings','']
for f in findings:
    a += [f'### {f["id"]} — {f["severity"]} — {f["title"]}','',f'**Fichier :** {f["absolute_file"]}:{f["line"]}',f'**Statut :** {f.get("verification_status","confirmé par lecture; scénario réel non exécuté")}. **Origine :** {f["origin"]}.',f'**Description :** {f["description"]}',f'**Scénario :** {f.get("exploitation_scenario","Sans objet.")}',f'**Impact :** {f["impact"]}','', '```'+('swift' if f['file'].endswith('.swift') else ''),f['evidence'],'```','',f'**Correction :** {f["remediation"]}',f'**Validation :** {f["verification"]}',f'**Effort :** {f["effort"]}. **Risque de régression :** {f["regression_risk"]}.']
    if f.get('severity_rationale'):a.append(f'**Motif de sévérité :** {f["severity_rationale"]}')
    if f.get('counter_audit'):a.append(f'**Contre-audit :** {f["counter_audit"]}. Voir {S}/counter-audit.json')
    if f.get('related_locations'):
        a.append('**Autres preuves :**')
        for loc in f['related_locations']:
            path=loc.get('file','');path=path if path.startswith('/') else str(R/path)
            a.append(f'- {path}:{loc.get("line","")} — {loc.get("note",loc.get("description",""))}')
    a+=['','**Exemple de correction proposé, non appliqué :**','','```',f.get('remediation_code','Voir correction et validation ci-dessus.'),'```','']
a+=['## Minimalisme & Frugalité','',f'Potentiel minimalisme : ~{minimal} lignes suppressibles à comportement constant','', 'Checklist exécutée : code mort, helpers sans utilité, wrappers, état dérivé, abstraction anticipée, fonctions hors besoin, dépendances évitables et chemins de validation inatteignables. Les anciennes surcharges JSON et duplications de pipelines ont été retirées. Le reliquat comprend sept lignes de validation inatteignable (MIN-005) et deux lignes privées jamais lues dans FileAdministration. Aucun grand refactoring n’est proposé sans besoin.', '', '## Vertus LLM & Responsabilité Future','', 'La session réduit la charge cognitive sur les correctifs vérifiés : encodage commun, résultat de persistance contrôlé, fonctions de calcul partagées et tests de comportement plus précis. Le volume ajouté aux verrous, à la validation AX et aux écritures contrôlées répond à des cas documentés. Les abstractions ont un usage réel ; les défauts restants concernent leur application incomplète aux points d’entrée, plutôt qu’un besoin de nouvelles couches.', 'Les invariants et les tests rendent le code explicable. Les noms de tests ne suffisent toutefois pas : les variantes de fenêtre, de moteur et de panne manquaient encore. Aucune origine LLM du code n’est déduite du style. Aucun service LLM intégré à l’application détecté.', '', '## Complexité algorithmique et performance','', 'Checklist explicite : doubles boucles, recherche linéaire en boucle, N+1 de lecture/API, tris répétés, concaténations répétées, I/O sans regroupement, récursion et copies successives. Les quatre HIGH algorithmiques initiaux sont résolus sur leurs sites. Deux autres cas non bornés sont confirmés : PERF-008 et PERF-009. Les coûts sont déduits du code ; aucune amélioration de latence chiffrée n’est annoncée. Les corrections proposées ont un plan de validation et de retour arrière dans les artefacts.', '', '## Points positifs','']
a += ['- '+x for x in positives]
a += ['', '## Dépendances et zones sensibles','', 'TOMLKit est verrouillée à 0.6.0 et à une révision précise. Aucune conclusion d’absence de CVE sans scan. Le contrôle sécurité a couvert deux recherches distinctes sur permissions, secrets, processus, fichiers et journaux. Aucun nouveau défaut de sécurité confirmé. Absence d’authentification web, de paiement et de moteur LLM ; persistance JSON locale, pas de migration de base SQL. Les permissions effectives du dossier utilisateur et l’historique complet des secrets ne sont pas certifiés.', '', '## Findings supprimés par la baseline','', 'Aucun. Le résiduel FR-039 reste scoré en LOW, même s’il était connu et volontairement laissé pour plus tard.', '', '## Roadmap de remédiation','', '1. Corriger REL-001 et protéger toutes les conversions d’identifiants ; traiter PERF-008 et PERF-009 avec tests de complexité.', '2. Terminer REL-012, REL-021 et REL-032. Corriger les nouveaux MEDIUM avec tests ciblés.', '3. Traiter les LOW, dont le statut métier explicite de FR-039 et le nettoyage des dossiers de tests.', '', '## Ce qui n’a pas été vérifié','']
a+=['- '+w for w in limits]
a+=['', '## Intégrité et artefacts','', 'Aucun code source corrigé. Aucun commit, stash, checkout ou reset. Seul le dossier de cet audit contient des écritures persistantes.',f'Empreintes avant/après : {S}/integrity-check.json',f'Comparaison machine des 50 constats : {S}/comparison.json',f'Constats agrégés : {S}/cycle-1/aggregated-findings.json',f'Validation du protocole : {S}/validation/session-validator.log','']
(S/'scoring.md').write_text('\n'.join(a))
# grade.json est écrit après le rapport, conformément au protocole.
write('grade.json',{'grade':grade(score),'numeric':score,'date':'2026-10-13','spec':'all','scope':f'Tout le dépôt Roadie au commit {meta["commit"][:7]}, après session022; audit readonly v14','coverage_percent':100,'coverage_definition':read_inventory['definition'],'justification':f'Moyenne canonique {score:.2f}/100; fiabilité {metrics["reliability"]["grade"]}; {sev["HIGH"]} HIGH confirmés bloquent la livraison.','release_blocked':blocked,'metrics':metrics})
write('deferred-and-merged.json',{'merged':['REL-001 : assign-empty Int.max et stage summon0, même famille validation','REL-021 : zoomParent, transferts desktop/window/stage, menu et heal, même contrat de persistance'], 'not_retained':['Course ConfigReloadService : aucune concurrence réelle de production établie','Restauration de fenêtre float via menu périmé : contexte non reproduit, non scoré'], 'baseline_suppressions':[]})
print(json.dumps({'score':score,'grade':grade(score),'summary':aggregate['summary'],'metrics':metrics,'original_statuses':comp['summary'],'new_findings':len(comp['new_finding_ids']),'minimalism_lines':minimal},ensure_ascii=False,indent=2))
