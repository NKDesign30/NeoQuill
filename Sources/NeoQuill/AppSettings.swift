import Foundation

// UserDefaults-Keys, an einer Stelle. Bleibt klein — nur was UI direkt bindet.

enum AppSettings {
    static let whisperModel        = "whisper_model"
    static let micDeviceId         = "mic_device_id"
    static let autoDetectMeetings  = "auto_detect_meetings"
    static let speakerDiarization  = "speaker_diarization"
    static let liveCaptionCapture  = "live_caption_capture"
    static let autoWatchDownloadsForTranscripts = "auto_watch_downloads_for_transcripts"
    static let ownerDisplayName    = "owner_display_name"
    static let ownerRole           = "owner_role"
    static let profileOnboarded    = "profile_onboarded"
    static let language            = "language"
    static let sidebarDensity      = "sidebar_density"
    static let detailLayout        = "detail_layout"
    static let voiceIdEnrolled     = "voice_id_enrolled"
    static let calendarParticipantPool = "calendar_participant_pool"

    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            autoDetectMeetings: true,
            speakerDiarization: true,
            liveCaptionCapture: false,
            autoWatchDownloadsForTranscripts: false,
            ownerDisplayName: "",
            ownerRole: "Eigene Stimme",
            profileOnboarded: false,
            whisperModel: "openai_whisper-small",
            language: "de",
            sidebarDensity: "regular",
            detailLayout: "editorial",
            voiceIdEnrolled: false,
            calendarParticipantPool: true,
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
