import Foundation
import SwiftData
import Testing
@testable import TNWTrackerKit

@Suite("SeedService", .serialized)
struct SeedServiceTests {
    let container: ModelContainer

    init() throws {
        container = try ModelContainerFactory.makeContainer(inMemory: true)
    }

    @Test("seedIfNeeded inserta 1 plan, 3 rutinas y ≥5 ejercicios en store vacío")
    func seedCreatesExpectedEntities() throws {
        let context = ModelContext(container)
        try SeedService.seedIfNeeded(context: context)

        let plans = try context.fetch(FetchDescriptor<Plan>())
        let routines = try context.fetch(FetchDescriptor<Routine>())
        let exercises = try context.fetch(FetchDescriptor<Exercise>())

        #expect(plans.count == 1)
        #expect(routines.count == 3)
        #expect(exercises.count >= 5)
    }

    @Test("seedIfNeeded es idempotente — llamar dos veces no duplica datos")
    func seedIsIdempotent() throws {
        let context = ModelContext(container)
        try SeedService.seedIfNeeded(context: context)
        try SeedService.seedIfNeeded(context: context)

        let plans = try context.fetch(FetchDescriptor<Plan>())
        let routines = try context.fetch(FetchDescriptor<Routine>())
        let exercises = try context.fetch(FetchDescriptor<Exercise>())

        #expect(plans.count == 1)
        #expect(routines.count == 3)
        #expect(exercises.count >= 5)
    }
}
