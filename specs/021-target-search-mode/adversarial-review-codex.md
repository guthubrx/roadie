# Contre-revue adverse - 021-target-search-mode

- **Agent** : sous-agent T3 Codex, GPT-6.1-Sol (effort medium), fournisseur OpenAI, `runtimeMode: auto`

## Round 1 (plan) - 2026-10-13

**Verdict** : APPROVE_WITH_CHANGES

| Objection | Vérifiée comment | Retenue | Raison |
|---|---|---|---|
| `kEventHotKeyExclusive` requis pour échouer sur conflit | lecture CarbonEvents.h | oui | option ajoutée |
| Fil principal, cycle de vie lié au mode lettres, flags `enabled`/`overlay_enabled` | lecture `roadied/main.swift:198` | oui | démarrage/arrêt avec le composant |
| Règle caractère → touche, masque `NoDeadKeysMask`, `deadKeyState`, `LMGetKbdType` | doc UCKeyTranslate | oui | appliqué |
| Changement de disposition non détecté | lecture du plan | oui | comparaison du code résolu toutes les 2 s |
| Contradiction config invalide / dernière config valide | `ConfigReloadService.swift:108` | oui | spec alignée sur l'existant |
| Double Retour : figer la cible, répétition, Échap, frappe pendant l'attente | lecture | oui | défini dans research |
| Réactivation par label après nouvelle liste | `TargetHintService.swift:368` | oui | activation de la cible figée (`perform`) |
| Texte des enfants trop étroit, `title` modifié | lecture | oui | `searchText` distinct, tous candidats web sans candidat descendant |
| Décodeur actuel inadapté (ponctuation, Tab, modificateurs) | `TargetOverlayPresenter.swift:692` | oui | `SearchKeyInput` dédié |
| Touches mortes / IME | doc NSTextInputClient | partiel | ignorées (accents non significatifs) ; limite annoncée |
| Barre sur l'écran actif, visible sans correspondance | lecture | oui | écran du pointeur |
| Classement non demandé | lecture | non | gardé : deux partitions O(n), utilité directe, pratique Homerow |
| Options de session (source, max, délai) | `TargetModeRuntimeController.swift:122` | oui | toutes sources, 500, 60 s |
