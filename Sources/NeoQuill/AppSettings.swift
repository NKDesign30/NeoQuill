import Foundation
import SwiftUI

/// Eine Einstellung: Key + Typ + Default an EINEM Ort.
///
/// Vorher deklarierten `registerDefaults`, die `@AppStorage`-Initialwerte und
/// die Inline-Defaults der Read-Helper denselben Wert an bis zu vier Stellen —
/// mit realen Widersprüchen (`speakerDiarization`: registriert `true`, an vier
/// Call-Sites mit Default `false` gelesen; `autoDetectMeetings` und
/// `liveCaptionCapture` je nach Datei unterschiedlich). Solange
/// `registerDefaults()` zuerst lief, gewann still der registrierte Wert — vor
/// der Registrierung und in Tests gewann der Inline-Default. Jetzt besitzt die
/// Definition den Default, alle Zugriffswege leiten daraus ab.
struct AppSetting<Value> {
    let key: String
    let defaultValue: Value
}

enum AppSettings {
    static let whisperModel        = AppSetting(key: "whisper_model", defaultValue: "openai_whisper-small")
    static let micDeviceId         = AppSetting(key: "mic_device_id", defaultValue: "")
    static let autoDetectMeetings  = AppSetting(key: "auto_detect_meetings", defaultValue: true)
    static let speakerDiarization  = AppSetting(key: "speaker_diarization", defaultValue: true)
    static let liveCaptionCapture  = AppSetting(key: "live_caption_capture", defaultValue: false)
    static let autoWatchDownloadsForTranscripts = AppSetting(key: "auto_watch_downloads_for_transcripts", defaultValue: false)
    static let ownerDisplayName    = AppSetting(key: "owner_display_name", defaultValue: "")
    static let ownerRole           = AppSetting(key: "owner_role", defaultValue: "Eigene Stimme")
    static let profileOnboarded    = AppSetting(key: "profile_onboarded", defaultValue: false)
    static let language            = AppSetting(key: "language", defaultValue: "auto")          // Transkript-/Summary-Sprache
    static let appLanguage         = AppSetting(key: "app_language", defaultValue: "system")    // UI-Sprache (system | de | en)
    static let sidebarDensity      = AppSetting(key: "sidebar_density", defaultValue: "regular")
    static let detailLayout        = AppSetting(key: "detail_layout", defaultValue: "editorial")
    static let voiceIdEnrolled     = AppSetting(key: "voice_id_enrolled", defaultValue: false)
    static let calendarParticipantPool = AppSetting(key: "calendar_participant_pool", defaultValue: true)
    static let claudeAnalysisEnabled = AppSetting(key: "claude_analysis_enabled", defaultValue: true)
    static let localOnlyMode = AppSetting(key: "local_only_mode", defaultValue: false)
    static let deleteAudioAfterTranscription = AppSetting(key: "delete_audio_after_transcription", defaultValue: false)
    static let aiSummaryProvider = AppSetting(key: "ai_summary_provider", defaultValue: AIProviderSettings.defaultProvider)
    static let aiSummaryBaseURL = AppSetting(key: "ai_summary_base_url", defaultValue: AIProviderSettings.defaultOpenAIBaseURL)
    static let aiSummaryModel = AppSetting(key: "ai_summary_model", defaultValue: AIProviderSettings.defaultOpenAIModel)
    static let aiAnthropicBaseURL = AppSetting(key: "ai_anthropic_base_url", defaultValue: AIProviderSettings.defaultAnthropicBaseURL)
    static let aiAnthropicModel = AppSetting(key: "ai_anthropic_model", defaultValue: AIProviderSettings.defaultAnthropicModel)
    static let aiOllamaBaseURL = AppSetting(key: "ai_ollama_base_url", defaultValue: AIProviderSettings.defaultOllamaBaseURL)
    static let aiOllamaModel = AppSetting(key: "ai_ollama_model", defaultValue: AIProviderSettings.defaultOllamaModel)
    static let actionDefaultRecipient = AppSetting(key: "action_default_recipient", defaultValue: "")
    static let actionJiraBaseURL = AppSetting(key: "action_jira_base_url", defaultValue: "")
    static let actionWebhookURL = AppSetting(key: "action_webhook_url", defaultValue: "")
    static let actionNeoSkillBridgeEnabled = AppSetting(key: "action_neo_skill_bridge_enabled", defaultValue: false)
    static let actionInboxEndpoint = AppSetting(key: NeonInboxClient.endpointDefaultsKey, defaultValue: "")
    static let actionJiraMCPEnabled = AppSetting(key: "action_jira_mcp_enabled", defaultValue: false)
    static let actionJiraMCPPackage = AppSetting(key: "action_jira_mcp_package", defaultValue: "")
    static let actionJiraMCPCommand = AppSetting(key: "action_jira_mcp_command", defaultValue: NeonJiraMCPInstaller.defaultCommand)
    static let cloudTeamsClientId = AppSetting(key: "cloud_teams_client_id", defaultValue: "")
    static let cloudTeamsScopes = AppSetting(key: "cloud_teams_scopes", defaultValue: "")
    static let cloudMeetClientId = AppSetting(key: "cloud_meet_client_id", defaultValue: "")
    static let cloudMeetScopes = AppSetting(key: "cloud_meet_scopes", defaultValue: "")
    static let cloudZoomClientId = AppSetting(key: "cloud_zoom_client_id", defaultValue: "")
    static let cloudZoomScopes = AppSetting(key: "cloud_zoom_scopes", defaultValue: "")
    static let captureSourceTeams  = AppSetting(key: "capture_source_teams", defaultValue: true)
    static let captureSourceZoom   = AppSetting(key: "capture_source_zoom", defaultValue: true)
    static let captureSourceMeet   = AppSetting(key: "capture_source_meet", defaultValue: true)
    static let captureSourceSystem = AppSetting(key: "capture_source_system", defaultValue: true)
    static let captureSourceLocal  = AppSetting(key: "capture_source_local", defaultValue: true)
    static let recordHotkey        = AppSetting(key: "record_hotkey", defaultValue: "⌥+R")

    static func registerDefaults() {
        UserDefaults.standard.register(defaults: registrationDefaults)
    }

    /// Aus den Definitionen abgeleitet — es gibt keine zweite Liste von
    /// Default-Werten mehr. Ein hier vergessenes Setting wäre harmlos:
    /// `value(for:)` und die `@AppStorage`-Inits fallen ohnehin auf
    /// `defaultValue` zurück.
    static var registrationDefaults: [String: Any] {
        var defaults: [String: Any] = [:]
        func add<V>(_ setting: AppSetting<V>) { defaults[setting.key] = setting.defaultValue }
        add(whisperModel); add(micDeviceId); add(autoDetectMeetings); add(speakerDiarization)
        add(liveCaptionCapture); add(autoWatchDownloadsForTranscripts); add(ownerDisplayName)
        add(ownerRole); add(profileOnboarded); add(language); add(appLanguage)
        add(sidebarDensity); add(detailLayout); add(voiceIdEnrolled); add(calendarParticipantPool)
        add(claudeAnalysisEnabled); add(localOnlyMode); add(deleteAudioAfterTranscription)
        add(aiSummaryProvider); add(aiSummaryBaseURL); add(aiSummaryModel)
        add(aiAnthropicBaseURL); add(aiAnthropicModel); add(aiOllamaBaseURL); add(aiOllamaModel)
        add(actionDefaultRecipient); add(actionJiraBaseURL); add(actionWebhookURL)
        add(actionNeoSkillBridgeEnabled); add(actionInboxEndpoint); add(actionJiraMCPEnabled)
        add(actionJiraMCPPackage); add(actionJiraMCPCommand)
        add(cloudTeamsClientId); add(cloudTeamsScopes); add(cloudMeetClientId)
        add(cloudMeetScopes); add(cloudZoomClientId); add(cloudZoomScopes)
        add(captureSourceTeams); add(captureSourceZoom); add(captureSourceMeet)
        add(captureSourceSystem); add(captureSourceLocal); add(recordHotkey)
        return defaults
    }
}

extension UserDefaults {
    /// Effektiver Wert einer Einstellung: gesetzter Wert, sonst der Default aus
    /// der Definition — unabhängig davon, ob `registerDefaults()` schon lief.
    func value(for setting: AppSetting<Bool>) -> Bool {
        object(forKey: setting.key) == nil ? setting.defaultValue : bool(forKey: setting.key)
    }

    func value(for setting: AppSetting<String>) -> String {
        string(forKey: setting.key) ?? setting.defaultValue
    }

    func set(_ value: Bool, for setting: AppSetting<Bool>) {
        set(value, forKey: setting.key)
    }

    func set(_ value: String, for setting: AppSetting<String>) {
        set(value, forKey: setting.key)
    }
}

extension AppStorage {
    /// Bindet eine View an eine `AppSetting`-Definition — Key und Default
    /// kommen aus derselben Quelle wie Service-Reads und `registerDefaults()`.
    init(_ setting: AppSetting<Value>, store: UserDefaults? = nil) where Value == Bool {
        self.init(wrappedValue: setting.defaultValue, setting.key, store: store)
    }

    init(_ setting: AppSetting<Value>, store: UserDefaults? = nil) where Value == String {
        self.init(wrappedValue: setting.defaultValue, setting.key, store: store)
    }
}
