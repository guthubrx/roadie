# Plan

Réutiliser StageCardView et les miniatures déjà chargées. RailPanel conserve les cartes originales pour le calcul des destinations et dessine une couche non interactive de copies. Seule la carte déplacée est translucide. Recalculer les copies quand la destination change, sans lecture AX ni capture pendant le geste.

Conserver persistentReorderPosition et le rang persistant transmis à reorderStage. Comparer les positions de l’aperçu au rendu AppKit après dépôt, y compris avec des hauteurs différentes. Supprimer uniquement le fantôme de stage attaché au curseur dans RailController.

Validation : tests ciblés puis suite isolée séquentielle, revue indépendante, build Release et installation signée, redémarrage et santé. Appliquer la skill preuves-correction ; signaler toute impossibilité de capture réelle. Mettre à jour la documentation et intégrer sur main après validation.

## Aimantation

Conserver le calcul des cibles originales. Ajouter une hystérésis bornée autour du seuil entre destinations, proportionnelle à l’intensité 0–100 et à l’espacement des cibles. La position précédente vient de l’aperçu. Calculer le dépôt avant de retirer cet aperçu pour conserver sa destination stabilisée. Paramètre TOML fx.rail.stages.reorder_magnetism, catalogue, curseur et signature RailSettings existants ; aucune nouvelle dépendance. Tester oscillations autour du seuil, saut distant, intensité nulle, bornes et écriture via SettingsService.
