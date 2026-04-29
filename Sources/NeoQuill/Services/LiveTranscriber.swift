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

    init(modelName: String = "openai_whisper-base", language: String = "de") {
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

        let lang = languageHint == "auto" ? nil : languageHint
        let options = DecodingOptions(
            task: .transcribe,
            language: lang,
            usePrefillPrompt: true,
            skipSpecialTokens: true,
            withoutTimestamps: false
        )

        Task.detached(priority: .userInitiated) { [weak self] in
            do {
                let results = try await kit.transcribe(audioArray: audioData, decodeOptions: options)

                for result in results {
                    for segment in result.segments {
                        let raw = segment.text.trimmingCharacters(in: .whitespacesAndNewlines)
                        let text = Self.cleanTokens(raw)
                        if text.isEmpty { continue }

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
                print("[NeoQuill] Transkription fehlgeschlagen: \(error)")
            }

            let transcriber = self
            await MainActor.run {
                transcriber?.isBusy = false
            }
        }
    }

    /// Post-Recording Transkription — laeuft den Whisper-Pass auf einem
    /// vollstaendigen Float-Array (statt 2s-Live-Chunks). Vorteile:
    /// - Kein RMS-Schwellen-Drop bei leisen Mic-Pegeln
    /// - Whisper sieht den ganzen Kontext (besser als chunk-by-chunk)
    /// - Kein `isBusy`-Lock-Drop bei parallelen Streams
    func transcribeFull(audioData: [Float], speaker: String) async -> [TranscriptLine] {
        guard let kit = whisperKit else { return [] }
        guard !audioData.isEmpty else { return [] }
        let lang = languageHint == "auto" ? nil : languageHint
        let options = DecodingOptions(
            task: .transcribe,
            language: lang,
            usePrefillPrompt: true,
            skipSpecialTokens: true,
            withoutTimestamps: false
        )
        do {
            let results = try await kit.transcribe(audioArray: audioData, decodeOptions: options)
            var lines: [TranscriptLine] = []
            for result in results {
                for segment in result.segments {
                    let raw = segment.text.trimmingCharacters(in: .whitespacesAndNewlines)
                    let cleaned = Self.cleanTokens(raw)
                    if cleaned.isEmpty { continue }
                    let mins = Int(segment.start) / 60
                    let secs = Int(segment.start) % 60
                    let ts = String(format: "%02d:%02d", mins, secs)
                    lines.append(TranscriptLine(
                        who: speaker,
                        timestamp: ts,
                        body: cleaned,
                        highlight: false
                    ))
                }
            }
            return lines
        } catch {
            print("[NeoQuill] Post-Recording-Transkription fehlgeschlagen (\(speaker)): \(error)")
            return []
        }
    }

    /// Gibt Ressourcen frei
    func unloadModel() {
        whisperKit = nil
        print("[NeoQuill] WhisperKit-Modell entladen")
    }

    deinit {
        unloadModel()
    }

    /// Räumt Whisper-Special-Tokens aus dem Output (`<|startoftranscript|>`,
    /// `<|en|>`, `<|0.00|>`, `<|endoftext|>` etc.) plus die typischen Brackets.
    static func cleanTokens(_ raw: String) -> String {
        var s = raw
        // <|...|> Tokens
        while let start = s.range(of: "<|"),
              let end = s.range(of: "|>", range: start.upperBound..<s.endIndex) {
            s.removeSubrange(start.lowerBound..<end.upperBound)
        }
        // [Music], [Applause]
        if let r = s.range(of: #"^\[.*\]$"#, options: .regularExpression) {
            s.removeSubrange(r)
        }
        // (Hintergrund), (laughter)
        if let r = s.range(of: #"^\(.*\)$"#, options: .regularExpression) {
            s.removeSubrange(r)
        }
        if s.contains("♪") || s.contains("♫") { return "" }
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
