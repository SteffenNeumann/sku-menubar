import Foundation

/// GitHub Models API Integration.
/// Endpoint: https://models.inference.ai.azure.com/chat/completions
/// Token: gh auth token (direkt, kein Exchange nötig)
final class GitHubModelsService {

    private let endpoint = URL(string: "https://models.inference.ai.azure.com/chat/completions")!

    private static let modelMap: [String: String] = [
        "github/claude-sonnet-4-5":  "claude-sonnet-4.5",
        "github/claude-opus-4-5":    "claude-opus-4.5",
        "github/claude-sonnet-4-6":  "claude-sonnet-4.6",
        "github/claude-opus-4-6":    "claude-opus-4.6",
        "github/claude-haiku-4-5":   "claude-haiku-4.5",
        "github/claude-3-7-sonnet":  "claude-sonnet-4",
        "github/claude-3-5-sonnet":  "claude-sonnet-4.5",
        "github/gpt-4.1":            "gpt-4.1",
        "github/gpt-4o":             "gpt-4o",
        "github/gpt-4o-mini":        "gpt-4o-mini",
        "github/o3":                 "o3",
        "github/o4-mini":            "o4-mini",
    ]

    private static func copilotModelId(for model: String) -> String {
        if let mapped = modelMap[model] { return mapped }
        let stripped = model.hasPrefix("github/") ? String(model.dropFirst("github/".count)) : model
        return stripped
    }

    private func ghAuthToken() -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["gh", "auth", "token"]
        let home = NSHomeDirectory()
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = "\(home)/.local/bin:/usr/local/bin:/opt/homebrew/bin:" + (env["PATH"] ?? "/usr/bin:/bin")
        process.environment = env
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let token = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            return token?.isEmpty == false ? token : nil
        } catch { return nil }
    }

    func send(
        message: String,
        model: String,
        systemPrompt: String?,
        history: [GitHubMessage] = [],
        githubToken: String
    ) -> AsyncThrowingStream<StreamEvent, Error> {
        return AsyncThrowingStream { continuation in
            Task.detached(priority: .userInitiated) {
                do {
                    let token = self.ghAuthToken() ?? githubToken
                    guard !token.isEmpty else { throw GitHubModelsError.noToken }

                    let apiModel = Self.copilotModelId(for: model)
                    let sessionId = UUID().uuidString
                    let requestId = UUID().uuidString

                    var messages: [[String: String]] = []
                    if let sp = systemPrompt, !sp.isEmpty {
                        messages.append(["role": "system", "content": sp])
                    }
                    for h in history { messages.append(["role": h.role, "content": h.content]) }
                    messages.append(["role": "user", "content": message])

                    let body: [String: Any] = ["model": apiModel, "messages": messages, "stream": true]

                    var req = URLRequest(url: self.endpoint)
                    req.httpMethod = "POST"
                    req.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                    req.setValue(requestId, forHTTPHeaderField: "X-Request-Id")
                    req.httpBody = try JSONSerialization.data(withJSONObject: body)

                    let (stream, response) = try await URLSession.shared.bytes(for: req)
                    if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                        var errData = Data()
                        for try await byte in stream { errData.append(byte) }
                        let msg = String(data: errData, encoding: .utf8) ?? "HTTP \(http.statusCode)"
                        throw GitHubModelsError.httpError(http.statusCode, msg)
                    }

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
                              let text = delta["content"] as? String, !text.isEmpty
                        else { continue }
                        accumulated += text
                        continuation.yield(.textDelta(text, model: "github/\(apiModel)", sessionId: sessionId))
                    }

                    continuation.yield(.resultSuccess(text: accumulated, model: "github/\(apiModel)", sessionId: sessionId))
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
    case noToken
    var errorDescription: String? {
        switch self {
        case .httpError(let code, let msg): return "GitHub Models API Error \(code): \(msg)"
        case .noToken: return "Kein GitHub Token. Bitte `gh auth login` ausführen."
        }
    }
}

struct GitHubMessage {
    let role: String
    let content: String
}

extension StreamEvent {
    static func systemInit(sessionId: String) -> StreamEvent {
        StreamEvent(type: "system", subtype: "init", sessionId: sessionId,
                    message: nil, costUsd: nil, inputTokens: nil, outputTokens: nil,
                    isError: nil, result: nil, error: nil)
    }
    static func textDelta(_ text: String, model: String, sessionId: String) -> StreamEvent {
        let content = StreamContent(type: "text", text: text, thinking: nil, id: nil, name: nil)
        let msg = StreamMessage(role: "assistant", content: [content], model: model, usage: nil)
        return StreamEvent(type: "assistant", subtype: nil, sessionId: sessionId,
                           message: msg, costUsd: nil, inputTokens: nil, outputTokens: nil,
                           isError: nil, result: nil, error: nil)
    }
    static func resultSuccess(text: String, model: String, sessionId: String) -> StreamEvent {
        StreamEvent(type: "result", subtype: "success", sessionId: sessionId,
                    message: nil, costUsd: 0, inputTokens: nil, outputTokens: nil,
                    isError: false, result: text, error: nil)
    }
}
