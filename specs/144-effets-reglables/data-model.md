# Modèle — 144

- EffectsConfig : borders existant ; animations (configuration commune et surcharges par action), dropPreview (contour / real). Défaut : animations désactivées, contour ; anciens comportements conservés jusqu’à activation.
- AnimationAction : move, stage, appearance, rail, launcher, switcher, overview.
- AnimationPolicy : enabled, profile (none/subtle/smooth/expressive), curve (linear/ease_out/ease_in_out/spring), duration_ms [0,1000], intensity [0,1], stiffness [50,1500], damping [0.3,2]. Surcharge par action ; profil établit les valeurs héritées. Ancien animation_ms du rail hérité si aucun remplacement explicite.
- Motion : valeur courante, vitesse, cible, temps monotone ; évolution pure, pas de timer/store/AX. Cible atteinte exactement à terminaison. Reprise depuis valeur/vitesse courantes. Résultat valide et taille positive même si ressort dépasse.
- Animation runtime : identifiant, politique capturée, instant, mise à jour, fin ; un timer commun seulement si au moins un élément actif. Invalidation supprime les callbacks anciens.
- LiveDropPreview.Session : sourceGestureOwned ajouté, source touchée seulement en mode réel ; originals/windows/touched/scopes/permit/dispatcher existants réutilisés. La visée et le contexte d’origine restent figés.
- Propriété souris : pending native -> qualifié -> owned -> ending -> drained. Si le premier mouvement arrive avant qualification : native jusqu’à fin. Échap en owned : restoring puis drained au relâchement ; aucune nouvelle capture entre les deux.
- ApplyResultItem.Status : deferred ajouté pour plan accepté mais non encore écrit. Ni succès, ni refus, ni échec final. Counts et événements distinguent les écritures effectives. Le final repasse par le writer et les observations communes.

Le modèle durable de stage, les arbres BSP et les affectations ne changent pas. Aucun nouveau fichier de données hors configuration TOML. Pas de migration destructive.
