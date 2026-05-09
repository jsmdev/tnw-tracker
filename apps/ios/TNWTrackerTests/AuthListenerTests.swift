import Foundation
import Testing
@testable import TNWTracker
@testable import TNWTrackerKit

@Suite("Auth listener cancellation")
@MainActor
struct AuthListenerTests {
    // MARK: - Test 1: procesamiento de evento signedIn

    @Test("Listener procesa evento signedIn y actualiza isAuthenticated")
    func processesSignedIn() async throws {
        let mock = AuthRepositoryMock()
        let env = AppEnvironment.makeForTesting(authRepository: mock)
        env.startAuthListener()
        await Task.yield()

        #expect(mock.streamCreatedCount == 1)

        mock.emit(.signedIn)
        // Dar tiempo al MainActor para procesar el evento
        try await Task.sleep(for: .milliseconds(100))

        #expect(env.isAuthenticated == true)
    }

    // MARK: - Test 2: stopAuthListener detiene el procesamiento

    @Test("stopAuthListener cancela la task y no procesa eventos posteriores")
    func cancelStopsProcessing() async throws {
        let mock = AuthRepositoryMock()
        let env = AppEnvironment.makeForTesting(authRepository: mock)
        env.startAuthListener()
        await Task.yield()

        let initialAuth = env.isAuthenticated
        env.stopAuthListener()
        await Task.yield()

        mock.emit(.signedIn)
        try await Task.sleep(for: .milliseconds(100))

        #expect(env.isAuthenticated == initialAuth)
    }

    // MARK: - Test 3: deinit cancela la Task (no retain cycle)

    @Test("deinit cancela authListenerTask — Task no retiene al env")
    func deinitCancelsAuthListenerTask() async throws {
        let mock = AuthRepositoryMock()
        weak var weakEnv: AppEnvironment?

        do {
            let env = AppEnvironment.makeForTesting(authRepository: mock)
            env.startAuthListener()
            await Task.yield()
            weakEnv = env
            #expect(mock.streamCreatedCount == 1)
        }

        // Dar tiempo a ARC para liberar y a onTermination para dispararse
        try await Task.sleep(for: .milliseconds(200))

        // Con el fix: Task usa [weak self] → no retiene AppEnvironment → ARC libera → weakEnv == nil
        #expect(weakEnv == nil)
        // El stream debería haberse terminado (onTermination del AsyncStream)
        #expect(mock.streamTerminatedCount == 1)
    }

    // MARK: - Test 4: re-init no deja listener anterior activo

    @Test("startAuthListener llamado dos veces solo deja 1 listener activo")
    func reInitDoesNotLeavePriorListenerActive() async throws {
        let mock = AuthRepositoryMock()
        let env = AppEnvironment.makeForTesting(authRepository: mock)

        env.startAuthListener()
        await Task.yield()
        #expect(mock.activeStreamCount == 1)

        // Segunda llamada — debe cancelar el primer listener antes de crear el nuevo
        env.startAuthListener()
        await Task.yield()
        try await Task.sleep(for: .milliseconds(100))

        // Solo 1 stream activo al mismo tiempo
        #expect(mock.activeStreamCount == 1)
        #expect(mock.streamCreatedCount == 2)
        #expect(mock.streamTerminatedCount == 1)
    }
}
