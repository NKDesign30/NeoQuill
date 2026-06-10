import Foundation
import WhisperKit

/// Post-Recording-Transkription via WhisperKit (CoreML + ANE).
/// Fallback-Engine, wenn whisper-cli (`FinalSTTTranscriber`) nicht verfügbar ist —
/// läuft beim Stop einmal pro Stem über das volle Float-Array.
final class WhisperKitTranscriber: @unchecked Sendable {
    private var whisperKit: WhisperKit?
    private(set) var modelName: String
    private var languageHint: String

    init(modelName: String = "openai_whisper-small", language: String = "de") {
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

    /// Post-Recording Transkription — läuft den Whisper-Pass auf einem
    /// vollständigen Float-Array (statt 2s-Live-Chunks). Vorteile:
    /// - Kein RMS-Schwellen-Drop bei leisen Mic-Pegeln
    /// - Whisper sieht den ganzen Kontext (besser als chunk-by-chunk)
    func transcribeFull(audioData: [Float], speaker: String) async -> [TranscriptLine] {
        guard let kit = whisperKit else { return [] }
        guard !audioData.isEmpty else { return [] }
        let lang = languageHint == "auto" ? nil : languageHint
        let options = DecodingOptions(
            task: .transcribe,
            language: lang,
            usePrefillPrompt: true,
            skipSpecialTokens: true,
            withoutTimestamps: false,
            suppressBlank: true
        )
        do {
            let prepared = Self.prepareForSpeech(audioData)
            guard !prepared.isEmpty else { return [] }
            let results = try await kit.transcribe(audioArray: prepared, decodeOptions: options)
            var lines: [TranscriptLine] = []
            var lastText = ""
            for result in results {
                for segment in result.segments {
                    let raw = segment.text.trimmingCharacters(in: .whitespacesAndNewlines)
                    let cleaned = Self.cleanTokens(raw)
                    if cleaned.isEmpty { continue }
                    if cleaned.caseInsensitiveCompare(lastText) == .orderedSame { continue }
                    lastText = cleaned
                    let ts = TranscriptTimecode.stamp(TimeInterval(segment.start))
                    let isLocalSpeaker = LocalSpeakerProfile.isLocalSpeakerId(speaker)
                    lines.append(TranscriptLine(
                        who: speaker,
                        displayName: isLocalSpeaker ? LocalSpeakerProfile.displayName : nil,
                        timestamp: ts,
                        startSeconds: TimeInterval(segment.start),
                        endSeconds: TimeInterval(segment.end),
                        body: cleaned,
                        source: isLocalSpeaker ? .mic : .system,
                        speakerSource: isLocalSpeaker ? .microphoneOwner : .unknown,
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
        s = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.range(of: #"^\*[^*]+\*$"#, options: .regularExpression) != nil { return "" }
        let lower = s.lowercased()
        let noiseOnly = ["klirren", "musik", "applaus", "lachen", "husten", "räuspern"]
        if noiseOnly.contains(where: { lower == $0 || lower == "*\($0)*" }) { return "" }
        return s
    }

    static func prepareForSpeech(_ samples: [Float]) -> [Float] {
        guard !samples.isEmpty else { return [] }
        let cleaned = samples.map { $0.isFinite ? $0 : 0 }
        let rms = sqrt(cleaned.reduce(Float(0)) { $0 + $1 * $1 } / Float(cleaned.count))
        guard rms > 0.00035 else { return [] }
        let peak = cleaned.reduce(Float(0)) { max($0, abs($1)) }
        guard peak > 0 else { return [] }
        let gain = min(Float(16), Float(0.85) / peak)
        return cleaned.map { min(max($0 * gain, -0.95), 0.95) }
    }
}
