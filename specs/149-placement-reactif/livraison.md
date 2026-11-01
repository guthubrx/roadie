# Livraison 149 — 1 novembre 2026

## Résultat actif
Les anomalies confirmées du placement différé, de l’acquisition de la barre, des relevés périodiques, des callbacks de cadre, de la sauvegarde périodique et de la capture clavier sont corrigées. Les trois revues ont été traitées ; les limites techniques restent explicites dans validation.md et revue.md.

Source fonctionnelle :901ed35df81384b783f5a30ff980fc4b7ec78c40, intégrée par avance rapide dans main et vérifiée sur origin/main. Commits précédents de la correction :d2a1cd556319717804903db01243687b3f0e6b24, a5be1985f4eb904a7c09ba3437bd45771dbf42f7, 970cdab59ff1d97bb5885942ab8986ab1a767fe5. Le commit de clôture ajoute uniquement ce reçu et le statut de session.

Application signée installée et chargée : /Users/moi/Applications/Roadie.app/Contents/MacOS/roadied. CLI : /Users/moi/.local/bin/roadie. UUID723B2205-C1F6-3EC2-9F63-E747FE9992CA, PID27444. Certificat78a75e8032f190a20072eb91cc2919aac344ef78 conservé. Configuration /Users/moi/.config/roadies/roadies.toml byte à byte inchangée. Les529empreintes Sources/Tests de la compilation sont identiques à celles de la source livrée.

## Vérification
- 2459tests dans372suites réussis en75,767s, mode séquentiel et HOME isolé. Les28tests de scripts ont réussi ; leur source est inchangée.
- Cinq contrôles de santé verts après activation, après essais et après nettoyage. Un seul daemon propriétaire du verrou ; le second processus est son watcher de restauration.
- Huit sessions de barre sur la dernière activation : premier dessin134–270ms, pauses16–83ms. Deux sessions ont une durée plus courte ; elles ne sont pas revendiquées comme des parcours physiques complets.
- Trois réponses lentes complètes d’une application fictive : pauses73,83,63ms, contre579,517,544ms avant. Pas de passe supérieure à400ms dans cette série. Aucun gain universel déduit ; les pics des séries intermédiaires sont conservés.
- Un refus de hauteur de la fenêtre fictive est journalisé par le chemin différé corrigé, puis accepté sans boucle. Aucune application utilisateur suspendue ou arrêtée.
- Aucun nouveau rapport de crash depuis le chargement du correctif clavier. Le rapport12h55 antérieur est conservé. Application fictive et pilote fermés, PID absents, focus rendu à T3 Code.

## Preuves et limites
Diaporama autonome vérifié dans /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/025-settings-readability/preuves-corrections/2026-11-01-149-placement-reactif/preuves.html. Capture native fictive, navigation et lecture/pause vérifiées.
Preuves incomplètes : les parcours utilisent les commandes Roadie existantes ; le clavier physique et les clics ne sont pas enregistrés. CUA ne dispose d’aucune surface et le pilote n’a pas les autorisations PostEvent/Accessibility. Aucun droit modifié, aucune coordonnée ou frappe inventée.
Un appel AX déjà parti n’est pas physiquement interruptible ; son résultat annulé est rejeté. Quelques acquisitions initiales et commandes explicites restent synchrones. Des rejets répétés peuvent retarder la prochaine tentative de2s. Ces limites ne sont pas présentées comme corrigées.

## Nettoyage effectué
Après vérification de la source distante et du fonctionnement actif :
- Branche locale148 intégrée supprimée ; aucune branche distante148 n’existait.
- Cache de compilation /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/025-settings-readability/.build supprimé après contrôle du checkout de dépendance propre et absence de fichier ouvert. Symboles dSYM de la version active conservés hors Git.
- Applications et binaire du pilote temporaires retirés avec /private/tmp/roadie149.126fichiers originaux archivés et vérifiés par empreinte avant retrait. Aucun processus du pilote ni compilateur actif.
- Ancien retour arrière147 contenu dans /Users/moi/.local/state/roadies/validation/2026-11-01-148/rollback retiré. Le retour arrière148 sain de cette livraison est conservé.
- Total des fichiers retirés :1513981853octets, dont1,44Go de compilation. Le reçu détaillé est hors Git.

Conservés : worktree actif de ce fil et branche149, checkout main, exécutables installés, retour arrière utile, symboles et originaux de preuve. La stash historique non intégrée reste intacte.
Les trois worktrees distants des revues Bridget sont propres, résultats acquittés, continuable=false, mais retention=review_required. Aucun outil de retrait de ces dossiers n’est exposé. Ils sont conservés ; aucun retrait forcé ni nouvelle mission de remplacement.

Archive locale : /Users/moi/.local/state/roadies/validation/2026-11-01-149. Les données brutes, les manifestes et le rapport de crash restent hors Git. Seuls les sources, tests, décisions, documents et le diaporama autonome sont publiés.
