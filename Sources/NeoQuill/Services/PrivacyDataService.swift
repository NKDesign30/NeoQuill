import AppKit
import Foundation

struct PrivacyDeleteResult: Equatable {
    let audioFilesDeleted: Int
}

enum PrivacyDataService {
    static func openLocalDataFolder() {
        NSWorkspace.shared.open(MeetingStore.applicationSupportDirectory())
    }

    @discardableResult
    static func deleteAudioFiles(directory: URL = AudioWriter.recordingsDirectory()) throws -> Int {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: directory.path) else { return 0 }
        let files = try fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension.lowercased() == "wav" }
        for file in files {
            try fileManager.removeItem(at: file)
        }
        return files.count
    }

    @discardableResult
    static func deleteAudioFiles(for meetingId: String, directory: URL = AudioWriter.recordingsDirectory()) throws -> Int {
        let fileManager = FileManager.default
        let urls = [
            directory.appendingPathComponent("\(meetingId).wav"),
            directory.appendingPathComponent("\(meetingId).mic.wav"),
            directory.appendingPathComponent("\(meetingId).system.wav"),
        ]
        var deleted = 0
        for url in urls where fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
            deleted += 1
        }
        return deleted
    }

    @discardableResult
    static func deleteAllLocalMeetingData(store: MeetingStore) throws -> PrivacyDeleteResult {
        store.deleteAllMeetings()
        let deletedAudio = try deleteAudioFiles()
        return PrivacyDeleteResult(audioFilesDeleted: deletedAudio)
    }
}
