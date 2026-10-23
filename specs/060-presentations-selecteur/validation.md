# Validation 060

## Implémentation
Les cinq organisations utilisent les cartes, le cache, la sélection et les actions
existants. Configuration commune `switcher.presentation`, surcharge facultative
dans chaque profil. Défaut `classic`, valeurs inconnues normalisées sans écriture.
Regroupement par identifiants écran/bureau/stage, ordre du profil conservé.
Le changement de sélection révèle le groupe ; les arrivées de vignettes ne
ramènent pas un défilement manuel vers la sélection.

## Contrôles terminés
- 143 tests ciblés dans 20 suites : réussite, 2,384 s.
- Suite complète : 1 892 tests dans 234 suites, réussite en 57,510 s.
- Passage final après harmonisation des noms générés avec le rail : 1 893 tests
  dans 234 suites, réussite en 58,192 s. Aucun identifiant interne affiché pour
  une stage anonyme ; test dédié réussi.
- Scripts : 28 tests, réussite en 20,817 s.
- Géométrie des six organisations et des trois styles, largeurs 220/500/1000,
  polices 10/16/32 : cartes dans le document, aucun chevauchement de cartes.
- Petits panneaux, sélection inter-bureaux, recherche, héritage des profils,
  flèches avec Commande, survol, activation et défilement : tests natifs réussis.
- Détection avant correction d'une navigation Bas vers une grande fenêtre voisine
  dans le plan spatial. Priorité corrigée à la colonne, test de régression réussi.
- 339 fichiers Sources/Tests empreintés ; aucun benchmark réalisé.

## Preuves et limites actuelles
Cinq rendus AppKit du jeu fictif examinés. Les captures brutes et journaux restent
hors Git dans le dossier de diagnostics de la session. Le diaporama signale ces
images comme rendus de test et non comme parcours de la version installée.
CUA indisponible : `CUA_REPL_ENABLED_SURFACES is required`. Le circuit natif BTT
sera utilisé après installation si la fenêtre et le bureau restent disponibles.
Avant non capturé ; aucun pointeur ni clic supposé ajouté aux captures.

## Revue indépendante
Demande Bridget `roadie-060-presentations-review-20261023-1`, source
5118b58deb1aab232ac7440e3ec70d3406de35ee. Admission refusée immédiatement :
`auto_admission_invalid`, sans identifiant de tâche ni revue démarrée. Aucun
contournement ni autre moteur lancé. Relecture du diff, tests et installation
poursuivis par le responsable ; cette livraison n'a pas de verdict indépendant.

## Installation et contrôle réel
Build Release final installé et relancé. UUID de la compilation et du daemon
installé identiques : 92CDDB8A-E428-3103-ADAE-7E1901FBC770. PID 11924.
Les cinq contrôles santé sont OK, dont Accessibilité et validation de configuration.
339 empreintes Sources/Tests inchangées depuis les tests finaux. Signature stricte
vérifiée ; certificat 78a75e8032f190a20072eb91cc2919aac344ef78 conservé.
Configuration utilisateur identique, SHA-256 vérifié après installation et essai.
Aucun raccourci BTT ni permission macOS modifié. Version locale 0.7.0 conservée ;
aucune nouvelle release publique.

Ouverture par `roadie switcher show` : panneau réel « Sélecteur de fenêtres Roadie »
observé, ID 383567, couche 26, 1100 × 652 points. Annulation par la commande publique,
sans activation ni changement d'appartenance. Santé finale 5/5.

Preuves incomplètes : le parcours des choix dans la fenêtre installée n'a pas été
capturé. La barre de commande s'est fermée pendant les deux tentatives de saisie
automatisée (action BTT 193 puis API paste_text). Le journal réel donne
target_search_cancelled. Les panneaux ont été relus avant de poursuivre ; aucune
validation n'a été envoyée après leur disparition. Pas de troisième tentative
aveugle ni demande répétée de permissions. Les rendus natifs et tests des choix,
de la persistance et des interactions restent les preuves disponibles.

Diaporama autonome : preuves-corrections/2026-10-23-selecteur-060/preuves.html.
Captures brutes, manifeste et journaux conservés hors Git dans les diagnostics
2026-10-23-session060. Le diaporama indique les étapes non vérifiées.

## Reprise de fidélité visuelle du 23 octobre
Retour utilisateur : le regroupement fonctionne, mais le rendu diffère trop des
maquettes (panneau vertical, captures étroites, contexte répété, aperçu sans détail).
Correction et validation complémentaire en cours sur `session-060-fidelite-selecteur`.
Revue demandée par Bridget, clé `roadie-060-fidelite-review-20261023-1`, base
`cc11fb8fc3b36453ca4818f4bb53d9299f69a367`, espace partagé, lecture seule.
Refus immédiat `auto_admission_invalid` : aucun identifiant de tâche, décision ou
exécution retourné, aucun agent lancé. Aucun autre moteur utilisé en remplacement.

Validation complémentaire : 32 tests ciblés / 5 suites réussis, puis 1 899 tests
Swift / 235 suites réussis en 33,881 secondes ; 28 tests de scripts réussis.
Un ancien contrôle cherchait l'image directement dans la fenêtre : il vérifie
maintenant le panneau de détail, sa position et l'image intégrale contenue.
Aucun benchmark. Six rendus natifs (classique et cinq organisations) comparés
aux maquettes, dont huit fenêtres verticales et groupes de tailles différentes.
Les rendus hors écran ne reproduisent pas le flou réel de NSVisualEffectView.
Complexité : parcours linéaires conservés ; cache d'icônes par PID, recadrage O(1),
répartition des colonnes O(s). Aucun nouveau relevé AX ni lot de capture.

### Complément : onze fenêtres sur une page
La capture utilisateur révèle la nécessité de tenir verticalement sans former des
bandes. Le cas réel de largeur préférée 120 a été ajouté. Le recadrage se fonde
sur la carte affichée, et la résolution des captures suit sa largeur effective,
avec le même budget. Les demandes de capture partent après le calcul des cartes.
Recherche bornée de 30 plans au plus : colonnes de bureaux, tailles de cartes,
puis hauteur d'image compacte si nécessaire. Les stages d'un bureau restent
réunies, la police reste inchangée et aucune fenêtre n'est supprimée.
34 tests ciblés / 6 suites réussis. Cas de onze fenêtres sur quatre bureaux et
sept stages : 120/220/400 points, 1920×1080 et 3840×2160, zéro défilement vertical.
Suite finale : 1 900 tests / 235 suites réussis en 37,115 secondes. Les 28 tests
de scripts restent valides ; aucun script de production n'a été modifié.

### Installation finale et limites des preuves
Release compilée, installée et relancée ; UUID
`E367325B-3C1D-3958-B982-886E7E2BD915`, PID 21019. Les cinq contrôles de santé
sont OK. Certificat `78a75e8032f190a20072eb91cc2919aac344ef78` conservé.
Les 337 fichiers Swift Sources/Tests empreintés n'ont pas changé entre la suite
finale et l'installation. Le fichier utilisateur n'a pas changé entre la dernière
préparation et l'installation ; les choix manuels faits pendant la session restent
présents. Aucun raccourci BTT ou Karabiner n'a été modifié.
Une tentative de parcours automatisé par configuration temporaire a été arrêtée
après fermeture du panneau pendant la capture. Réglages d'origine rétablis,
fichier temporaire supprimé. Une ouverture réelle de la version intermédiaire
avec onze fenêtres a été observée, révélant le cas de largeur 120. La version
finale a été capturée sur le bureau en grille classique, avec douze fenêtres.
Le contrôle visuel final de la grille par sections et le parcours des paramètres
restent incomplets ; ils ne sont pas présentés comme validés en réel.
Le diaporama de fidélité contient six rendus natifs fictifs, dont le cas onze
fenêtres sur une page. Lecture/pause, navigation, sélection de dernière étape et
zoom vérifiés dans T3. Les captures réelles, qui contiennent les fenêtres de
l'utilisateur, restent hors Git. Aucun clic fictif annoté.
