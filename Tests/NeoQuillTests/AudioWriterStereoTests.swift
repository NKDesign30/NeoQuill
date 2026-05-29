import AVFoundation
import XCTest
@testable import NeoQuill

/// Locks down the high-resolution stereo archive path added to fix the muffled
/// 16 kHz-mono recording. The mono `.mix` API stays covered by AudioWriterTests;
/// these guard the new `persistStereo` / `.hq` contract.
final class AudioWriterStereoTests: XCTestCase {
    func testPersistStereoWrites48kHzTwoChannelWav() throws {
        let id = "stereo-\(UUID().uuidString)"
        let url = AudioWriter.url(id: id, stem: .hq)
        defer { try? FileManager.default.removeItem(at: url) }

        let left = (0..<4_800).map { Float(sin(Double($0) * 0.02)) * 0.3 }
        let right = (0..<4_800).map { Float(cos(Double($0) * 0.02)) * 0.3 }

        let written = try XCTUnwrap(AudioWriter.persistStereo(id: id, stem: .hq, left: left, right: right))
        let file = try AVAudioFile(forReading: written)

        XCTAssertEqual(file.fileFormat.sampleRate, 48_000, accuracy: 0.1)
        XCTAssertEqual(file.fileFormat.channelCount, 2)
        XCTAssertEqual(file.length, 4_800)
    }

    func testPersistStereoPadsShorterChannelToMaxLength() throws {
        let id = "stereo-pad-\(UUID().uuidString)"
        let url = AudioWriter.url(id: id, stem: .hq)
        defer { try? FileManager.default.removeItem(at: url) }

        let left = Array(repeating: Float(0.2), count: 9_600)   // longer (mic)
        let right = Array(repeating: Float(0.1), count: 4_800)  // shorter (system)

        let written = try XCTUnwrap(AudioWriter.persistStereo(id: id, stem: .hq, left: left, right: right))
        let file = try AVAudioFile(forReading: written)
        XCTAssertEqual(file.length, 9_600)  // padded to the longer channel
        XCTAssertEqual(file.fileFormat.channelCount, 2)
    }

    func testPersistStereoReturnsNilForEmptyInput() throws {
        let id = "stereo-empty-\(UUID().uuidString)"
        let result = try AudioWriter.persistStereo(id: id, stem: .hq, left: [], right: [])
        XCTAssertNil(result)
    }

    func testHQStemHasDistinctSuffixWithoutBreakingMixContract() {
        XCTAssertEqual(RecordingAudioStem.hq.suffix, ".hq")
        XCTAssertTrue(AudioWriter.url(id: "abc", stem: .hq).lastPathComponent.hasSuffix(".hq.wav"))
        // The mono mix stem stays the bare id — the ASR / playback-corrector contract.
        XCTAssertEqual(AudioWriter.url(id: "abc", stem: .mix).lastPathComponent, "abc.wav")
    }
}
