# Contexte et périmètre figé — consolidation 155

Actifs : configuration locale, fenêtres et autorisation Accessibilité, identité du build,
code publié et notices de licence. Acteur principal : utilisateur local. Entrées : TOML,
réponses AX, commande CLI et JSON public GitHub. Aucun service HTTP entrant ajouté.

Invariants examinés : anciennes configurations lisibles, nouveau chemin prioritaire par
clé, reset retire les deux valeurs, pas d'écriture globale TOML ni d'appel réseau daemon,
code HTTP contrôlé, délai request 5 s / attente 6 s, résultat partagé verrouillé, session
éphémère invalidée. Identité Git injectée par arguments quotés ; suffixe dirty inclut les
fichiers non suivis. Certificat installé conservé par procédure existante, preuve runtime
à la livraison. Aucune dépense, CI workflow_dispatch seule, contents:read et checkout épinglé.

Lecture : Config.swift (racine, TargetModeConfig, catalogue, chargeur et validateur),
ConfigFileEditor (scanner, lectures, édition scalaire/structurée), SettingsService (validation,
fichier candidat, écriture atomique et reset), SettingsCollectionCodec, CLICommandRouter
(dispatch et isDaemonRouted), CommandSocketClient et Sources/roadie/main.swift ;
ReleaseCheck complet, DaemonHealth/RoadieVersion, deux gardes AX, scripts de bundle/install/DMG,
coverage, outils de recette et tests modifiés. Déplacement ReplayableSnapshotProvider
comparé octet pour octet à la base. Les autres mécanismes de placement ne sont pas réaudités.

Contrôles déjà observés : 26 tests ciblés de 155 ; 29 scripts ; sept tests alias et édition,
plus huit tests après correctif de préservation du commentaire scalaire. Couverture mesurée
sur les lots préparés : 71,30 % lignes (2533 tests) ; pas de mesure inventée sur le dernier code.
Une exécution complète 2549 tests a trouvé le test intermittent 151 documenté avant cette
reprise. Recontrôle isolé puis suite complète requis, aucun échec ignoré pour livrer.

Hors de ce gate code : publication GitHub, installation et vérification du runtime de 0.14.0,
qui constituent T053. Les preuves de ces opérations seront produites à la livraison.
Pas de nouvelle interface graphique, pas de SLA de latence revendiqué. Les outils statiques
ne couvrent pas la logique Swift : revue manuelle et compilation sont complémentaires.
