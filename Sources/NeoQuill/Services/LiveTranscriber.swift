import Foundation
import WhisperKit

/// Live-Transkription via WhisperKit (CoreML + ANE)
final class LiveTranscriber: @unchecked Sendable {
    private var whisperKit: WhisperKit?
    private(set) var modelName: String
    private var languageHint: String
    private var isBusy = false
    private let queue = DispatchQueue(label: "com.neon.neoquill.transcriber", qos: .userInitiated)

    /// Callback für neue Segmente
    var onSegment: (@Sendable (TranscriptSegment) -> Void)?

    init(modelName: String = "openai_whisper-tiny", language: String = "de") {
        self.modelName = modelName
        self.languageHint = language
    }

    /// Lädt das WhisperKit-Modell (Download bei erstem Start)
    /// — Falls `model` oder `language` sich geändert haben, wird neu geladen.
    func loadModel(model: String? = nil, language: String? = nil) async -> Bool {
        let targetModel = model ?? modelName
        let targetLang  = language ?? languageHint
        let needsReload = whisperKit == nil
            || targetModel != modelName
            || targetLang != languageHint

        if !needsReload { return true }

        modelName = targetModel
        languageHint = targetLang
        whisperKit = nil

        do {
            let config = WhisperKitConfig(
                model: modelName,
                verbose: false,
                logLevel: .none
            )
            whisperKit = try await WhisperKit(config)
            print("[NeoQuill] WhisperKit geladen (\(modelName), lang=\(languageHint))")
            return true
        } catch {
            print("[NeoQuill] WhisperKit laden fehlgeschlagen: \(error)")
            return false
        }
    }

    /// Transkribiert einen Audio-Chunk (Float32 PCM, 16kHz Mono)
    func transcribe(audioData: [Float], sampleRate: Int = 16000, offset: TimeInterval = 0) {
        guard whisperKit != nil else { return }
        guard !isBusy else { return }

        // Einfacher Energy-Check — Stille rausfiltern
        let rms = sqrt(audioData.reduce(0) { $0 + $1 * $1 } / Float(max(audioData.count, 1)))
        guard rms > 0.005 else { return }

        isBusy = true
        let callback = self.onSegment
        let kit = self.whisperKit!

        Task.detached(priority: .userInitiated) { [weak self] in
            do {
                let results = try await kit.transcribe(audioArray: audioData)

                for result in results {
                    for segment in result.segments {
                        let text = segment.text.trimmingCharacters(in: .whitespacesAndNewlines)
                        if text.isEmpty { continue }

                        // Whisper-Artefakte filtern
                        let lower = text.lowercased()
                        if lower.hasPrefix("[") && lower.hasSuffix("]") { continue }
                        if lower.hasPrefix("(") && lower.hasSuffix(")") { continue }
                        if lower.contains("♪") || lower.contains("♫") { continue }

                        let seg = TranscriptSegment(
                            text: text,
                            start: offset + Double(segment.start),
                            end: offset + Double(segment.end)
                        )

                        await MainActor.run {
                            callback?(seg)
                        }
                    }
                }
            } catch {
                print("[Quill] Transkription fehlgeschlagen: \(error)")
            }

            let transcriber = self
            await MainActor.run {
                transcriber?.isBusy = false
            }
        }
    }

    /// Gibt Ressourcen frei
    func unloadModel() {
        whisperKit = nil
        print("[Quill] WhisperKit-Modell entladen")
    }

    deinit {
        unloadModel()
    }
}
