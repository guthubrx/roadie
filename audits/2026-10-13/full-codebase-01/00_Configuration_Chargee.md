# Configuration Audit v14.0

- AUDIT_ROOT_PATH : "/Users/moi/Nextcloud/10.Scripts/39.roadie"
- AUDIT_SCOPE : "/Users/moi/Nextcloud/10.Scripts/39.roadie"
- SESSION_DATE : "2026-10-13"
- SESSION_ID : "full-codebase-01"
- SESSION_DIR : "/Users/moi/Nextcloud/10.Scripts/39.roadie/audits/2026-10-13/full-codebase-01"
- SCOPE_MODE : "full"
- DIFF_BASE : "ignored"
- AUDIT_MODE : "readonly"
- AUDIT_GRID : "all"
- MODULES_ACTIFS : ["00", "01", "02", "03", "04", "05", "06", "07", "08", "10", "11", "12"]
- MAX_CYCLES : 1
- MAX_FIXES_PER_CYCLE : 10
- MAX_RETRY_PER_FINDING : 2
- AUTO_COMMIT : false
- SKIP_HOOKS : false
- SAMPLING_THRESHOLD : 500
- SAMPLING_DAYS : 90
- SAMPLING_KEYWORDS : ["auth", "login", "crypto", "password", "secret", "token", "payment", "admin", "upload", "exec"]
- MIN_SAMPLE_SIZE : 50
- OUTPUT_FORMATS : ["json", "md"]
- GENERATE_DASHBOARD : false
- INCLUDE_EVIDENCE_SNIPPETS : true
- BASELINE_PATH : "/Users/moi/Nextcloud/10.Scripts/39.roadie/audits/baseline.json"
- SEVERITY_DEFAULTS : {"CRITICAL": {"sla_hours": 24, "block_release": true}, "HIGH": {"sla_hours": 168, "block_release": true}, "MEDIUM": {"sla_hours": 720, "block_release": false}, "LOW": {"sla_hours": null, "block_release": false}}
- DUPLICATION_THRESHOLDS : {"global_warn_pct": 5, "global_crit_pct": 10, "block_warn_lines": 100, "block_crit_lines": 200}
- COMPLEXITY_THRESHOLDS : {"function_warn": 15, "function_crit": 25, "function_max_lines": 50}
- PERF_BUDGETS : {"lcp_ms": 2500, "inp_ms": 200, "cls": 0.1, "bundle_initial_kb": 200, "bundle_total_kb": 1000}
- MODE_PARALLELISME : "agents"
- MODELE_SUBAGENTS : "inherit"
- MAX_FINDINGS_PER_DOMAIN : 50
- EXCLUDE_PATHS : ["node_modules/**", ".venv/**", "dist/**", "build/**", ".build/**", "__pycache__/**", ".git/**", "vendor/**", ".next/**", "target/**", "*.min.js", "*.bundle.js", "coverage/**", ".audit-sessions/**", "audits/**", ".worktrees/**"]
- EXCLUDE_LANGUAGES : []

Contraintes prioritaires : aucune correction, aucun commit/push/branche, aucun processus arrêté ou relancé. Toutes les écritures sont confinées à /Users/moi/Nextcloud/10.Scripts/39.roadie/audits/2026-10-13/full-codebase-01. La phase 09 ne s’applique pas. Le modèle des sous-audits est hérité.
