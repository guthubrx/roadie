# Session 047 - Fenêtre flottante dans sa stage

Date : 18 octobre 2026. Demande explicite après comparaison avec TrellisWM.
Branche : session-047-fenetre-flottante. Specs : specs/047-fenetre-flottante/.

`roadie toggle floating` fait flotter la fenêtre active dans sa stage, puis la
remet au tuilage. Réutilise l'épinglage : nouvelle portée `stage`, écrite de façon
lisible par les versions antérieures. Menu « Fenêtre » de la barre de titre aligné.
Commande routée vers le daemon. Guides FR/EN, CLI et changelog alignés.

1 707 tests / 200 suites réussis ; deux tests instables préexistants documentés.
Revue indépendante APPROVE_WITH_CHANGES traitée. Release installée : UUID
7DE5FFC6-67B3-3CD2-A7B3-3C4CB9A1694E, PID 64518, quatre contrôles santé OK.
Aller-retour réel vérifié sur Firefox. Détails : specs/047-fenetre-flottante/validation.md.
