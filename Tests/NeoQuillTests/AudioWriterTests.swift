import AVFoundation
import XCTest
@testable import NeoQuill

final class AudioWriterTests: XCTestCase {
    func testPersistWritesPlaybackCompatiblePcm16Wav() throws {
        let id = "test-\(UUID().uuidString)"
        let url = AudioWriter.url(id: id, stem: .mix)
        defer { try? FileManager.default.removeItem(at: url) }

        let samples = (0..<1_600).map { index in
            Float(sin(Double(index) * 0.03)) * 0.25
        }

        let written = try XCTUnwrap(AudioWriter.persist(id: id, stem: .mix, samples: samples))
        let file = try AVAudioFile(forReading: written)

        XCTAssertEqual(file.fileFormat.sampleRate, 16_000, accuracy: 0.1)
        XCTAssertEqual(file.fileFormat.channelCount, 1)
        XCTAssertEqual(file.fileFormat.commonFormat, .pcmFormatInt16)

        let readBack = try AudioWriter.readSamples(from: written)
        XCTAssertEqual(readBack.count, samples.count)
    }
}
