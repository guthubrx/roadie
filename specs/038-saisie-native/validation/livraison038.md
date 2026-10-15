# Livraison 038 — saisie native

15 octobre 2026. Release installée, signée avec le certificat existant roadied-cert.
Redémarrage de Roadie vérifié : PID 96284. T3 n’a pas été redémarré ; ses processus
65544 et 97328 sont conservés. Quatre contrôles santé OK après les parcours.
UUID identique entre Release compilée et installée :
9B0A1CA9-9170-3AC4-B2C5-38ADC0E8EE97.
SHA-256 du binaire installé signé :
160fbd0733aaefbdd0d4005afa4f757d0903c16f37571c149e8e972e51fd15ac.
La signature modifie l’empreinte du binaire non signé ; la vérification codesign
--verify --deep --strict réussit. Aucun changement produit après les tests.

## Vérifications

127 tests ciblés dans 10 suites ; 1 597 tests dans 185 suites, tous réussis.
Contre-lecture locale du diff ; aucune revue indépendante lancée.
Circuit clavier réel : ⌘A donne [0,10] sur /settings suivi d’une espace.
⌥⌫ transforme alpha beta en alpha suivi d’une espace ; ⌘⌫ vide la ligne.
⌘C, ⌘X, ⌘V, ⌘Z et ⇧⌘Z donnent les valeurs attendues, relues via Accessibilité.
Deux flèches Bas puis Tab insèrent /settings tuilage.
Clic natif (770,1108), écran 2048×1280 : /settings rail inséré, texte témoin intact.
Retour ferme la barre et ouvre les réglages dans Rail ; journal command_box_settings.
La fenêtre témoin et la fenêtre de réglages de test sont fermées.
Presse-papiers restauré par le témoin si toujours égal à notre texte fictif.
L’unique ajout d’historique settings rail est retiré après comparaison stricte.

Configuration identique, SHA-256 :
301d7d43737c1deb31d2acaa3146ca5b285450a1bad65d27bd8cd095e19a3d77.
Vingt scopes conservés. Identifiants, noms, ordre et groupes des stages inchangés.
Les 28 membres communs gardent leur stage. La seule référence retirée (123671,
HyperWhisper) était déjà marquée confirmedClosedAt dans la sauvegarde initiale.
Les métadonnées de présence, cadres et focus évoluent normalement pendant l’essai.
Aucun réglage BTT modifié ; l’action shell de test est éphémère.

## Preuves et limites

Preuves : diaporama vérifié, huit étapes, sept captures natives. Avant non capturé.
Les captures trop précoces du premier essai sont exclues. Aucun faux curseur ajouté
sur le clic natif : coordonnées réellement émises conservées dans le script, sans
horodatage pointeur DOM applicable à AppKit. Un essai complémentaire a été arrêté
avant toute saisie après changement d’application. Il ne compte pas comme preuve.
Haut, les sélections au milieu et les flèches modifiées sont vérifiés en tests.
Glisser de sélection et toutes les méthodes IME non rejoués manuellement.
L’écran externe n’est pas connecté pendant cette validation.

Diaporama autonome :
/Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/038-saisie-native/preuves-corrections/2026-10-15-038-saisie-native/preuves.html
Preuves brutes, sauvegarde et empreintes hors Git :
/private/tmp/roadie038-evidence
