import Foundation

// SPEC-019 — Registre central des renderers de cellule de stage.
// Pattern reproduit textuellement de `RoadieTiler.TilerRegistry` (Article I' constitution-002).

public enum StageRendererRegistry {
    public static let defaultID: String = "stacked-previews"

    @MainActor
    private static var factories: [String: @MainActor () -> any StageRenderer] = [:]

    /// Enregistre une factory pour un identifiant. Idempotent : un appel
    /// ultérieur avec le même id remplace silencieusement la factory précédente.
    @MainActor
    public static func register(id: String, factory: @escaping @MainActor () -> any StageRenderer) {
        factories[id] = factory
    }

    /// Crée une instance pour `id`. Retourne nil si non enregistrée.
    @MainActor
    public static func make(id: String) -> (any StageRenderer)? {
        factories[id]?()
    }

    /// `make(id) ?? make(defaultID)!` avec log warning si fallback déclenché.
    /// Précondition : le default DOIT être enregistré (vérifié au boot par
    /// `registerBuiltinRenderers`). Sinon trap fail-loud.
    @MainActor
    public static func makeOrFallback(id: String?) -> any StageRenderer {
        if let id = id, let renderer = make(id: id) { return renderer }
        if let id = id, !id.isEmpty {
            FileHandle.standardError.write(
                "renderer_unknown want=\(id) fallback=\(defaultID)\n".data(using: .utf8) ?? Data())
        }
        guard let fallback = make(id: defaultID) else {
            preconditionFailure("StageRendererRegistry: defaultID '\(defaultID)' missing — registerBuiltinRenderers() not called?")
        }
        return fallback
    }

    /// Identifiants enregistrés, triés lex pour stabilité.
    @MainActor
    public static var availableRenderers: [String] {
        factories.keys.sorted()
    }

    /// Tests-only.
    @MainActor
    public static func reset() {
        factories.removeAll()
    }
}
