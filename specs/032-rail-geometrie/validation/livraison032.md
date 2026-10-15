# Livraison 032 — 2026-10-15

Correction installée et redémarrage vérifié. UUID compilé et installé identique :
2133EE29-4924-31D5-B827-CCF5581B0F1E. Signature stricte valide, même certificat stable.
Ancien PID 21035 ; nouveau PID 24397. Quatre contrôles santé OK.
Les dix fenêtres suivies conservent leur scope. Les 46 fichiers modifiés ou nouveaux
sur le worktree parallèle sont inchangés, vérifiés par SHA256.

Hauteur installée : 120 points, contre 184 auparavant avec la police courante.
Écart entre emplacements conservé : 13 points. Distance entre centres : 133 points.
Les emplacements nommés vides gardent leur rang et leur hauteur.

Captures des deux écrans inspectées : vignettes avant alignées, espace réduit,
nom et numéro visibles pendant la révélation, disparition des noms et des repères
vides après cinq secondes. Les raccourcis et les tailles de police sont conservés.

Les essais AppKit vérifient le rang de dépôt, le trait d'insertion, sa disparition
hors du rail et son nettoyage. Aucun glisser physique n'a été simulé.

## Reproduction de la version installée

Le manifeste donne les empreintes de tous les fichiers Sources et Tests compilés.
Le patch delivery.patch est relatif au commit 893c5fc6 (identifiant complet dans le
manifeste). Il réunit le travail parallèle déjà installé et la correction 032.
Appliquer ce patch sur une copie propre de cette base reproduit les sources livrées.
Ne pas installer uniquement la branche 032 tant que le travail parallèle n'est pas
intégré : cela retirerait des corrections déjà utilisées.

Copie de compilation : /private/tmp/roadie031-livraison
Sauvegarde de l'application, du CLI, de la configuration et de l'état précédents :
/private/tmp/roadie032-before-install
Configuration active : /Users/moi/.config/roadies/roadies.toml
Application active : /Users/moi/Applications/Roadie.app

Captures locales, non versionnées :
/private/tmp/roadie032-before-internal.rail.png
/private/tmp/roadie032-before-external.rail.png
/private/tmp/roadie032-after-internal.rail.png
/private/tmp/roadie032-after-external.rail.png
/private/tmp/roadie032-labels-internal.rail.png
/private/tmp/roadie032-labels-external.rail.png
/private/tmp/roadie032-expired-internal.rail.png
/private/tmp/roadie032-expired-external.rail.png

Les artefacts durables sont dans :
/Users/moi/Nextcloud/10.Scripts/39.roadie/specs/032-rail-geometrie/validation
