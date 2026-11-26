# Spec 170 — Profils matériels d’écrans automatiques & Export/Import portable

## Contexte & Problème
1. Sur un Mac portable branché alternativement sur un grand écran de bureau, un vidéoprojecteur ou utilisé seul, les proportions souhaitées (`default_strategy`, marges, largeur de colonne `scrolling`, projet de travail) varient selon la topologie d’écrans.
2. Migrer ou sauvegarder sa configuration Roadie complète vers un autre Mac ne se résume pas à copier `roadies.toml` : les projets de stages, abréviations du lanceur et profils d’écrans doivent pouvoir être exportés/importés proprement sans exposer de secrets ni coller d’UUIDs locaux.

## Exigences fonctionnelles
- **FR-001 (Interrupteur dédié, désactivé par défaut)** : Réglage `tiling.display_profiles_enabled` (`Bool`, défaut `false`). Tant qu’il est `false`, aucun basculement automatique de profil matériel n’a lieu (coût zéro).
- **FR-002 (Signature topologique portable)** : `DisplayTopologySignature` identifie une configuration d’écrans par le nombre d’écrans et leurs résolutions logiques triées (`1800x1169+3840x2160`), indépendamment des UUID matériels.
- **FR-003 (Protection des modifications récentes)** : Le rappel automatique d’un profil matériel n’écrase jamais un changement manuel effectué dans les 60 dernières secondes (`shouldAutoApply`).
- **FR-004 (Export/Import portable & sûr)** : `roadie config export [PATH]` génère un bundle JSON versionné embarquant `roadies.toml` (chemins normalisés avec `~`), les projets, abréviations et profils d’écrans — en excluant strictement `clipboard.json`, `events.jsonl`, `stages.json` et captures privées. `roadie config import <PATH> [--dry-run] [--force]` valide le bundle avant toute écriture et sauvegarde le fichier courant avant modification.
- **FR-005 (CLI profils)** : `roadie profile list|save <NOM>|apply <NOM>|delete <NOM> [--json]`.
