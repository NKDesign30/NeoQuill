import Foundation

/// Anthropic-Messages-Backend mit eigenem API-Key. Spricht `/v1/messages` mit
/// `x-api-key` und `anthropic-version` — ein anderes Protokoll als OpenAI, daher
/// ein eigener Provider. Die Antwort kommt als Content-Blöcke; wir nehmen den
/// ersten Text-Block und geben ihn an den gemeinsamen Summary-Parser.
struct AnthropicSummaryProvider: SummaryProvider {
    let config: AnthropicSummaryConfig
    /// Injizierbar (Pattern wie `NeonInboxClient`) — Tests fahren `summarize`
    /// und `probe` über eine URLProtocol-gemockte Session statt live.
    let session: URLSession

    init(config: AnthropicSummaryConfig, session: URLSession = .shared) {
        self.config = config
        self.session = session
    }

    func summarize(transcript: String, locale: String) async -> MeetingSummaryAI? {
        let prompt = MeetingSummaryPrompt.build(transcript: transcript, locale: locale)
        var request = URLRequest(url: config.messagesURL, timeoutInterval: 60)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(config.apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

        let body = AnthropicMessagesRequest(
            model: config.model,
            maxTokens: 4096,
            messages: [AnthropicMessage(role: "user", content: prompt)]
        )

        do {
            request.httpBody = try JSONEncoder().encode(body)
            let (data, response) = try await session.data(for: request)
            if let http = response as? HTTPURLResponse,
               !(200..<300).contains(http.statusCode) {
                NSLog("[Anthropic] request failed with status \(http.statusCode)")
                return nil
            }
            let decoded = try JSONDecoder().decode(AnthropicMessagesResponse.self, from: data)
            guard let text = decoded.content.first(where: { $0.type == "text" })?.text else { return nil }
            return MeetingSummaryPrompt.parseSummary(text)
        } catch {
            NSLog("[Anthropic] request failed: \(error)")
            return nil
        }
    }

    func probe() async -> ProviderProbeResult {
        var request = URLRequest(url: config.messagesURL, timeoutInterval: 15)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(config.apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

        let body = AnthropicMessagesRequest(
            model: config.model,
            maxTokens: 16,
            messages: [AnthropicMessage(role: "user", content: "Antworte nur mit OK.")]
        )

        do {
            request.httpBody = try JSONEncoder().encode(body)
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                return .failed("Keine HTTP-Antwort vom Endpoint.")
            }
            guard (200..<300).contains(http.statusCode) else {
                let snippet = String(data: data, encoding: .utf8)?.prefix(160) ?? ""
                return .failed("HTTP \(http.statusCode): \(snippet)")
            }
            return .ok("Verbindung steht (Modell \(config.model)).")
        } catch {
            return .failed(error.localizedDescription)
        }
    }
}

private struct AnthropicMessagesRequest: Encodable {
    let model: String
    let maxTokens: Int
    let messages: [AnthropicMessage]

    enum CodingKeys: String, CodingKey {
        case model
        case messages
        case maxTokens = "max_tokens"
    }
}

private struct AnthropicMessage: Encodable {
    let role: String
    let content: String
}

private struct AnthropicMessagesResponse: Decodable {
    let content: [AnthropicContentBlock]
}

private struct AnthropicContentBlock: Decodable {
    let type: String
    let text: String?
}
