# Découverte du dépôt

Périmètre : /Users/moi/Nextcloud/10.Scripts/39.roadie

Mode S, lecture complète de 96 fichiers de production Swift (38 217 lignes). Inventaire global : 193 fichiers source/scripts/tests. Swift 6, SwiftPM, macOS 14+, AppKit/SwiftUI, AX et Carbon. JSON persistant, aucun serveur web ni service LLM intégré. Aucun pipeline CI du dépôt détecté.

## Chemins fréquents

- Notification AX → TickScheduler → LayoutMaintainer → writes AX
- CLI → socket Unix → MainActor → mutations persistantes
- snapshot/reconcile → plan/invariant géométrique
- Hyper+F → scan AX concurrent → modèle et overlay MainActor
- Activation cible → focus AX → injection CGEvent
- Rail et glisser → sélection écran/stage → géométrie
- Modification config → validation/rechargement
- Changement écran → parking/restauration
- Macros → capture/replay
- Journaux → rotation/abonnement

## Modèle de menace

{
  "assets": [
    "fenêtres/focus/clavier/souris utilisateur",
    "associations persistantes et signets",
    "configuration",
    "titres de fenêtres et journaux"
  ],
  "attackers": [
    "processus local du même utilisateur",
    "commande shell erronée",
    "application Accessibility lente ou incohérente"
  ],
  "surfaces": [
    "socket Unix privé",
    "arguments CLI",
    "TOML/JSON sur disque",
    "réponses AX",
    "événements Carbon/CGEvent"
  ],
  "non_applicable": [
    "service HTTP public",
    "authentification web",
    "paiements",
    "base SQL",
    "service LLM embarqué"
  ]
}

## Vérification croisée

Tous les HIGH ont été soumis à un lecteur distinct en posture de réfutation. Les preuves sont dans /Users/moi/Nextcloud/10.Scripts/39.roadie/audits/2026-10-13/full-codebase-01/counter-audit.json et /Users/moi/Nextcloud/10.Scripts/39.roadie/audits/2026-10-13/full-codebase-01/counter-runtime-perf.json. Les sources associées ont été relues intégralement.

Mémoire projet absente dans /Users/moi/.Codex/projects. Constitution globale et pont projet lus. Les specs 018/020/021 et les ADR pertinents servent de contexte, sans restreindre le périmètre à la dernière session.
