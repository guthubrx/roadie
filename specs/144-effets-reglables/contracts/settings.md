# Contrat utilisateur — 144

Paramètres > Effets expose Activation, Profils et mouvement, Pendant un glisser, puis les surcharges par action. Libellés et aide FR/EN. L’aperçu local ne touche aucun document.

[fx] drop_preview = "contour" ou "real". Ce choix ne dépend ni de [fx.animations] enabled ni de [tiling] live_drag_preview.
[fx.animations] : enabled, profile, curve, duration_ms, intensity, stiffness, damping.
[fx.animations.move|stage|appearance|rail|launcher|switcher|overview] : enabled, curve, duration_ms, intensity, stiffness, damping, valeurs absentes héritées.

Les sauvegardes utilisent SettingsConfigService et le contrat existant /set. Pas de nouvelle commande CLI. Valeur invalide : rejet de l’écriture par catalogue et validation du fichier, sans état partiellement appliqué.

Si le tap manque ou le titre n’est pas admissible, le geste natif garde le contour. L’interface décrit cette limite ; un événement diagnostic distingue indisponibilité de capture et refus AX. Aucune demande de nouvelle permission automatique.

Résultats de placement : deferred signifie planifié, pas appliqué. Les compteurs de succès final n’incluent pas ces éléments. Les consommateurs ne concluent pas à un refus de taille à partir d’un résultat deferred.

Les réglages Roadie font seuls autorité. Le choix macOS Réduire les animations ne modifie pas cette politique.

Qualification native du 31 octobre : pendant un glisser possédé entre écrans à Spaces séparés, le cadre AX rejoint la cible, mais WindowServer masque le contenu jusqu’au relâchement. La vraie source reste donc sur son écran initial lorsque le pointeur vise un autre écran ; le contour de destination est affiché et le dépôt reste fonctionnel. Aucun transfert de Space non réversible ni injection n’est ajouté. Limite explicite de l’aperçu réel : même écran.

Pour les fondus, les valeurs de l’action spécifique remplacent celles d’Apparition/disparition, qui remplacent les valeurs communes et le profil. L’interrupteur Apparition/disparition coupe tous les fondus, sans couper les déplacements. Les paramètres de géométrie de la vue d’ensemble restent réglés par son action propre.
