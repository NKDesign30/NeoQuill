import Foundation

// UserDefaults-Keys, an einer Stelle. Bleibt klein — nur was UI direkt bindet.

enum AppSettings {
    static let whisperModel        = "whisper_model"
    static let micDeviceId         = "mic_device_id"
    static let autoDetectMeetings  = "auto_detect_meetings"
    static let speakerDiarization  = "speaker_diarization"
    static let language            = "language"
    static let sidebarDensity      = "sidebar_density"
    static let detailLayout        = "detail_layout"

    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            autoDetectMeetings: true,
            speakerDiarization: true,
            whisperModel: "openai_whisper-small",
            language: "de",
            sidebarDensity: "regular",
            detailLayout: "editorial",
        ])
    }
}

extension UserDefaults {
    func stringOr(_ key: String, default: String) -> String {
        string(forKey: key) ?? `default`
    }

    func boolOr(_ key: String, default: Bool) -> Bool {
        object(forKey: key) == nil ? `default` : bool(forKey: key)
    }
}
