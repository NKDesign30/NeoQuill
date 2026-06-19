import Foundation

/// Führt einen einzelnen whisper-cli-Lauf für einen Audio-Chunk aus — mit
/// hartem Timeout und GPU-zuerst/CPU-Fallback.
///
/// Kapselt den Subprozess-Lebenszyklus, den `FinalSTTTranscriber` früher inline
/// hielt: ein nacktes `process.waitUntilExit()` ohne Obergrenze. Auf der CPU
/// (erzwungenes `--no-gpu`) konnte ein 35-min-Meeting dadurch über Stunden
/// laufen, ohne je abzubrechen. Dieses Modul gibt dem Lauf eine Deadline und
/// nutzt standardmäßig die Metal-GPU (Faktor ~11 schneller), mit CPU-Fallback
/// falls der GPU-Lauf scheitert.
enum TranscriptionJob {
    enum Failure: Error, Equatable {
        case timedOut(afterSeconds: TimeInterval)
        case processFailed(exitCode: Int32)
        case outputMissing
    }

    struct Spec {
        let executable: URL
        let model: URL
        let vadModel: URL?
        let language: String
        let inputURL: URL
        /// Ausgabepfad ohne Extension — whisper hängt `.json` an.
        let outputBaseURL: URL
        let threads: Int
        /// Harte Obergrenze pro Subprozess. Verhindert unbegrenztes Hängen.
        let timeout: TimeInterval
    }

    /// Dekodiert einen Chunk und gibt die erzeugte JSON-URL zurück. Versucht
    /// zuerst die GPU (Metal); scheitert der GPU-Lauf mit einem Prozessfehler,
    /// wird einmalig auf CPU zurückgefallen. Ein Timeout fällt NICHT zurück
    /// (die CPU wäre nur langsamer und liefe ebenfalls in die Deadline).
    static func decode(_ spec: Spec) throws -> URL {
        do {
            return try run(spec, useGPU: true)
        } catch Failure.processFailed {
            return try run(spec, useGPU: false)
        }
    }

    private static func run(_ spec: Spec, useGPU: Bool) throws -> URL {
        let jsonURL = spec.outputBaseURL.appendingPathExtension("json")
        try? FileManager.default.removeItem(at: jsonURL)

        let process = Process()
        process.executableURL = spec.executable
        var arguments: [String] = []
        if !useGPU { arguments.append("--no-gpu") }
        arguments += [
            "-t", String(spec.threads),
            "-mc", "0",
            "-m", spec.model.path,
            "-l", spec.language == "auto" ? "auto" : spec.language,
            "-f", spec.inputURL.path,
            "-oj",
            "-ojf",
            "-of", spec.outputBaseURL.path,
            "-sns",
            "--print-confidence",
        ]
        if let vad = spec.vadModel {
            arguments.append(contentsOf: ["--vad", "-vm", vad.path])
        }
        process.arguments = arguments
        process.environment = environment(for: spec.executable, useGPU: useGPU)
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        let finished = try runWithTimeout(process, seconds: spec.timeout)
        guard finished else { throw Failure.timedOut(afterSeconds: spec.timeout) }
        guard process.terminationStatus == 0 else {
            throw Failure.processFailed(exitCode: process.terminationStatus)
        }
        guard FileManager.default.fileExists(atPath: jsonURL.path) else {
            throw Failure.outputMissing
        }
        return jsonURL
    }

    private static func environment(for executable: URL, useGPU: Bool) -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        let executableDir = executable.deletingLastPathComponent()
        let backendName = useGPU ? "libggml-metal.so" : "libggml-cpu-apple_m1.so"
        let backend = executableDir.appendingPathComponent(backendName)
        if FileManager.default.fileExists(atPath: backend.path) {
            environment["GGML_BACKEND_PATH"] = backend.path
        }
        return environment
    }

    /// Startet `process` und wartet maximal `seconds`. Endet der Prozess von
    /// selbst, wird `true` zurückgegeben. Läuft er in die Deadline, wird er hart
    /// beendet (SIGTERM, nach 2 s SIGKILL) und `false` zurückgegeben.
    ///
    /// Der `terminationHandler` wird vor `run()` gesetzt, damit ein sehr kurzer
    /// Prozess das Signal nicht verpassen kann.
    static func runWithTimeout(_ process: Process, seconds: TimeInterval) throws -> Bool {
        let done = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in done.signal() }
        try process.run()

        if done.wait(timeout: .now() + seconds) == .success { return true }

        process.terminate()
        if done.wait(timeout: .now() + 2) == .timedOut {
            kill(process.processIdentifier, SIGKILL)
            done.wait()
        }
        return false
    }
}
