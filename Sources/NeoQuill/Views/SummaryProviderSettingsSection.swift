import SwiftUI

/// Provider-Konfiguration für die KI-Zusammenfassung. Jeder Provider zeigt nur
/// seine relevanten Felder; der API-Key wird scope-genau in der Keychain abgelegt.
/// Der "Verbindung testen"-Button geht über `AIProviderSettings.makeProvider` und
/// `SummaryProvider.probe`, kennt die einzelnen Anbieter also nicht.
struct SummaryProviderSettingsSection: View {
    @AppStorage(AppSettings.claudeAnalysisEnabled) private var summaryEnabled = true
    @AppStorage(AppSettings.aiSummaryProvider) private var providerRaw = AIProviderSettings.defaultProvider
    @AppStorage(AppSettings.aiSummaryBaseURL) private var openAIBaseURL = AIProviderSettings.defaultOpenAIBaseURL
    @AppStorage(AppSettings.aiSummaryModel) private var openAIModel = AIProviderSettings.defaultOpenAIModel
    @AppStorage(AppSettings.aiAnthropicBaseURL) private var anthropicBaseURL = AIProviderSettings.defaultAnthropicBaseURL
    @AppStorage(AppSettings.aiAnthropicModel) private var anthropicModel = AIProviderSettings.defaultAnthropicModel
    @AppStorage(AppSettings.aiOllamaBaseURL) private var ollamaBaseURL = AIProviderSettings.defaultOllamaBaseURL
    @AppStorage(AppSettings.aiOllamaModel) private var ollamaModel = AIProviderSettings.defaultOllamaModel

    @State private var apiKeyInput = ""
    @State private var hasStoredKey = false
    @State private var keyStatus: String?
    @State private var probeStatus: String?
    @State private var probing = false

    private var provider: AISummaryProvider {
        AISummaryProvider(rawValue: providerRaw) ?? .openAICompatible
    }

    private var keyScope: AIProviderKeyScope? {
        switch provider {
        case .openAICompatible: return .openAICompatible
        case .anthropicAPI: return .anthropic
        case .claudeCLI, .ollama: return nil
        }
    }

    var body: some View {
        Section("Zusammenfassung") {
            Toggle("KI-Zusammenfassung aktivieren", isOn: $summaryEnabled)
            Picker("Provider", selection: $providerRaw) {
                ForEach(AISummaryProvider.allCases) { provider in
                    Text(provider.displayName).tag(provider.rawValue)
                }
            }

            switch provider {
            case .claudeCLI:    claudeFields
            case .openAICompatible: openAIFields
            case .anthropicAPI: anthropicFields
            case .ollama:       ollamaFields
            }

            testConnectionRow
        }
        .onAppear(perform: refreshKeyState)
        .onChange(of: providerRaw) { _, _ in
            refreshKeyState()
            keyStatus = nil
            probeStatus = nil
            apiKeyInput = ""
        }
    }

    // MARK: - Provider-spezifische Felder

    private var claudeFields: some View {
        Group {
            LabeledContent("Account", value: summaryEnabled ? "lokaler Claude-Login" : "Aus")
            hint("Nutzt den lokal eingeloggten Claude-Account über die Claude CLI. Kein API-Key wird gespeichert.")
        }
    }

    private var openAIFields: some View {
        Group {
            TextField("Base URL", text: $openAIBaseURL)
            TextField("Modell", text: $openAIModel)
            apiKeyControls
            hint("OpenAI, OpenRouter, Groq, Together, lokale Server — alles, was chat/completions spricht. Secrets bleiben in der macOS Keychain.")
        }
    }

    private var anthropicFields: some View {
        Group {
            TextField("Base URL", text: $anthropicBaseURL)
            TextField("Modell", text: $anthropicModel)
            apiKeyControls
            hint("Anthropic API mit eigenem Key (api.anthropic.com). Modell z. B. claude-haiku-4-5. Secrets bleiben in der macOS Keychain.")
        }
    }

    private var ollamaFields: some View {
        Group {
            TextField("Base URL", text: $ollamaBaseURL)
            TextField("Modell", text: $ollamaModel)
            hint("Lokales Ollama über seinen OpenAI-kompatiblen Endpoint. Kein API-Key nötig. Modell z. B. llama3.1 — muss in Ollama installiert sein.")
        }
    }

    // MARK: - API-Key (scope-genau)

    private var apiKeyControls: some View {
        Group {
            LabeledContent("API-Key", value: hasStoredKey ? "In Keychain gespeichert" : "Fehlt")
            SecureField("Neuen API-Key eintragen", text: $apiKeyInput)
            HStack {
                Button("API-Key speichern") { saveKey() }
                    .disabled(apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Button("API-Key löschen") { clearKey() }
                    .disabled(!hasStoredKey)
            }
            if let keyStatus {
                Text(keyStatus).font(.callout).foregroundStyle(.secondary)
            }
        }
    }

    private var testConnectionRow: some View {
        Group {
            HStack {
                Button("Verbindung testen") { testConnection() }
                    .disabled(probing)
                if probing { ProgressView().controlSize(.small) }
            }
            if let probeStatus {
                Text(probeStatus)
                    .font(.callout)
                    .foregroundStyle(probeStatus.hasPrefix("✓") ? Neon.brandPrimary : Neon.statusError)
            }
        }
    }

    private func hint(_ text: String) -> some View {
        Text(text).font(.callout).foregroundStyle(.secondary)
    }

    // MARK: - Actions

    private func refreshKeyState() {
        guard let scope = keyScope else {
            hasStoredKey = false
            return
        }
        hasStoredKey = AIProviderSecretStore().apiKey(for: scope) != nil
    }

    private func saveKey() {
        guard let scope = keyScope else { return }
        do {
            try AIProviderSecretStore().setAPIKey(apiKeyInput, for: scope)
            apiKeyInput = ""
            keyStatus = "API-Key gespeichert."
            refreshKeyState()
        } catch {
            keyStatus = "API-Key konnte nicht gespeichert werden."
        }
    }

    private func clearKey() {
        guard let scope = keyScope else { return }
        AIProviderSecretStore().clearAPIKey(for: scope)
        apiKeyInput = ""
        keyStatus = "API-Key gelöscht."
        refreshKeyState()
    }

    private func testConnection() {
        probing = true
        probeStatus = "Teste Verbindung ..."
        Task {
            let result: ProviderProbeResult
            switch AIProviderSettings.makeProviderResult() {
            case .success(let provider):
                result = await provider.probe()
            case .failure(let configError):
                // Config-Fehler VOR dem Netz-Call konkret benennen (fehlender
                // Key, kaputte URL, leeres Modell) statt generisch zu raten.
                result = .failed(configError.userMessage)
            }
            await MainActor.run {
                switch result {
                case .ok(let detail):    probeStatus = "✓ \(detail)"
                case .failed(let reason): probeStatus = "✗ \(reason)"
                }
                probing = false
            }
        }
    }
}
