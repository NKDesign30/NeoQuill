import Foundation

/// OpenAI-kompatibles Backend: OpenAI selbst, OpenRouter, Groq, Together,
/// lokale Server und alles andere, das `chat/completions` spricht. Ollama
/// nutzt denselben Transport über seinen OpenAI-kompatiblen Endpoint.
struct OpenAICompatibleSummaryProvider: SummaryProvider {
    let config: OpenAICompatibleSummaryConfig

    func summarize(transcript: String, locale: String) async -> MeetingSummaryAI? {
        let prompt = MeetingSummaryPrompt.build(transcript: transcript, locale: locale)
        var request = URLRequest(url: config.chatCompletionsURL, timeoutInterval: 60)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")

        let body = OpenAIChatCompletionRequest(
            model: config.model,
            messages: [
                OpenAIChatMessage(role: "user", content: prompt),
            ],
            temperature: 0.2,
            responseFormat: OpenAIResponseFormat(type: "json_object")
        )

        do {
            request.httpBody = try JSONEncoder().encode(body)
            let (data, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse,
               !(200..<300).contains(http.statusCode) {
                NSLog("[OpenAICompatible] request failed with status \(http.statusCode)")
                return nil
            }
            let decoded = try JSONDecoder().decode(OpenAIChatCompletionResponse.self, from: data)
            guard let content = decoded.choices.first?.message.content else { return nil }
            return MeetingSummaryPrompt.parseSummary(content)
        } catch {
            NSLog("[OpenAICompatible] request failed: \(error)")
            return nil
        }
    }

    func probe() async -> ProviderProbeResult {
        var request = URLRequest(url: config.chatCompletionsURL, timeoutInterval: 15)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")

        let body = OpenAIChatCompletionRequest(
            model: config.model,
            messages: [OpenAIChatMessage(role: "user", content: "Antworte nur mit OK.")],
            temperature: 0,
            responseFormat: nil
        )

        do {
            request.httpBody = try JSONEncoder().encode(body)
            let (data, response) = try await URLSession.shared.data(for: request)
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

private struct OpenAIChatCompletionRequest: Encodable {
    let model: String
    let messages: [OpenAIChatMessage]
    let temperature: Double
    let responseFormat: OpenAIResponseFormat?

    enum CodingKeys: String, CodingKey {
        case model
        case messages
        case temperature
        case responseFormat = "response_format"
    }
}

private struct OpenAIChatMessage: Encodable {
    let role: String
    let content: String
}

private struct OpenAIResponseFormat: Encodable {
    let type: String
}

private struct OpenAIChatCompletionResponse: Decodable {
    let choices: [OpenAIChoice]
}

private struct OpenAIChoice: Decodable {
    let message: OpenAIMessage
}

private struct OpenAIMessage: Decodable {
    let content: String?
}
