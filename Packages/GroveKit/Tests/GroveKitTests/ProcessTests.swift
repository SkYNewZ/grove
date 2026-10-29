import Foundation
import Testing

@testable import GroveKit

struct ProcessTests {
    @Test func killsAndReportsAProcessThatOutlivesItsTimeout() async throws {
        let started = ContinuousClock.now
        await #expect(throws: ProcessTimeout.self) {
            try await ProcessRunner().run(
                "/bin/sleep", ["5"], cwd: URL(fileURLWithPath: "/"), timeout: .milliseconds(200))
        }
        #expect(ContinuousClock.now - started < .seconds(3))
    }

    @Test func probeFindsAProcessWorkingInsideTheDirectory() async throws {
        let fixture = try GitFixture()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sleep")
        process.arguments = ["5"]
        process.currentDirectoryURL = fixture.root
        try process.run()
        defer { process.terminate() }

        let found = await ProcessProbe().processes(withCwdUnder: fixture.root.path)

        #expect(found.contains { $0.hasPrefix("sleep (") })
        #expect(
            await ProcessProbe().processes(withCwdUnder: fixture.root.appending(path: "other").path).isEmpty)
    }

    @Test func aChildThatIgnoresItsInputDoesNotKillTheApp() async throws {
        let out = try await ProcessRunner().run(
            "/bin/sh", ["-c", "exit 3"], cwd: URL(fileURLWithPath: "/"), input: Data(count: 500_000))
        #expect(out.status == 3)
    }
}
