# Validation146 — en cours

Avant : utilisateur iTerm2 id494130 ; activation observée sans placement, safety suivant et animation300,5ms. Reproduction dédiée avec commande native iTerm et contenu fictif : premier essai8cadresCG distincts ; second6cadres,541ms entre première surface et cadre final. Captures initiale/finale du second essai ; aucune fenêtre utilisateur fermée. Les deux fenêtres fictives iTerm se sont terminées à la fin de leur commande de test15s ; terminal494130 conservé.

Tests :40ciblés/7suites réussis ;2425tests/363suites en82,456s. Premier test de cible directe réellement rouge avant la garde ; reprises de découverte rouges avant compteur. Une erreur de compilation d’accès exclusif Swift a été résolue par copie de Pending, sans changement du mécanisme. Suite scripts28tests réussis en15,577s. Revue Bridget non admise, voir review.md ; aucune revue indépendante positive affirmée.

Limites : le premier cadre macOS natif peut précéder la notificationAX. Le writerAX existant conserve ses phases taille/position/taille, donc ces attributs ne sont pas atomiques côté application. Aucun changement de ses gardes ni promesse d’invisibilité de la toute première surface. Pas de capture de documents réels ni benchmark CPU/GPU.

Après : iTerm2 fictif495951 ; deux cadresCG seulement,570×436 de naissance puis914×1052 à4432,303 ;133,35ms entre les deux, cible stable7,4s. La géométrie finale diffère des essais avant : comparaison de comportements, pas benchmark contrôlé ni promesse de ratio de gain. Un second essai a été refusé AVANT création car l’écran actif avait changé ; aucune nouvelle fenêtre ni succès revendiqué pour lui.

AppKit réel : cadre final atteint en224ms environ après première surface, avec quatre cadresCG. Instrumentation de la fenêtre fictive : appels frame sans demande animate, tailles1272×632 puis1837×679 puis1837×1052 ; ces tailles correspondent aux limites du premier écran pendant les phases taille/position/taille. Cela soutient une contrainte native transitoire ; aucune atomicité native n’est affirmée. Les deux observations instrumentées sont conservées horsGit. Aucun troisième correctif empirique n’a été empilé.

Code chargé : UUID758AD9DB-B909-3E17-80FC-512675038D50, PID23980, certificat stable78a75e8032f190a20072eb91cc2919aac344ef78. Configuration identique à la sauvegarde. Santé5/5 après installation et nettoyage. Une requête de contrôle émise pendant le redémarrage a reçu69 ; contrôle repris après disponibilité du socket, sans nouveau redémarrage.

Preuves : diaporama vérifié,7étapes/5images fictives,42,8Ko, aucune position de clic fabriquée. Créations par commandes natives iTerm et vraie fenêtre AppKit, pas de CmdN physique rejoué. Aperçu T3 contrôlé visuellement ; suivant, lecture/pause et dernière étape pilotés dans le navigateur, console next=true/paused=true/last=true. Originaux/manifestes horsGit dans /Users/moi/.local/state/roadies/validation/2026-10-31-146.

Nettoyage : processus de test sortis, stage validation146-initial supprimée par la commande normale après délai de fermeture, scopes actifs rendus à3 externe et9 interne. Terminal utilisateur494130 conservé. Aucun JSON global restauré. Rollback signé conservé ; enregistrement LaunchServices temporaire retiré.
