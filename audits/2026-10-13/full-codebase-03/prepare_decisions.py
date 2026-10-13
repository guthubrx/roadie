import json
from pathlib import Path

S=Path(__file__).resolve().parent
R=S.parents[2]
def read(name): return json.loads((S/name).read_text())
def write(name,obj): (S/name).write_text(json.dumps(obj,ensure_ascii=False,indent=2)+'\n')
mapping={
 'raw-models-completion.json:MODEL-NEW-001':'PERF-010',
 'raw-runtime-completion.json:RUNTIME-NEW-001':'PERF-011',
 'raw-commands-completion.json:CMD-NEW-02':'PERF-012',
 'raw-commands-completion.json:REL-021':'REL-021',
 'raw-commands-completion.json:CMD-NEW-01':'REL-043',
 'raw-targets-completion.json:TARGETS-NEW-001':'REL-044',
 'raw-models-completion.json:MODEL-NEW-002':'REL-045',
 'raw-runtime-completion.json:RUNTIME-NEW-002':'REL-046',
 'raw-targets-completion.json:TARGETS-NEW-002':'REL-047',
 'raw-targets-completion.json:TARGETS-NEW-003':'REL-048',
 'raw-ui-completion.json:UI-NEW-001':'REL-049',
 'raw-security-completion.json:REL-401':'REL-050',
 'raw-models-completion.json:MODEL-NEW-003':'MIN-006',
 'raw-security-completion.json:MIN-002':'MIN-007',
 'raw-ui-completion.json:UI-NEW-003':'MIN-008',
}
excluded={
 'raw-security-completion.json:MIN-001': 'Non retenu : double appel dans self-test froid, aucun effet visible démontré ; le remplacement par une variable ne supprime pas de complexité significative.',
 'raw-security-completion.json:REL-402': 'Scénario réfuté : scripts/install:35-40 rejette une identité nommée inconnue avant copie ou signature. Un autre échec de codesign n’a pas été reproduit. Le pseudo-code de preuve contenait aussi des commentaires absents du source.',
 'raw-security-completion.json:SEC-001': 'Scénario réfuté tel que formulé : un répertoire 0755 ne permet pas à un autre utilisateur de créer le fichier stop. Précréation du chemin ou lien symbolique du journal prévisible restent des pistes non vérifiées, sans conclusion d’absence de risque.',
 'raw-ui-completion.json:UI-NEW-002': 'Non retenu : gap=0 interprété comme repli vers layout.spacing ; contrat utilisateur insuffisant pour affirmer que ce comportement est erroné.',
}
counter=read('counter-reconcile.json')
overrides={
 'raw-commands-completion.json:CMD-NEW-02': {
  'title':'Le rapprochement rescane les mêmes candidats pour chaque membre absent',
  'line':1519,
  'verification_status':'confirmé par lecture et contre-audit indépendant ; aucun benchmark exécuté',
  'severity_review_required':False,
  'remediation':counter['remediation'], 'remediation_code':counter['remediation_code'],
  'complexity_target':counter['target_complexity'], 'counter_audit_pending':False,
  'verification':' '.join(counter['verification_recommended']),
 },
 'raw-runtime-completion.json:RUNTIME-NEW-002':{
  'verification_status':'plausible : entrelacement interprocessus établi par lecture ; course non reproduite',
  'exploitability':'LIKELY',
 },
 'raw-security-completion.json:REL-401':{
  'title':'Le démarrage peut être annoncé en échec avant la fin de son initialisation',
  'verification_status':'plausible : délai fixe confirmé ; démarrage lent non reproduit',
  'exploitability':'LIKELY',
  'verification':'Ajouter un test shell avec faux daemon et écriture du PID retardée. Vérifier succès après convergence et message de délai dépassé si le processus reste en initialisation. Ne pas lancer le vrai daemon pour ce test.',
  'remediation':'Sonder le PID et le verrou avec un délai borné configurable, puis annoncer explicitement une absence de disponibilité dans ce délai. Ne pas annoncer avec certitude un échec du processus encore vivant.',
  'remediation_code':'',
 },
 'raw-security-completion.json:MIN-002':{
  'line':61,
  'evidence':'  local name="$1"\n  local args="$2"\n  local session="roadie-${name}"',
  'remediation_code':'',
  'verification':'Vérifier la liste et les arguments avec une doublure de tmux dans les tests shell. Ne pas lancer les composants réels pour vérifier cette simplification.',
  'removable_lines_estimate':2,
 },
 'raw-ui-completion.json:UI-NEW-003':{'line':25},
}
for key in ['raw-models-completion.json:MODEL-NEW-002','raw-targets-completion.json:TARGETS-NEW-003','raw-ui-completion.json:UI-NEW-001','raw-ui-completion.json:UI-NEW-003']:
 overrides.setdefault(key,{})['verification_status']='confirmé par lecture et sonde Swift pure exécutée ('+str(S/'validation/probe.log')+')'
status_overrides={
 'REL-014':{'id':'REL-014','status':'résolu','reason':'config reload est routé au daemon par isDaemonRouted ; le routeur utilise le ConfigReloadService partagé injecté. Le rechargement modifie donc le service actif.', 'evidence':[{'file':'Sources/RoadieDaemon/CLICommandRouter.swift','line':348,'note':'Routage de config reload au daemon.'},{'file':'Sources/RoadieDaemon/CLICommandRouter.swift','line':579,'note':'Appel au service de rechargement injecté.'}]},
}
write('review-decisions.json',{
 'id_map':mapping,'excluded':excluded,'overrides':overrides,'status_overrides':status_overrides,
 'counter_audits':{k:{'verdict':'CONFIRMED','artifact':str(S/v)} for k,v in [('PERF-010','counter-snapshot.json'),('PERF-011','counter-layout.json'),('PERF-012','counter-reconcile.json')]},
 'complexity_note':'PERF-010 : reconstruction O(w²) par scans de suppression répétés ; construire les appartenances en une passe. PERF-011 : O(k×n²), donc O(n³) si k≈n ; dédupliquer les scopes avant validation pour revenir à une validation O(n²) par scope. PERF-012 : première passe O(m×w log w), puis O(m×w) répété pour les membres orphelins ; exclure une fois les candidats déjà revendiqués et chercher les deux meilleurs sans tri. Cette dernière correction ne garantit pas O(M+W) pour les groupes homonymes non résolus. Aucune borne effective ni choix de coût documenté ne neutralise ces chemins fréquents. Trois contre-audits indépendants confirment le niveau HIGH.',
 'minimalism_lines':63,
 'minimalism_note':'MIN-006 : 3 lignes inaccessibles. MIN-007 : ~2 lignes de paramètre/extraction inutiles, plus simplification des six entrées. MIN-008 : ~58 lignes de sélection d’écran algébriquement redondantes. Estimation indicative, sans modification du source.',
})
limitations=[
 '47 des 1163 tests annoncés n’ont pas été exécutés : 42 tests des suites CLICommandRouterTests, Audit022LotITests et Audit022R2LotCTests utilisent des sockets hors du scratch ; 5 tests de cycle de vie dans Audit022R4LotT6Tests arrêtent leurs propres processus. Le test réseau intermittent cité fait partie des exclusions.',
 'Aucune interaction réelle avec les fenêtres, clics, glisser-déposer, hotkeys, écrans, Accessibilité macOS ou capture. Les scénarios système restent vérifiés par lecture ; les sondes ajoutées sont pures.',
 'Aucun démarrage, arrêt ou redémarrage de daemon/composant/application. Scripts d’installation, signature, désinstallation et cycle de vie seulement lus. Aucun make install.',
 'Aucun profil CPU/mémoire ni benchmark de latence. Les coûts algorithmiques sont établis par les boucles et leurs appelants, sans revendication de durée observée.',
 'Aucun scan externe CVE, audit exhaustif du code de TOMLKit ni scan complet des secrets dans l’historique Git. Permissions réelles du HOME, précréation de chemins et protections système contre les liens symboliques non certifiées.',
 'Les 96 fichiers Swift de production sont lus intégralement. Tests, scripts, documentation, specs et ressources sont contrôlés selon les risques. Aucun taux instrumenté de couverture de tests, mutation testing ou taux global de duplication calculé.',
 'La course interprocessus de REL-046 et le démarrage lent de REL-050 n’ont pas été reproduits ; ils restent plausibles.',
 'Le pointeur audits/latest et les artefacts des audits précédents restent inchangés, conformément au périmètre d’écriture autorisé.',
 'Les exemples de correction du rapport n’ont pas été appliqués ni compilés. Seules les sondes de comportement courant ont été compilées et exécutées.',
]
write('validation/results.json',{'exit_code':0,'build':'succeeded via swift test','swift_tests':1112,'safe_t6_tests':4,'distinct_swift_tests':1116,'excluded_tests':47,'pure_probes':4,'pure_probes_exit_code':0,'warnings':['internal redondant dans une extension private : Sources/RoadieDaemon/DaemonSnapshot.swift:2193','SwiftPM : option --skip-update dépréciée'],'limitations':limitations})
manifest=read('manifest.json');manifest['audit_meta']['parallelism_note']='Six lectures thématiques Sonnet, compléments par six réviseurs natifs, consolidation et trois contre-audits indépendants. Aucun agent ne modifie le code audité.';write('manifest.json',manifest)
