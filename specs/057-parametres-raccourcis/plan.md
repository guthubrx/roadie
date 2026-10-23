# Plan 057
1. Métadonnées de sections pures: partition totale du catalogue, réutilisation des descripteurs/persistance. Réduction des aides permanentes, disposition des contrôles compacte et adaptable.
2. Apparence commune avec valeurs facultatives propres au profil (style, aperçu, taille et police). Configuration rétrocompatible: trigger_source (déduit de hotkey à la lecture ancienne), profil enabled, release_action focus/stay/search, search_visibility/actions_visibility auto/always/never, arrow_navigation/mouse_hover. Un raccourci BTT garde sa combinaison mais n'est pas enregistré par Carbon Roadie.
3. Éditeur de profils dédié au-dessus du codec existant. Écriture au travers de SettingsCollectionEditorModel et contrôle des conflits. Bouton de capture AppKit temporaire, arrêt sur annulation/fermeture. Même composant pour search_hotkey.
4. Liaison BTT par API AppleScript, JSON sérialisé; aucun SQL en écriture. UUID liés explicitement au profil dans un registre local. Préparer/vérifier, puis commuter; rollback borné en cas d'échec. Les entrées utilisateur non reconnues sont importées seulement après correspondance exacte et action explicite.
5. Panneau du sélecteur: recherche activée selon mode, navigation géométrique pure sur les cadres, survol via mouvement réel sans activation, pas de scan AX par mouvement.
6. Tests de contrats et scénarios, suite complète, scripts, revue, documentation, compilation/install/restart, santé et preuves honnêtes. Git et nettoyage selon autorisation.

