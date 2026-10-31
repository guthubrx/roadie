# Validation — Session 144

État : livré sur main, poussé, installé et activé. Réglages retenus au moment des mesures : animations Roadie activées, profil Sobre hérité, destination réelle, voisines activées. L’utilisateur a ensuite choisi smooth, ease_out et move.ease_in_out ; ces choix sont conservés. macOS reduceMotion=1 inchangé ; aucune dépendance à ce réglage dans la politique Roadie. Les surcharges de durée utilisées pendant les démonstrations ont été retirées.

## Matrice native

| Cas | Résultat observé | Limite |
|---|---|---|
| Source AppKit, paysage vers portrait | 1837×1052 → 914×2114 ; nouvelles lignes réelles ; cadre stable au mouvement suivant et au dépôt | Injection BTT, pas de mesure de cadence écran |
| Échap pendant appui | Source et voisines restaurées avant le relâchement, puis identiques après | Aucun changement du modèle |
| Vraie source sans voisines | Source seule change ; A/C inchangées ; annulation restaure | Réglages indépendants vérifiés |
| TextEdit | 913×1052 → 452×2114, stable puis restauration | Document fictif |
| Chrome | 913×1052 → 452×2114 ; texte reformaté et vidéo locale toujours rendue | Profil temporaire, fenêtre d’application Chrome |
| Finder | 1837×1052 → 580×2114 ; minimum conservé ; restauration | Dossier et fichiers fictifs |
| Taille imposée | Fenêtre témoin reste à 640×382 et rejoint le point demandé ; Échap restaure la position | Ne force pas la taille refusée |
| Rail → bureau | Source A 914×1052 → 914×2114 ; seul A change avec voisines coupées ; Échap restaure toutes les frames | Premières tentatives visaient une zone ou une cible inadéquate ; non comptées |
| Autre écran / Space | Frame déplacée mais contenu absent pendant l’appui : défaut observé puis repli corrigé. Source reste à l’origine, contour sur destination ; dépôt conservé | Aperçu réel limité au même écran ; aucun transfert privé de Space ajouté |
| Réglage macOS Reduce Motion activé | Fondus avec alpha intermédiaires 0,006 à 0,999 ; aperçu local animé | Durée temporaire 1000 ms pour échantillonnage, retirée ensuite |
| Clic / fermeture / génération / pin / configuration | Tests de sessions et writers, générations et refus ; callback de pression et notifications écran/Space/veille raccordés | Pas de veille ni de débranchement physique imposés à l’utilisateur |

## Mesures reproductibles

Deux essais successifs, chacun 30 s au repos et 10 glissers réels annulés. Source B et cible C du même témoin AppKit ; aperçu réel actif, voisines temporairement coupées pour ne pas toucher les autres fenêtres. Tous les cadres B restaurés : 10/10 pour chaque essai. Sans build ni test Swift pendant les mesures. CPU = delta du temps CPU `ps` divisé par temps écoulé, en pourcentage d’un cœur. RSS = mémoire résidente `ps`, KiB ; ne représente pas la mémoire privée. Le témoin échantillonne ses fenêtres à 120 Hz : son coût de base est inclus. WindowServer inclut les autres applications.

| Condition | Roadie CPU | WindowServer CPU | Témoin CPU | Roadie RSS début → fin |
|---|---:|---:|---:|---:|
| Animations coupées, repos 30 s | 2.86 % | 43.61 % | 1.79 % | 198.0 → 194.7 Mio |
| Animations coupées, 10 glissers | 6.09 % | 32.01 % | 3.24 % | 195.3 → 192.1 Mio |
| Animations actives, repos 30 s | 2.99 % | 43.93 % | 1.86 % | 196.2 → 198.2 Mio |
| Animations actives, 10 glissers | 6.11 % | 33.10 % | 3.47 % | 198.9 → 195.1 Mio |

Le suivi direct ne passe pas par les animations temporelles. Les 6,09/6,11 % de Roadie sont donc cohérents, sans constituer une preuve statistique d’équivalence. Latence observée depuis le début de la commande BTT jusqu’au premier cadre modifié (échantillons du témoin 120 Hz) :

| Animations | p50 | p95 | Échantillons |
|---|---:|---:|---:|
| off | 281.5 ms | 295.9 ms | 10 |
| on | 296.6 ms | 350.5 ms | 10 |

La durée nominale d’injection BTT de 180 ms et son transport sont inclus. Ces chiffres ne sont ni une latence doigt-écran, ni une cadence d’images, ni un gain sur une version antérieure. L’ordre off puis on, l’échauffement des caches et le travail des autres applications limitent la comparaison.

Dix ouvertures/fermetures du lanceur, 0,5 s ouvert puis 0,5 s après Échap :

| Animations | Durée de l’essai | Roadie CPU | WindowServer CPU | Roadie RSS début → fin |
|---|---:|---:|---:|---:|
| off | 11.88 s | 21.71 % | 45.78 % | 197.9 → 202.7 Mio |
| on | 11.87 s | 16.59 % | 47.08 % | 201.4 → 205.6 Mio |

Le lanceur coûte plus que le simple suivi car il prépare sa liste. Le second passage bénéficie des caches. La baisse de CPU observée n’est pas attribuée aux animations. L’augmentation du RSS entre les ouvertures ne prouve pas une fuite ; aucune analyse de tas n’a été faite.

GPU : `ioreg -r -c AGXAccelerator -a`, champs Device/Renderer/Tiler Utilization. Compteurs globaux, pas de ventilation par PID. Médiane à 0 % dans les deux essais de glisser, maximum au repos 11 % off et 54 % on, révélant l’activité globale et la faible résolution de l’échantillonnage. Impossible d’en déduire le coût GPU propre à Roadie ; aucune attribution inventée. Le moteur ne capture aucun pixel supplémentaire, anime les panneaux à 60 Hz au plus et envoie les cadres AX à 30 Hz au plus, avec une file par application.

## Tests et limites

Tests ciblés :42 tests dans5 suites réussis. Suite complète2416 tests/360 suites et28 scripts réussis dans le runner V15 sur le code figé. La suite est exécutée séquentiellement : les tests UI MainActor en concurrence affament des contrôles à échéance. Un ancien cache Swift incompatible avec le layout d’une structure publique a été nettoyé ; le crash a été diagnostiqué par LLDB, puis a disparu après reconstruction complète.

Revues indépendantes du plan et du code : admission Bridget refusée, aucune tâche admise, aucun verdict favorable. Le refus et ses limites sont conservés dans les deux rapports de contre-revue. L’audit local reste non indépendant.

Données natives, originaux, profils de test et journaux : /Users/moi/.local/state/roadies/validation/2026-10-31-144/. Les résultats des premiers essais restent valides pour les mécanismes inchangés ; les modifications ultérieures portent sur les interruptions, le repli inter-écrans et l’héritage des surcharges de fondu. Le dernier chargement et le contrôle de santé ont été effectués après intégration.

## Compléments issus de l’usage pendant la validation

L’utilisateur a modifié ses profils pendant les essais : smooth, courbe commune ease_out et surcharge move ease_in_out. Ces choix sont conservés. Les captures précédentes montrent l’état au moment de leur prise, pas un profil imposé.
Le glisser réel a été qualifié sur les cas observés, puis confirmé stable sur Firefox par l’utilisateur. T3 expose sa bande vide comme un groupe racine sans action, et non comme AXWindow ; cette variante a été observée puis ajoutée. Firefox expose AXWindow : bande et délai de qualification corrigés. La stabilité sur un même écran est maintenant confirmée par l’utilisateur, indépendamment des fenêtres fictives.
La suite ciblée a aussi subi les boutons physiques de l’utilisateur, que schedule observe pour protéger ses gestes. La frontière matérielle est maintenant injectée dans les tests ; la lecture NSEvent reste la valeur native par défaut en production.

## Dernière correction du parcours utilisateur

Bande de titre44 commune au détecteur et à la qualification, publication AX hors MainActor dèsCGdown, revalidation identité/point/cadre, AXGroup racine Electron et bande vide Chrome sans action/enfant. Version chargée PID53939, santé5/5. Chrome normal fictif469459, application PID71200 dédiée :8/8 glissers réels et stables,8/8 annulations complètes, offsets12/26/33/39. Aucun délai volontaire après mouseDown ; transportBTT inclus. Stage de test supprimée et stage interne9 rétablie ; processus propres arrêtés. Stabilité Firefox confirmée par l’utilisateur après cette installation, y compris bas du titre et glisser rapide. L’utilisateur confirme aussi le repli contour entre écrans ; aucune garantie sur toutes les applications n’est déduite de ce seul essai. Une qualification indisponible/tardive garde le natif et le contour ; aucune capture tardive du geste.

Tests finaux :2416/360 suites PASS, puis même total dans runner V15 ; scripts28 PASS. Audit révision1 PASS/release_blocked=false et validation du recalcul réussie. Semgrep29 fichiersSwift sans candidat, Gitleaks fichiers13,27Mo sans candidat sur copie SHA identique hors chemin ignoré, historique borné aprèsv0.4.0, OSV verrouTOMLKit0.6.0 sans vulnérabilité signalée. Les erreurs de la révision0 sont conservées. Qualité par axe63–75/100 sur les critères examinés ; la note indicative de défautsA ne représente pas une qualité parfaite. Rapport détaillé dans le dossier d’audit.

## Activation intégrée

Code fe63993caa507b9a9e8f96b824a344850d485b4d intégré à main par avance rapide, socles142/143 inclus ; push origin/main vérifié. Build Release depuis le checkout main :199,22s pour roadied et2,11s pour roadie. UUID compilé, installé et chargé :76B3E44F-DB41-3DF5-BECE-7849353D4880, PID30412. Certificat78a75e8032f190a20072eb91cc2919aac344ef78 conservé, codesign strict réussi, santé5/5. Configuration SHA identique avant/après et28 affectations identiques. Reçu détaillé : livraison.md.
