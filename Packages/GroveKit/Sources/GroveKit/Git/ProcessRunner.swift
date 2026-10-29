import Foundation

public struct ProcessOutput: Sendable {
    public let status: Int32
    public let stdout: Data
    public let stderr: String

    public var stdoutString: String { String(decoding: stdout, as: UTF8.self) }
}

public struct ProcessTimeout: Error, Equatable, Sendable {
    public let executable: String
    public let arguments: [String]
}

/// The single door to sub-processes: argument arrays only, explicit cwd, no shell.
public struct ProcessRunner: Sendable {
    private let environment: [String: String]

    /// `environment` overrides are merged over the current process environment (read once, here).
    public init(environment: [String: String] = [:]) {
        self.environment = ProcessInfo.processInfo.environment.merging(environment) { $1 }
    }

    /// Kills the process and throws `ProcessTimeout` when it runs longer than `timeout`.
    public func run(
        _ executable: String, _ arguments: [String], cwd: URL, input: Data? = nil,
        timeout: Duration = .seconds(60)
    ) async throws -> ProcessOutput {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.currentDirectoryURL = cwd
        process.environment = environment
        // Without `input`, a tool asking for input must fail, not wait.
        let stdin = Pipe()
        process.standardInput = input == nil ? FileHandle.nullDevice : stdin
        let out = Pipe()
        let err = Pipe()
        process.standardOutput = out
        process.standardError = err

        // shortcut: two blocking reads on the cooperative pool, fine for a handful of git calls at once;
        // cap git concurrency (or switch to a dedicated executor) when scans run many repos in parallel.
        let outHandle = out.fileHandleForReading
        let errHandle = err.fileHandleForReading
        async let stdout = Task.detached { outHandle.readDataToEndOfFile() }.value
        async let stderr = Task.detached { errHandle.readDataToEndOfFile() }.value

        let running = process  // only `terminate()` is called from the watchdog
        let watchdog = Task {
            try await Task.sleep(for: timeout)
            if running.isRunning { running.terminate() }
        }
        defer { watchdog.cancel() }

        let (status, reason): (Int32, Process.TerminationReason) =
            try await withCheckedThrowingContinuation { continuation in
                process.terminationHandler = {
                    continuation.resume(returning: ($0.terminationStatus, $0.terminationReason))
                }
                do {
                    try process.run()
                    if let input {
                        // A child that exits without reading must give EPIPE, not kill Grove with SIGPIPE; and the
                        // parent's copy of the read end must go, or the write would block instead of failing.
                        let writer = stdin.fileHandleForWriting
                        _ = fcntl(writer.fileDescriptor, F_SETNOSIGPIPE, 1)
                        try? stdin.fileHandleForReading.close()
                        Task.detached {
                            try? writer.write(contentsOf: input)
                            try? writer.close()
                        }
                    }
                } catch {
                    // Without this the readers above wait forever for an EOF that never comes.
                    try? out.fileHandleForWriting.close()
                    try? err.fileHandleForWriting.close()
                    continuation.resume(throwing: error)
                }
            }
        if reason == .uncaughtSignal, status == SIGTERM {
            throw ProcessTimeout(executable: executable, arguments: arguments)
        }
        return ProcessOutput(
            status: status, stdout: await stdout, stderr: String(decoding: await stderr, as: UTF8.self))
    }
}
