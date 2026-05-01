import Foundation
import RoadieCore

/// Registre des stratégies de tiling disponibles.
///
/// Chaque implémentation conforme à `Tiler` s'enregistre via `register(_:factory:)`.
/// Le daemon, au boot, appelle l'enregistrement de chaque tiler livré (BSP, Master-Stack).
/// Pour ajouter une nouvelle stratégie ("papillon", "fibonacci", …), il suffit de :
///   1. Créer un fichier `<Name>Tiler.swift` conformant à `Tiler`.
///   2. Lui donner une méthode `static func register()`.
///   3. L'appeler dans le bootstrap du daemon.
///
/// Aucune modification de `TilerRegistry`, `TilerStrategy`, ou `LayoutEngine` n'est nécessaire.
public enum TilerRegistry {
    private static var factories: [TilerStrategy: () -> any Tiler] = [:]

    /// Enregistre une factory pour une stratégie. Appel idempotent : un appel ultérieur
    /// avec la même stratégie remplace la factory précédente.
    public static func register(_ strategy: TilerStrategy, factory: @escaping () -> any Tiler) {
        factories[strategy] = factory
    }

    /// Crée une instance de la stratégie donnée. Retourne `nil` si non enregistrée.
    /// Le caller décide comment réagir au nil (fail loud au boot, erreur 1 au runtime).
    public static func make(_ strategy: TilerStrategy) -> (any Tiler)? {
        factories[strategy]?()
    }

    /// Stratégies disponibles, triées par identifiant pour stabilité.
    public static var availableStrategies: [TilerStrategy] {
        factories.keys.sorted { $0.rawValue < $1.rawValue }
    }

    /// Vide le registre (utilisé uniquement par les tests).
    public static func reset() {
        factories.removeAll()
    }
}
