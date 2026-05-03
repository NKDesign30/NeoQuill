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
    static let claudeAnalysisEnabled = "claude_analysis_enabled"
    static let captureSourceTeams  = "capture_source_teams"
    static let captureSourceZoom   = "capture_source_zoom"
    static let captureSourceMeet   = "capture_source_meet"
    static let captureSourceSystem = "capture_source_system"
    static let captureSourceLocal  = "capture_source_local"
    static let recordHotkey        = "record_hotkey"
    static let ownerOrganization   = "owner_organization"

    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            autoDetectMeetings: true,
            speakerDiarization: true,
            liveCaptionCapture: false,
            autoWatchDownloadsForTranscripts: false,
            ownerDisplayName: "",
            ownerRole: "Eigene Stimme",
            ownerOrganization: "",
            profileOnboarded: false,
            whisperModel: "openai_whisper-small",
            language: "de",
            sidebarDensity: "regular",
            detailLayout: "editorial",
            voiceIdEnrolled: false,
            calendarParticipantPool: true,
            claudeAnalysisEnabled: true,
            captureSourceTeams: true,
            captureSourceZoom: true,
            captureSourceMeet: true,
            captureSourceSystem: true,
            captureSourceLocal: true,
            recordHotkey: "⌥+R",
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
