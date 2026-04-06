import Foundation

/// Direkte GitHub Models API Integration (OpenAI-kompatibel).
/// Wird genutzt wenn selectedModel mit "github/" beginnt.
/// Endpoint: https://models.inference.ai.azure.com/chat/completions
final class GitHubModelsService {

    private let endpoint = URL(string: "https://models.inference.ai.azure.com/chat/completions")!

    /// Sendet eine Nachricht an die GitHub Models API und liefert einen AsyncThrowingStream
    /// mit StreamEvent-Objekten — kompatibel mit dem CLI-Stream in ChatView.
    func send(
        message: String,
        model: String,          // z.B. "github/claude-sonnet-4-5"
        systemPrompt: String?,
        history: [GitHubMessage] = [],
        githubToken: String
    ) -> AsyncThrowingStream<StreamEvent, Error> {

        let apiModel = model.hasPrefix("github/")
            ? String(model.dropFirst("github/".count))
            : model

        return AsyncThrowingStream { continuation in
            Task {
                do {
                    var messages: [[String: String]] = []
                    if let sp = systemPrompt, !sp.isEmpty {
                        messages.append(["role": "system", "content": sp])
                    }
                    for h in history {
                        messages.append(["role": h.role, "content": h.content])
                    }
                    messages.append(["role": "user", "content": message])

                    let body: [String: Any] = [
                        "model":    apiModel,
                        "messages": messages,
                        "stream":   true
                    ]

                    var req = URLRequest(url: endpoint)
                    req.httpMethod = "POST"
                    req.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    req.setValue("Bearer \(githubToken.trimmingCharacters(in: .whitespacesAndNewlines))",
                                 forHTTPHeaderField: "Authorization")
                    req.httpBody = try JSONSerialization.data(withJSONObject: body)

                    let (stream, response) = try await URLSession.shared.bytes(for: req)

                    if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                        var errData = Data()
                        for try await byte in stream { errData.append(byte) }
                        let msg = String(data: errData, encoding: .utf8) ?? "HTTP \(http.statusCode)"
                        throw GitHubModelsError.httpError(http.statusCode, msg)
                    }

                    // Synthetic session ID
                    let sessionId = UUID().uuidString
                    continuation.yield(.systemInit(sessionId: sessionId))

                    var accumulated = ""

                    for try await line in stream.lines {
                        guard line.hasPrefix("data: ") else { continue }
                        let data = String(line.dropFirst(6))
                        if data == "[DONE]" { break }

                        guard let jsonData = data.data(using: .utf8),
                              let obj = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
                              let choices = obj["choices"] as? [[String: Any]],
                              let delta = choices.first?["delta"] as? [String: Any],
                              let text = delta["content"] as? String
                        else { continue }

                        accumulated += text
                        continuation.yield(.textDelta(text, model: "github/\(apiModel)", sessionId: sessionId))
                    }

                    continuation.yield(.resultSuccess(
                        text: accumulated,
                        model: "github/\(apiModel)",
                        sessionId: sessionId
                    ))
                    continuation.finish()

                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
}

enum GitHubModelsError: LocalizedError {
    case httpError(Int, String)
    var errorDescription: String? {
        if case .httpError(let code, let msg) = self {
            return "GitHub Models API Error \(code): \(msg)"
        }
        return nil
    }
}

struct GitHubMessage {
    let role: String    // "user" | "assistant"
    let content: String
}

// MARK: - StreamEvent factory helpers (keeps ChatView untouched)

extension StreamEvent {
    static func systemInit(sessionId: String) -> StreamEvent {
        StreamEvent(
            type: "system",
            subtype: "init",
            sessionId: sessionId,
            message: nil,
            costUsd: nil, inputTokens: nil, outputTokens: nil,
            isError: nil, result: nil, error: nil
        )
    }

    static func textDelta(_ text: String, model: String, sessionId: String) -> StreamEvent {
        let content = StreamContent(type: "text", text: text, thinking: nil, id: nil, name: nil)
        let msg = StreamMessage(role: "assistant", content: [content], model: model, usage: nil)
        return StreamEvent(
            type: "assistant",
            subtype: nil,
            sessionId: sessionId,
            message: msg,
            costUsd: nil, inputTokens: nil, outputTokens: nil,
            isError: nil, result: nil, error: nil
        )
    }

    static func resultSuccess(text: String, model: String, sessionId: String) -> StreamEvent {
        StreamEvent(
            type: "result",
            subtype: "success",
            sessionId: sessionId,
            message: nil,
            costUsd: 0,
            inputTokens: nil,
            outputTokens: nil,
            isError: false,
            result: text,
            error: nil
        )
    }
}
