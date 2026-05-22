import AVFoundation
import Foundation

// Dekodiert eine beliebige Audiodatei (iPhone-Sprachmemo .m4a/AAC, .mp3,
// .wav, .aiff, .caf) zu 16kHz Mono Float32 — exakt das Format, das
// WhisperKit/Final-STT erwartet. Resampling + Downmix laufen über einen
// AVAudioConverter, chunk-weise, damit auch stundenlange Aufnahmen nicht
// als ein einziger Riesen-Buffer in den RAM gezogen werden.

enum AudioImportError: LocalizedError {
    case unreadable(String)
    case emptyAudio
    case conversionUnavailable
    case conversionFailed(String)

    var errorDescription: String? {
        switch self {
        case .unreadable(let detail):
            return "Audiodatei konnte nicht gelesen werden: \(detail)"
        case .emptyAudio:
            return "Die Audiodatei enthält keine Audiodaten."
        case .conversionUnavailable:
            return "Audioformat wird nicht unterstützt."
        case .conversionFailed(let detail):
            return "Audio-Konvertierung fehlgeschlagen: \(detail)"
        }
    }
}

enum AudioImporter {

    static let targetSampleRate: Double = 16_000

    /// Unterstützte Eingabe-Dateiendungen für den Open-Panel-Filter.
    static let supportedExtensions: [String] = ["m4a", "mp3", "wav", "aiff", "aif", "caf", "aac", "mp4"]

    /// Liest `url` und gibt 16kHz Mono Float32 zurück. Wirft bei kaputten
    /// oder leeren Dateien. Läuft synchron — Aufrufer sollte das in einen
    /// Hintergrund-Task legen, da das Decoding CPU-gebunden ist.
    static func decodeToWhisperSamples(url: URL) throws -> [Float] {
        let file: AVAudioFile
        do {
            file = try AVAudioFile(forReading: url)
        } catch {
            throw AudioImportError.unreadable(error.localizedDescription)
        }

        guard file.length > 0 else { throw AudioImportError.emptyAudio }

        let inFormat = file.processingFormat
        guard let outFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: targetSampleRate,
            channels: 1,
            interleaved: false
        ) else {
            throw AudioImportError.conversionUnavailable
        }

        guard let converter = AVAudioConverter(from: inFormat, to: outFormat) else {
            throw AudioImportError.conversionUnavailable
        }

        let readChunk: AVAudioFrameCount = 16_384
        let ratio = outFormat.sampleRate / inFormat.sampleRate
        // Output-Kapazität großzügig dimensionieren (Ratio + Polster), damit
        // ein Convert-Aufruf den ganzen Input-Chunk aufnehmen kann.
        let outCapacity = AVAudioFrameCount(Double(readChunk) * max(ratio, 1) + 4_096)

        var output: [Float] = []
        output.reserveCapacity(Int(Double(file.length) * ratio) + Int(outCapacity))

        var reachedEnd = false

        while !reachedEnd {
            guard let outBuffer = AVAudioPCMBuffer(pcmFormat: outFormat, frameCapacity: outCapacity) else {
                throw AudioImportError.conversionFailed("Output-Buffer konnte nicht angelegt werden.")
            }

            var convError: NSError?
            let status = converter.convert(to: outBuffer, error: &convError) { _, inputStatus in
                guard let inBuffer = AVAudioPCMBuffer(pcmFormat: inFormat, frameCapacity: readChunk) else {
                    inputStatus.pointee = .endOfStream
                    return nil
                }
                do {
                    try file.read(into: inBuffer, frameCount: readChunk)
                } catch {
                    inputStatus.pointee = .endOfStream
                    return nil
                }
                if inBuffer.frameLength == 0 {
                    inputStatus.pointee = .endOfStream
                    return nil
                }
                inputStatus.pointee = .haveData
                return inBuffer
            }

            if let convError {
                throw AudioImportError.conversionFailed(convError.localizedDescription)
            }

            if outBuffer.frameLength > 0, let channel = outBuffer.floatChannelData?[0] {
                output.append(contentsOf: UnsafeBufferPointer(start: channel, count: Int(outBuffer.frameLength)))
            }

            switch status {
            case .endOfStream, .error:
                reachedEnd = true
            case .inputRanDry where outBuffer.frameLength == 0:
                reachedEnd = true
            default:
                break
            }
        }

        guard !output.isEmpty else { throw AudioImportError.emptyAudio }
        return output
    }
}
