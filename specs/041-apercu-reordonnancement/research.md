# Diagnostic et réutilisation

RailPanel dessine actuellement insertionY dans RailStackView. Les cibles viennent des milieux des vignettes originales et le rang est calculé dans l’ordre persistant complet. RailController fige les reconstructions pendant pendingStageReorder.

Déplacer les cartes originales pendant le geste modifierait les seuils du geste lui-même. Une couche de copies non interactive conserve les seuils. StageCardView détient déjà configuration, stage et miniatures nécessaires au rendu. Les copies utilisent ces mêmes données et le numéro futur. Les spacers, en-têtes et indicateurs restent à leur position.

Les tests Spec032 construisent déjà un RailPanel réel avec NSScreen. Ils permettent de comparer l’aperçu et le rendu après reorderStage, sans toucher aux fenêtres de l’utilisateur. Les tests Spec029 couvrent les rangs avec stages vides.
