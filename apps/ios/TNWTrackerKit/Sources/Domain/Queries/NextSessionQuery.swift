import Foundation
import SwiftData

/// Consulta el próximo Session disponible desde SwiftData.
/// Usado por el Widget para mostrar la próxima sesión planificada.
public struct NextSessionQuery {
    private let modelContext: ModelContext

    public init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    /// Devuelve el nombre de la próxima sesión activa, o nil si no hay ninguna.
    /// Actualmente devuelve la primera sesión activa ordenada por nombre.
    /// En una implementación completa consultaría el plan activo del usuario.
    public func nextSessionName() -> String? {
        var descriptor = FetchDescriptor<Session>(
            sortBy: [SortDescriptor(\.name)]
        )
        descriptor.fetchLimit = 1
        return (try? modelContext.fetch(descriptor))?.first?.name
    }
}
