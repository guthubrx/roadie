# Livraison 033 — 2026-10-15

Installée et redémarrée. UUID compilé et installé identique :
90AF0C93-3F33-3EA9-838C-1613EAB1DC33. Signature stricte valide ; certificat conservé :
78a75e8032f190a20072eb91cc2919aac344ef78.
Ancien PID 24397 ; nouveau PID 34131. Quatre contrôles santé OK après rechargement.
Les neuf fenêtres communes gardent leur groupe. Les 46 fichiers suivis dans le
worktree parallèle sont inchangés.

## Réglages et captures

Légende : 14 points, écart 4 points, opacité 0,90, centrée sous la vignette.
Hauteur des emplacements : 112 points ; écart entre emplacements conservé à 13.
Taille des autres détails : 28 points, inchangée. Police et couleurs des stages conservées.
Les emplacements vides restent présents, avec un repère seulement pendant la révélation.

Texte droit par défaut. Le mode avec perspective a aussi été activé et inspecté sur
les deux écrans, puis désactivé. Les captures après expiration montrent la disparition
complète des noms et des repères vides. Durée 5 secondes, fondu 0,35 seconde conservés.
Double Alt droit : noms ; double Alt gauche : grille. Aucun raccourci modifié.

Captures locales, non versionnées :
/private/tmp/roadie033-straight-internal.rail.png
/private/tmp/roadie033-straight-external.rail.png
/private/tmp/roadie033-perspective-internal.rail.png
/private/tmp/roadie033-perspective-external.rail.png
/private/tmp/roadie033-expired-internal.rail.png
/private/tmp/roadie033-expired-external.rail.png

## Dépôt Outlook

Le test du geste complet reproduit le retour au bas gauche en présence d'un ancien
signal de fermeture. Sans la confirmation du placement, il échoue sur 27 assertions,
avec deux dépôts annoncés acceptés malgré le retour à l'ancienne disposition.

Avec le correctif, les deux dépôts successifs passent, avec et sans ancien signal.
Le test valide l'aperçu, Outlook sous Teams, le cadre de Teams réduit, T3 dans sa
colonne entière, puis trois cycles de maintien après chaque dépôt. Les tests de
commande vérifient également qu'une fermeture ultérieure reste effective.

Le journal historique ne précise pas la cible de chaque aperçu ni l'identifiant de
chaque notification AX détruite. Le diagnostic est une déduction soutenue par
l'état concret et la reproduction. Le geste est rejoué par les contrôleurs réels
dans un environnement de test isolé. Aucun glisser physique sur les applications
de l'utilisateur n'est revendiqué. La disposition actuelle ne conditionne pas la
validation de cette régression.

## Sources reproductibles

Suite isolée initiale : 1 482 tests. Nouveau test de geste isolé : deux cas réussis.
Suite combinée complète : 1 550 tests dans 168 suites, avec `swift test --no-parallel`.
Les tests IPC ne sont ni désactivés ni assouplis ; le mode concurrent sous Swift
Testing provoque un délai dépassé pendant les balayages AppKit (voir implementation.md).

Le patch delivery.patch est relatif à la base 893c5fc6, identifiant complet dans
le manifeste. Il réunit les corrections déjà installées et la session 033.
Les 263 empreintes Sources/Tests du manifeste ont été vérifiées en appliquant le
patch à un index Git isolé. Ne pas installer le seul main tant que le travail
parallèle déjà utilisé n'y est pas intégré.

Le complément ajoute uniquement un test. Toutes les sources de production restent
identiques à celles de l'application installée. UUID, signature et quatre contrôles
santé ont été revérifiés ; aucune réinstallation n'est nécessaire.

Copie de compilation : /private/tmp/roadie031-livraison
Sauvegarde de l'application, du CLI, de la configuration et de l'état précédents :
/private/tmp/roadie033-before-install
Incident brut local : /private/tmp/roadie033-incident
Application active : /Users/moi/Applications/Roadie.app
Configuration active : /Users/moi/.config/roadies/roadies.toml
Artefacts durables :
/Users/moi/Nextcloud/10.Scripts/39.roadie/specs/033-legendes-compactes/validation
