# Livraison de la session 031

Date : 2026-10-15. Correction installée et redémarrée.

- Tests ciblés : 20 réussis. Suite combinée : 1 539 tests dans 165 suites.
- L'ancien badge produit 20 écarts dans le test de rendu avant son retrait.
- UUID compilé et installé : 9D135F82-6211-33BD-9F12-A2D9767C47F5.
- Signature stricte valide, certificat stable : 78a75e8032f190a20072eb91cc2919aac344ef78.
- Ancien PID 60128, nouveau PID 2722. Quatre contrôles santé OK.
- Cinq fenêtres conservent leur scope. Rail : trois stages. Démarrage : deux
  placements, aucun échec, layout stable après 162 ms.
- Captures réelles : aucun numéro au repos ; « 1 — Work », « 2 — Com »,
  « 3 — Perso » après révélation ; disparition après cinq secondes et le fondu.
- L'action du trigger BTT gauche ouvre une grille de neuf cellules sur l'écran.
  Le journal confirme scope=display. Aucun clic ou déplacement n'est exécuté.
- Le trigger BTT droit de grille est désactivé avec les deux indicateurs à zéro.
  Le profil Karabiner sélectionné conserve le double appui droit pour les noms.

Les actions sont testées par les commandes configurées et l'API BTT.
Les doubles appuis physiques ne sont pas simulés. La capture différée via BTT
a renvoyé un délai dépassé après cinq secondes ; les deux images attendues
ont néanmoins été écrites et inspectées. Les captures suivantes utilisent
une action courte.

Le worktree parallèle est inchangé, vérifié par empreintes avant installation.
Son code installé est combiné avec les corrections 030 et 031 dans une copie
de livraison. Seuls le dessin du badge, sa hauteur réservée et son ancien test
sont remplacés. Le patch ciblé passe git apply --check sur la version parallèle.

Copie de livraison : /private/tmp/roadie031-livraison

Sauvegarde de l'application précédente, de l'état et du patch combiné :
/private/tmp/roadie031-before-install

Sauvegarde cohérente BTT et copie Karabiner :
/Users/moi/Library/Application Support/BetterTouchTool/backup-roadie031-20261015-073307

Captures : /private/tmp/roadie031-screen-before.png,
/private/tmp/roadie031-screen-after-rest.png,
/private/tmp/roadie031-screen-labels.png,
/private/tmp/roadie031-screen-expired.png,
/private/tmp/roadie031-screen-grid-active.png.

Logs : /private/tmp/roadie031-old-badge-repro.log,
/private/tmp/roadie031-combined-targeted.log,
/private/tmp/roadie031-combined-full.log,
/private/tmp/roadie031-install.log.
