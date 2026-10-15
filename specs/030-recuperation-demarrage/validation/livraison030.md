# Livraison de la session 030 — 2026-10-15

- Correction : a7079c02. Test du relevé unique : 5e03788.
- Tests de non-régression : 5. Suite isolée : 1471 succès.
- Version combinée avec le rail déjà installé : 1527 succès dans 163 suites.
- Installation Release signée avec la même identité roadied-cert.
- UUID du binaire installé et du binaire compilé : D89DCA82-9439-3864-9344-0284FCFD8C07.
- Arrêt propre puis bootstrap du LaunchAgent : PID 53846 remplacé par 37751.
- Santé après redémarrage : quatre contrôles OK, Accessibilité conservée.
- Quatre fenêtres candidates gardent leur groupe ; aucune fenêtre candidate sans scope.
- Navrail : trois groupes. Première application : trois placements, zéro échec, un relevé.

Le cas « écran externe absent au démarrage » et l'arrivée tardive sont reproduits
par tests déterministes du vrai LayoutMaintainer. Le redémarrage réel vérifie
la version installée et la conservation des groupes ; il ne simule pas un
nouveau débranchement physique.

La livraison conserve aussi les changements 029-resize-rail déjà installés.
Ils ont été combinés dans /private/tmp/roadie030-livraison, sans modifier le
dossier de travail de cette autre session. L'instantané et la sauvegarde de
l'application précédente sont conservés dans /private/tmp/roadie030-before-install.
Le correctif Git 030 reste indépendant de ces changements.
