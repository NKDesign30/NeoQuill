import Foundation

enum AudioPlaybackFileCorrector {
    private static let sampleRate: Double = 16_000
    private static let defaultMaximumExpansionFactor = 4.0

    static func renderCorrectedCopy(
        from sourceURL: URL,
        expectedDuration: TimeInterval,
        correctionRate: Float,
        maximumExpansionFactor: Double = defaultMaximumExpansionFactor
    ) throws -> URL? {
        guard expectedDuration.isFinite,
              expectedDuration > 0,
              correctionRate.isFinite,
              correctionRate > 0,
              correctionRate < 1,
              maximumExpansionFactor >= 1 else { return nil }

        let targetFrames = expectedDuration * sampleRate
        guard targetFrames.isFinite,
              targetFrames > 0,
              targetFrames <= Double(Int.max) else { return nil }

        let samples = try AudioWriter.readSamples(from: sourceURL)
        guard !samples.isEmpty else { return nil }

        let targetCount = Int(targetFrames.rounded())
        let expansionFactor = Double(targetCount) / Double(samples.count)
        guard targetCount > samples.count,
              expansionFactor <= maximumExpansionFactor else { return nil }

        let correctedSamples = resample(samples: samples, targetCount: targetCount)
        let correctedURL = try correctedURL(sourceURL: sourceURL, expectedDuration: expectedDuration)
        try? FileManager.default.removeItem(at: correctedURL)
        try AudioWriter.writePlaybackCompatibleWav(samples: correctedSamples, to: correctedURL)
        return correctedURL
    }

    static func resample(samples: [Float], targetCount: Int) -> [Float] {
        guard !samples.isEmpty, targetCount > 0 else { return [] }
        guard targetCount != samples.count else { return samples }
        guard samples.count > 1 else { return Array(repeating: samples[0], count: targetCount) }
        guard targetCount > 1 else { return [samples[0]] }

        let sourceLastIndex = Double(samples.count - 1)
        let targetLastIndex = Double(targetCount - 1)

        return (0..<targetCount).map { index in
            let position = Double(index) * sourceLastIndex / targetLastIndex
            let lowerIndex = Int(position.rounded(.down))
            let upperIndex = min(lowerIndex + 1, samples.count - 1)
            let fraction = Float(position - Double(lowerIndex))
            let lower = samples[lowerIndex]
            let upper = samples[upperIndex]
            return lower + (upper - lower) * fraction
        }
    }

    private static func correctedURL(sourceURL: URL, expectedDuration: TimeInterval) throws -> URL {
        let directory = try correctionsDirectory()
        let sourceValues = try? sourceURL.resourceValues(forKeys: [.contentModificationDateKey])
        let sourceStamp = Int(sourceValues?.contentModificationDate?.timeIntervalSince1970 ?? 0)
        let expectedMillis = Int((expectedDuration * 1_000).rounded())
        let stem = sanitizedFileStem(sourceURL.deletingPathExtension().lastPathComponent)
        return directory.appendingPathComponent("\(stem)-\(expectedMillis)-\(sourceStamp).wav")
    }

    private static func correctionsDirectory() throws -> URL {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let directory = base.appendingPathComponent("NeoQuill/PlaybackCorrections", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private static func sanitizedFileStem(_ stem: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let result = String(stem.unicodeScalars.map { scalar in
            allowed.contains(scalar) ? Character(scalar) : "-"
        })
        return result.isEmpty ? "audio" : result
    }
}
