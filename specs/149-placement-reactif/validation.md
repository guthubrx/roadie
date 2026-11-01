# Validation 149 — placement et barre

Date : 1 novembre 2026. Le reçu de clôture est dans livraison.md.

## Défauts confirmés et corrigés
- Les 38 tentatives finales échouées de la période 05h10–11h08 CET ne revenaient pas à la mémoire des échecs ni aux événements par fenêtre. Il ne s’agit pas de38fenêtres distinctes. Seuls les résultats finaux de la génération courante reviennent maintenant au maintainer. Les cibles identiques déjà échouées réutilisent la protection existante.
- Des relevés AX du producteur occupaient le fil principal. Les relevés périodiques et l’ouverture de la barre passent par l’acquisition asynchrone existante, avec contrôles de publication et annulation. L’ordonnanceur ne prépare qu’une passe à la fois.
- Les callbacks de cadre des fenêtres connues relisaient encore AX sur le fil principal. Un échantillonnage natif en montre504échantillons. L’identité locale et les lectures de cadre coalescées hors MainActor corrigent ce second chemin.
- La sauvegarde périodique de restauration relançait un relevé synchrone toutes les30s. Elle réutilise désormais readerSnapshot, avec tâche unique et contrôles Mission Control avant/après l’attente.
- Trois régressions rouges ont confirmé une acquisition pendant Mission Control, une notification nouvelle écrasée par un relevé plus ancien et une fermeture de Mission Control non mémorisée entre préparation et passe. Les gardes de génération et de stabilisation sont corrigées.
- Deux régressions rouges ont confirmé200lectures rejetées en10s et une échéance perdue. Les reprises attendent50,100,200,400,800,1600puis2000ms. Demandes et échéances sont conservées, rejets et reprise journalisés. Le test impose moins de15lectures en10s.
- Un crash natif SIGTRAP du1novembre à12h55m33CET (sourcea5be198, PID20064) se produit dans swift_unknownObjectRetain, depuis le callback commun du tap clavier. Le contexte non retenu devient un identifiant opaque, associé à un propriétaire faible sous verrou. La fermeture révoque cet identifiant puis invalide port et source. Une tâche clavier déjà en file revérifie aussi finished avant handle.

## Tests sur la dernière source
- 2459tests dans372suites réussis en75,767s, exécution séquentielle et HOME isolé.
- 89tests ciblés dans15suites avaient déjà réussi avant la dernière garde clavier. La suite finale contient ces tests.
- 28tests de scripts réussis en17,176s ; leur source n’a pas changé depuis cette exécution.
- Les529empreintes Sources/Tests sont conservées hors Git avant la compilation signée et revérifiées à la livraison.
- Les trois revues indépendantes et les décisions sur leurs constats sont consignées dans revue.md. Elles sont des lectures de source, sans exécution de tests par les lecteurs.

## Mesures natives et limites
La barre est ouverte par la commande existante workflow alfred search sur une recherche fictive. Une application standard de validation décale son cadre de2points puis bloque uniquement son propre fil pendant1,2s. Aucun processus utilisateur n’est suspendu. Les essais sont espacés de6s pour laisser expirer la mise de côté AX.

Avant correction : pauses max_stall de579,517,544ms. Après correction des callbacks :64,70,73ms, puis série prolongée120,125,66,71,108,79,67,85ms. Un pic429ms d’une autre série reste conservé.

Les résultats n’ont pas été uniformes entre les activations intermédiaires. Après un redémarrage :663,718,642,652ms sans profil simultané. Une série profilée suivante donne82ms, une session interrompue à346ms de durée, puis69ms. Nouveau démarrage profilé : première session trop courte à1118ms (max_stall0, dessin816ms), puis182,76,90ms. Aucune cause certaine n’est attribuée aux pics. Le crash observé ensuite invalide toute déclaration de stabilité fondée uniquement sur les premières séries.

Après activation du correctif de contexte clavier970cdab :16ouvertures complètes avec le même PID91871, pauses54–95ms, premier dessin63–384ms, aucun nouveau rapport de crash. Quatre essais lents complets donnent70,66,123,67ms ; premier dessin186,114,218,156ms. Santé5/5 après ces parcours. La dernière garde contre un traitement clavier déjà en file est ensuite chargée et vérifiée dans livraison.md.

Une première comparaison d’ouvertures ordinaires donnait192–502ms de premier dessin avant et90–199ms après. Les caches et les autres applications peuvent varier. open_ms désigne la durée complète de la session, pas le temps d’ouverture. Aucun gain universel ni limite absolue de latence n’est revendiqué.

## Limites techniques conservées
- Un appel AX déjà lancé ne peut pas être interrompu physiquement par Task.cancel. Il termine en arrière-plan et son résultat annulé est rejeté.
- Certains appels initiaux pour une fenêtre inconnue, les abonnements et des commandes explicites restent synchrones. La correction ne supprime pas tous les appels AX du fil principal.
- Après plusieurs rejets, la reprise peut attendre jusqu’à2s. Le daemon continue à observer à fréquence réduite si le contexte reste instable.
- Les petites écritures JSON locales restent sur MainActor pour préserver la cohérence et l’atomicité.
- Les5annulations utilisateur et les7reprises de Cmd+Tab observées dans le diagnostic ne sont pas classées comme des erreurs. Aucun sélecteur réellement vide n’a été trouvé dans cette période.

## Preuves
Diaporama autonome versionné dans preuves-corrections/2026-11-01-149-placement-reactif/preuves.html. Captures natives limitées à une saisie fictive, sans document utilisateur. Originaux, manifestes, traces et rapport de crash conservés hors Git.
Preuves partielles : l’ouverture et la fermeture passent par les commandes existantes, sans frappe système simulée. CUA ne fournit aucune surface (CUA_REPL_ENABLED_SURFACES is required). Le pilote temporaire n’a pas l’autorisation PostEvent/Accessibility ; aucun droit n’a été modifié. Aucun clic ni repère de souris inventé. Les manipulations physiques complètes du clavier restent non enregistrées.


## Dernière activation vérifiée
UUID723B2205-C1F6-3EC2-9F63-E747FE9992CA, PID27444. Les529empreintes Sources/Tests de compilation sont inchangées. UUID du produit compilé et du produit installé identiques ; certificat78a75e8032f190a20072eb91cc2919aac344ef78 et TOML conservés.
Huit sessions natives observées : premier dessin134–270ms, pauses16–83ms. Deux sessions sont plus courtes (392et541ms) ; aucune interprétation inventée, aucun parcours physique complet déduit. Les six autres durent1,043–1,143s. Trois essais lents complets : pauses73,83,63ms, premier dessin151,242,148ms, aucune passe supérieure à400ms.
Un layout_failed concerne uniquement la fenêtre fictive592940 : AX retourne succès, mais garde une hauteur679 au lieu1052. Le résultat différé est bien journalisé, puis layout_app_response_accepted accepte ce refus ; aucune boucle observée. Les focus_failed du pilote concernent cette même fenêtre fictive. Les originaux identifient l’application Validation149 ; aucun échec utilisateur n’est masqué.
Les cinq contrôles de santé restent verts après les essais, même PID. Aucun nouveau rapport de crash : seul le rapport12h55 antérieur au correctif est présent. Application fictive et pilote fermés normalement, PID absents, focus rendu à T3 Code. Le contrôle pendant le redémarrage lisait brièvement l’ancien PID arrêté ; le contrôle après disponibilité et celui de fin sont tous deux5/5.
