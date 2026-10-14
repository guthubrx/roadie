# Diagnostic et réutilisation — session 027

## Baseline avant correction

- SettingsViewModel.editText applique seulement les clés font_size ; les autres
  champs attendent commitDraft via Retour ou perte du focus.
- SettingsService valide un candidat, sauvegarde, remplace par rename, recharge
  la configuration puis publie roadieSettingsDidChange avec seulement configPath.
- startTilerComponent écoute AX, les bureaux, écrans et réveils ; il n'écoute pas
  directement cette notification de paramètres.
- Les douze entrées non scalaires du catalogue sont affichées en lecture seule
  avec un bouton d'ouverture du fichier. Six sont de simples listes.
- ConfigFileEditor préserve les lignes et commentaires des scalaires. Ses lectures
  de valeurs brutes et tableaux de tables peuvent aider l'édition structurée.
- TOMLKit est déjà une dépendance de RoadieCore ; réutiliser son analyse existante.
- La configuration réelle comporte des marges par côté et une exception par écran.
  Une marge locale peut donc conserver sa priorité après un changement général.
- TargetOverlayStyle et SearchBarRenderer suivent déjà les tailles en place ;
  ajouter les familles au même circuit de mise à jour.
- Pas de changement de configuration réelle pour les tests : fixtures temporaires.
- TOMLKit ne conserve pas les commentaires : lecture et validation par DOM,
  écriture ciblée par lignes. Les commentaires d'une liste multiligne sont conservés.
- Le rail attend des blocs canoniques pour les accents par stage ; la sortie doit
  rester compatible avec son lecteur existant.
- Les signaux hooks sont une structure connue non exécutée actuellement ;
  son éditeur le signale, sans ajouter un nouvel exécuteur.
- Un pas de marge de 1 point peut être absorbé par la tolérance AX de 2 points.
  L'application explicite de paramètres doit disposer d'une précision temporaire,
  sans modifier la tolérance des événements AX ordinaires.

## Résolution mise en œuvre

- Les champs scalaires appliquent leurs valeurs valides pendant la saisie. Les
  brouillons incomplets ou invalides gardent la dernière configuration valide.
  `hasDrafts` distingue les brouillons non appliqués des valeurs déjà sauvegardées.
  Une valeur déjà sauvegardée ne réécrit pas une modification externe lors du
  retour du focus. Les critères connus vides sont conservés si un autre champ change.
  Les collections apparaissent dans les catégories normales des paramètres.
- La validation sémantique vérifie le fichier principal et les fragments générés.
  Le chemin logique reste la référence pour leurs chemins associés, y compris
  lorsque la configuration est accessible par un lien symbolique.
- Les notifications identifient le fichier et le réglage modifiés. Le contrôleur
  d'application compare les domaines concernés, résout les liens symboliques et
  ignore les fichiers autres que la configuration active.
- La première revue a révélé qu'un signal local ne traverse pas les processus
  modulaires. Le circuit écoute désormais le signal local et le signal distribué.
  La comparaison des domaines rend leur réception doublée idempotente.
- TickScheduler regroupe les demandes de disposition. Une modification limitée
  aux polices ne provoque pas de retuilage, même dans une édition complète `*`.
- Le diagnostic d'une première écriture ignorée a confirmé une fausse réussite :
  le résultat comptait une application alors que le cadre restait à une marge de
  6 points, au lieu des 7 demandés. La tolérance ordinaire masquait cet écart.
  L'application explicite suit désormais la preuve du cadre réel par fenêtre.
  Un écart ou un résultat inconnu permet une seule reprise après 0,1 s, via
  l'échéance existante du planificateur. Un cadre déjà arrivé à la cible évite cette
  écriture. Un vrai cadre contraint conserve le traitement existant des refus.
- Une commande filtrée par une garde ou un budget n'est pas une application.
  Les cibles calculées avant ce filtrage permettent de conserver la précision en
  attente sans consommer une tentative. Un scope inactif conserve ses intents et
  son échéance de reprise jusqu'à sa réactivation. Les gestes, suspensions et
  transitions gardent leurs protections. La tolérance AX ordinaire reste à 2 points.
- Les quatre variantes BSP/BSP spatial × stage actif vide/zoomé ont confirmé une
  échéance de reprise passée persistante sur une seconde de ticks de 15 ms.
  Le réveil exige maintenant un scope actif avec une fenêtre candidate et exclut
  le zoom ordinaire ou natif. La demande et sa borne restent conservées pour le
  retour d'une fenêtre ou la sortie du zoom. Le zoom réservant le rail reste autorisé.
  Les cibles de la passe ne suffisent pas à déterminer si le réveil doit rester
  armé : elles sont volontairement absentes pendant l'attente de son échéance.
- Une modification de géométrie ne remet plus à zéro la priorité et l'échéance
  du redimensionnement manuel. La précision explicite reste en attente pendant
  sa grâce de 0,35 s, puis est évaluée selon le résultat réel de l'application.
- Les intents non zoomés sont invalidés pour une nouvelle géométrie. Les arbres et
  les choix de zoom restent conservés. Le zoom réservant le rail recalcule son
  conteneur ; le plein écran ordinaire continue de couvrir sa zone plein écran.
- Les noms configurés de stages étaient seulement des valeurs initiales. Une
  modification explicite compare maintenant les anciennes et nouvelles définitions
  par identifiant, puis renomme les stages existants dans une transaction contrôlée.
  Les définitions inchangées gardent les noms personnalisés. Supprimer ou réidentifier
  une définition ne supprime pas ses stages, membres ou affectations.
- Les familles de police Caps+F suivent le circuit existant des styles actualisés
  en place. Le sélecteur utilise les polices installées et conserve un secours système.
- Les actions de règles `layout` et `gap_override` sont enregistrées mais ne
  modifient pas la géométrie. L'aide de l'éditeur expose cette limite.

## État de vérification

La suite complète finale a passé 1 440 tests Swift, dans 154 suites, en 6,943 s.
Le résultat figure dans `/private/tmp/roadie-027-final-tests.log`.
Elle inclut une publication IPC par un véritable processus enfant JXA et la garde
de redimensionnement de 0,35 s. Elle vérifie aussi la reprise bornée, l'attente des
gardes et du budget, les scopes inactifs, les conflits après saisie sauvegardée,
les fragments générés via lien symbolique et les critères connus vides.
Vingt rendus hors écran ont été actualisés et
inspectés, notamment à 760 px de largeur et avec des polices de 24 points.

Les constats de niveau élevé et moyen de la première revue 027-1 sont corrigés.
La quatrième revue 027-4 confirme les corrections précédentes. Le scénario de
transition demandé a été reproduit avant correction dans les quatre variantes.
Après correction, les 12 tests runtime ciblés passent dans une suite, en 0,477 s.
Journaux : `/private/tmp/roadie-027-retry-transition-red.log` et
`/private/tmp/roadie-027-retry-transition-green.log`.
La suite complète finale inclut ce dernier correctif et passe.

L'installation finale et `make restart` ont réussi.
Le daemon est actif sous le PID 47508 depuis le 14 octobre 2026 à 04:25:59 UTC.
Les quatre contrôles de santé sont OK. Les autorisations Accessibilité et capture
d'écran sont accordées et la configuration est valide. Le certificat est conservé,
empreinte SHA `78a75e8032f190a20072eb91cc2919aac344ef78`.
Cette installation inclut le dernier correctif de transition et sa santé est
vérifiée. L'utilisateur confirme « Oui, tout fonctionne » pour les espacements
sans Retour, les éditeurs et les polices Caps+F immédiates avec une saisie fluide.
