# Session 046 - Placement sur l'écran actif par défaut

Date : 18 octobre 2026. Demande explicite après essai utilisateur confirmé.
Branche : session-046-placement-ecran-actif. Specs : specs/046-placement-ecran-actif/.

Défaut focused_display aligné entre constructeur, décodeur, catalogue et exemple.
Les choix explicites restent conservés. Libellés français et aide dans Tuilage ;
guides, README et changelog FR/EN alignés. Sans écran actif connu, repli d'abord
sur l'écran de la fenêtre. Aucun délai ni algorithme de tuilage modifié.

1 696 tests / 199 suites réussis ; revue indépendante sans défaut bloquant,
notes traitées. Deux fixtures AX précisent désormais leur choix macos. Le test
de signal distribué passe isolément puis en suite complète après un dépassement
d'attente sous charge. Aucune modification de ce test ni de son délai.

Release installée et redémarrée : UUID 4203C4C0-E22C-3F80-BC7E-4A624E9C0A13,
PID 76046, quatre contrôles santé OK. Configuration et signature conservées.
Défaut et choix explicite vérifiés avec la CLI installée. Essai réel préalable
du même mécanisme confirmé par l'utilisateur ; nouveau panneau non capturé,
bureau inaccessible. Détails dans specs/046-placement-ecran-actif/validation.md.

Correction 597314cc intégrée et poussée sur main. Branche de session supprimée,
fichiers de compilation et recette temporaire retirés. Worktree lié à la
conversation conservé détaché, diagnostics conservés hors Git.
