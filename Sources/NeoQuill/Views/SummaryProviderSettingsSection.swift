import SwiftUI

/// Provider-Konfiguration für die KI-Zusammenfassung. Jeder Provider zeigt nur
/// seine relevanten Felder; der API-Key wird scope-genau in der Keychain abgelegt.
/// Der "Verbindung testen"-Button geht über `AIProviderSettings.makeProvider` und
/// `SummaryProvider.probe`, kennt die einzelnen Anbieter also nicht.
struct SummaryProviderSettingsSection: View {
    @AppStorage(AppSettings.claudeAnalysisEnabled) private var summaryEnabled: Bool

    var body: some View {
        Section("Zusammenfassung") {
            Toggle("KI-Zusammenfassung aktivieren", isOn: $summaryEnabled)
            SummaryProviderConfigurationFields()
        }
    }
}

struct SummaryProviderConfigurationFields: View {
    var onVerificationChanged: ((Bool) -> Void)?

    @AppStorage(AppSettings.aiSummaryProvider) private var providerRaw: String
    @AppStorage(AppSettings.aiSummaryBaseURL) private var openAIBaseURL: String
    @AppStorage(AppSettings.aiSummaryModel) private var openAIModel: String
    @AppStorage(AppSettings.aiAnthropicBaseURL) private var anthropicBaseURL: String
    @AppStorage(AppSettings.aiAnthropicModel) private var anthropicModel: String
    @AppStorage(AppSettings.aiOllamaBaseURL) private var ollamaBaseURL: String
    @AppStorage(AppSettings.aiOllamaModel) private var ollamaModel: String

    @State private var apiKeyInput = ""
    @State private var hasStoredKey = false
    @State private var keyStatus: String?
    @State private var probeStatus: String?
    @State private var probing = false

    private var provider: AISummaryProvider {
        AISummaryProvider(rawValue: providerRaw) ?? .openAICompatible
    }

    /// Provider ↔ Keychain-Scope lebt am Enum (`AISummaryProvider.keyScope`) —
    /// die View trägt kein eigenes Mapping mehr.
    private var keyScope: AIProviderKeyScope? { provider.keyScope }

    var body: some View {
        Group {
            Picker("Provider", selection: $providerRaw) {
                ForEach(AISummaryProvider.allCases) { provider in
                    Text(provider.displayName).tag(provider.rawValue)
                }
            }

            switch provider {
            case .claudeCLI: claudeFields
            case .openAICompatible: openAIFields
            case .anthropicAPI: anthropicFields
            case .ollama: ollamaFields
            }

            testConnectionRow
        }
        .onAppear(perform: refreshKeyState)
        .onChange(of: providerRaw) { _, _ in resetProbeState(clearKeyInput: true) }
        .onChange(of: openAIBaseURL) { _, _ in resetProbeState() }
        .onChange(of: openAIModel) { _, _ in resetProbeState() }
        .onChange(of: anthropicBaseURL) { _, _ in resetProbeState() }
        .onChange(of: anthropicModel) { _, _ in resetProbeState() }
        .onChange(of: ollamaBaseURL) { _, _ in resetProbeState() }
        .onChange(of: ollamaModel) { _, _ in resetProbeState() }
    }

    // MARK: - Provider-spezifische Felder

    private var claudeFields: some View {
        Group {
            LabeledContent("Account", value: "Claude CLI OAuth")
            hint("Nutzt den lokal eingeloggten Claude-Account über die Claude CLI. Einmal `claude login` reicht; NeoQuill speichert keinen Claude-Key.")
        }
    }

    private var openAIFields: some View {
        Group {
            TextField("Base URL", text: $openAIBaseURL)
            TextField("Modell", text: $openAIModel)
            apiKeyControls
            hint("Codex/OpenAI, OpenRouter, Groq, Together oder lokale Server über chat/completions. API-Key einmal speichern; Secret bleibt in der macOS Keychain.")
        }
    }

    private var anthropicFields: some View {
        Group {
            TextField("Base URL", text: $anthropicBaseURL)
            TextField("Modell", text: $anthropicModel)
            apiKeyControls
            hint("Claude über Anthropic API mit eigenem Key (api.anthropic.com). Modell z. B. claude-haiku-4-5. Secret bleibt in der macOS Keychain.")
        }
    }

    private var ollamaFields: some View {
        Group {
            TextField("Base URL", text: $ollamaBaseURL)
            TextField("Modell", text: $ollamaModel)
            hint("Lokales Ollama über seinen OpenAI-kompatiblen Endpoint. Kein API-Key nötig. Modell z. B. llama3.1 — muss in Ollama installiert sein.")
        }
    }

    // MARK: - API-Key

    private var apiKeyControls: some View {
        Group {
            LabeledContent("API-Key", value: hasStoredKey ? "Im Schlüsselbund gespeichert" : "Noch nicht gespeichert")
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

    private func resetProbeState(clearKeyInput: Bool = false) {
        refreshKeyState()
        probeStatus = nil
        onVerificationChanged?(false)
        if clearKeyInput {
            keyStatus = nil
            apiKeyInput = ""
        }
    }

    private func saveKey() {
        guard let scope = keyScope else { return }
        do {
            try AIProviderSecretStore().setAPIKey(apiKeyInput, for: scope)
            apiKeyInput = ""
            keyStatus = "API-Key gespeichert."
            resetProbeState()
        } catch {
            keyStatus = error.localizedDescription
            onVerificationChanged?(false)
        }
    }

    private func clearKey() {
        guard let scope = keyScope else { return }
        AIProviderSecretStore().clearAPIKey(for: scope)
        apiKeyInput = ""
        keyStatus = "API-Key gelöscht."
        resetProbeState()
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
                result = .failed(configError.userMessage)
            }
            await MainActor.run {
                switch result {
                case .ok(let detail): probeStatus = "✓ \(detail)"
                case .failed(let reason): probeStatus = "✗ \(reason)"
                }
                onVerificationChanged?(result.isOK)
                probing = false
            }
        }
    }
}
