import Foundation

/// Quill v2 Post-Processing: Ruft die v2 Pipeline auf (faster-whisper + pyannote CPU-only)
/// Kann entweder direkt via Python oder über den Quill-Server arbeiten.
final class PostProcessor: @unchecked Sendable {
    static let scriptDir = "/Users/nikoknez/.claude/meeting-scribe"
    static let meetingsDir = "/Users/nikoknez/.claude/meeting-scribe/meetings"
    static let serverURL = "http://127.0.0.1:8765"

    // MARK: - Server Management

    /// Prüft ob der Quill-Server läuft
    static func isServerRunning() -> Bool {
        guard let url = URL(string: "\(serverURL)/health") else { return false }
        var request = URLRequest(url: url, timeoutInterval: 2)
        request.httpMethod = "GET"
        let semaphore = DispatchSemaphore(value: 0)
        var running = false
        URLSession.shared.dataTask(with: request) { data, response, _ in
            if let http = response as? HTTPURLResponse, http.statusCode == 200 {
                running = true
            }
            semaphore.signal()
        }.resume()
        semaphore.wait()
        return running
    }

    /// Startet den Quill-Server falls nicht aktiv
    @discardableResult
    static func ensureServerRunning() -> Bool {
        if isServerRunning() { return true }

        print("[Quill] Server nicht aktiv, starte...")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-c", "source ~/.zshrc 2>/dev/null; cd '\(scriptDir)'; nohup python3 quill_server.py > /tmp/quill-server.log 2>&1 &"]
        var env = ProcessInfo.processInfo.environment
        env["PYTORCH_MPS_DEVICE_DISABLED"] = "1"
        env.removeValue(forKey: "CLAUDECODE")
        process.environment = env

        do {
            try process.run()
            process.waitUntilExit()
            // Warten bis Server bereit ist
            for _ in 0..<10 {
                Thread.sleep(forTimeInterval: 1)
                if isServerRunning() {
                    print("[Quill] Server gestartet")
                    return true
                }
            }
            print("[Quill] Server-Start Timeout")
            return false
        } catch {
            print("[Quill] Server-Start Fehler: \(error)")
            return false
        }
    }

    // MARK: - Processing

    /// Speichert Audio als WAV und startet v2 Pipeline
    static func process(audio: [Float], sampleRate: Int = 16000,
                        meetingName: String, meetingType: String = "default") async -> String? {
        let timestamp = Self.timestamp()
        let safeName = meetingName.replacingOccurrences(of: " ", with: "-")
            .filter { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }
        let filename = "\(timestamp)_\(safeName)"
        let wavPath = "\(meetingsDir)/\(filename).wav"

        try? FileManager.default.createDirectory(atPath: meetingsDir,
                                                   withIntermediateDirectories: true)

        guard writeWAV(audio: audio, sampleRate: sampleRate, path: wavPath) else {
            print("[Quill] WAV schreiben fehlgeschlagen: \(wavPath)")
            return nil
        }

        print("[Quill] WAV gespeichert: \(wavPath) (\(audio.count / sampleRate)s)")

        let mdPath = "\(meetingsDir)/\(filename).md"
        let success = await runV2Pipeline(wavPath: wavPath, meetingName: meetingName,
                                           meetingType: meetingType)

        return success ? mdPath : nil
    }

    /// Ruft die v2 Pipeline auf (faster-whisper + pyannote CPU-only + LLM-Analyse)
    private static func runV2Pipeline(wavPath: String, meetingName: String,
                                       meetingType: String) async -> Bool {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                let pythonScript = """
                import os, sys
                os.environ["PYTORCH_MPS_DEVICE_DISABLED"] = "1"
                os.environ["TOKENIZERS_PARALLELISM"] = "false"
                sys.path.insert(0, '\(scriptDir)')

                from pipeline_v2 import run_pipeline
                import yaml

                # Config laden
                cfg = {}
                try:
                    with open('\(scriptDir)/config.yaml') as f:
                        cfg = yaml.safe_load(f) or {}
                except Exception:
                    pass

                result = run_pipeline(
                    '\(wavPath)',
                    '\(meetingName.replacingOccurrences(of: "'", with: "\\'"))',
                    meeting_type='\(meetingType)',
                    config=cfg,
                )
                print(f"Pipeline: {result['status']}")
                if result['status'] != 'completed':
                    sys.exit(1)
                """

                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/Library/Frameworks/Python.framework/Versions/3.12/bin/python3")
                process.arguments = ["-u", "-c", pythonScript]

                var env = ProcessInfo.processInfo.environment
                env.removeValue(forKey: "CLAUDECODE")
                env["PYTORCH_MPS_DEVICE_DISABLED"] = "1"
                env["TOKENIZERS_PARALLELISM"] = "false"
                let extraPaths = [
                    "/opt/homebrew/bin",
                    "/usr/local/bin",
                    "/Library/Frameworks/Python.framework/Versions/3.12/bin"
                ]
                let currentPath = env["PATH"] ?? "/usr/bin:/bin"
                env["PATH"] = (extraPaths + [currentPath]).joined(separator: ":")
                env["HOME"] = env["HOME"] ?? "/Users/nikoknez"
                process.environment = env
                process.currentDirectoryURL = URL(fileURLWithPath: scriptDir)

                let pipe = Pipe()
                process.standardOutput = pipe
                process.standardError = pipe

                do {
                    try process.run()
                    process.waitUntilExit()

                    let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                    if process.terminationStatus != 0 {
                        print("[Quill] v2 Pipeline Exit \(process.terminationStatus): \(output.suffix(500))")
                    } else {
                        print("[Quill] v2 Pipeline OK")
                    }
                    continuation.resume(returning: process.terminationStatus == 0)
                } catch {
                    print("[Quill] v2 Pipeline Fehler: \(error)")
                    continuation.resume(returning: false)
                }
            }
        }
    }

    /// Verarbeitet eine bereits gespeicherte WAV-Datei
    static func processExistingWav(wavPath: String) async -> String? {
        let url = URL(fileURLWithPath: wavPath)
        let stem = url.deletingPathExtension().lastPathComponent
        let parts = stem.split(separator: "_").dropFirst(2)
        let meetingName = parts.isEmpty ? stem :
            parts.joined(separator: " ").replacingOccurrences(of: "-", with: " ")
        let mdPath = url.deletingPathExtension().path + ".md"
        let success = await runV2Pipeline(wavPath: wavPath, meetingName: meetingName, meetingType: "default")
        return success ? mdPath : nil
    }

    /// Scannt nach WAVs ohne passendes .md und verarbeitet sie
    static func processAllPendingWavs() async {
        guard let files = try? FileManager.default.contentsOfDirectory(atPath: meetingsDir) else { return }
        let wavFiles = files.filter { $0.hasSuffix(".wav") }
        for wav in wavFiles {
            let base = (wav as NSString).deletingPathExtension
            let hasMd = files.contains(base + ".md")
            if !hasMd {
                print("[Quill] Auto-Processing pending WAV: \(wav)")
                _ = await processExistingWav(wavPath: "\(meetingsDir)/\(wav)")
            }
        }
    }

    // MARK: - WAV Writer

    private static func writeWAV(audio: [Float], sampleRate: Int, path: String) -> Bool {
        let numSamples = audio.count
        let dataSize = numSamples * 2
        let fileSize = 44 + dataSize

        var data = Data(capacity: fileSize)

        data.append(contentsOf: "RIFF".utf8)
        data.append(contentsOf: withUnsafeBytes(of: UInt32(fileSize - 8).littleEndian) { Array($0) })
        data.append(contentsOf: "WAVE".utf8)

        data.append(contentsOf: "fmt ".utf8)
        data.append(contentsOf: withUnsafeBytes(of: UInt32(16).littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: UInt16(1).littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: UInt16(1).littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: UInt32(sampleRate).littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: UInt32(sampleRate * 2).littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: UInt16(2).littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: UInt16(16).littleEndian) { Array($0) })

        data.append(contentsOf: "data".utf8)
        data.append(contentsOf: withUnsafeBytes(of: UInt32(dataSize).littleEndian) { Array($0) })

        for sample in audio {
            let clamped = max(-1.0, min(1.0, sample))
            let int16 = Int16(clamped * 32767)
            data.append(contentsOf: withUnsafeBytes(of: int16.littleEndian) { Array($0) })
        }

        return FileManager.default.createFile(atPath: path, contents: data)
    }

    private static func timestamp() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd_HH-mm"
        return f.string(from: Date())
    }
}
