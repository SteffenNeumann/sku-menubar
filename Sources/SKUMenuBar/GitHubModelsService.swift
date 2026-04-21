import Foundation
import Security

/// GitHub Copilot API Integration.
/// Endpoint: https://api.githubcopilot.com/chat/completions
/// Token: VS Code Keychain "GitHub - https://api.github.com" → hat Copilot-Scopes
final class GitHubModelsService {

    private let endpoint = URL(string: "https://api.githubcopilot.com/chat/completions")!

    private static let modelMap: [String: String] = [
        "github/claude-sonnet-4-5":  "claude-sonnet-4.6",  // fallback: 4.5 nicht verfügbar
        "github/claude-opus-4-5":    "claude-opus-4.5",
        "github/claude-sonnet-4-6":  "claude-sonnet-4.6",
        "github/claude-opus-4-6":    "claude-opus-4.6",
        "github/claude-haiku-4-5":   "claude-haiku-4.5",
        "github/claude-3-7-sonnet":  "claude-sonnet-4.6",
        "github/claude-3-5-sonnet":  "claude-sonnet-4.6",
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

    /// Liest den VS Code GitHub Token aus dem macOS Keychain (hat Copilot-Scopes).
    private func ghAuthToken() -> String? {
        // 1. VS Code Keychain Token (hat Copilot-Berechtigung)
        if let token = keychainToken(service: "GitHub - https://api.github.com", account: nil),
           !token.isEmpty { return token }
        // 2. Fallback: gh CLI Token
        return ghCLIToken()
    }

    private func keychainToken(service: String, account: String?) -> String? {
        var query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnData as String:  true,
            kSecMatchLimit as String:  kSecMatchLimitOne
        ]
        if let acc = account { query[kSecAttrAccount as String] = acc }
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let token = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !token.isEmpty else { return nil }
        return token
    }

    private func ghCLIToken() -> String? {
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
        githubToken: String,
        imageAttachments: [GitHubImageAttachment] = [],
        mcpConfigs: [MCPServerConfig] = []
    ) -> AsyncThrowingStream<StreamEvent, Error> {
        return AsyncThrowingStream { continuation in
            Task.detached(priority: .userInitiated) {
                do {
                    let token = self.ghAuthToken() ?? githubToken
                    guard !token.isEmpty else { throw GitHubModelsError.noToken }

                    let apiModel = Self.copilotModelId(for: model)
                    let sessionId = UUID().uuidString

                    // MARK: MCP Setup — connect to active MCP servers and gather tool definitions
                    var mcpSessionByTool: [String: MCPClientSession] = [:]
                    var openAITools: [[String: Any]] = []
                    var allMCPSessions: [MCPClientSession] = []

                    for config in mcpConfigs {
                        let session = MCPClientSession(config: config)
                        do {
                            try await session.connect()
                            let tools = try await session.listTools()
                            for tool in tools {
                                if let name = tool["name"] as? String {
                                    mcpSessionByTool[name] = session
                                }
                            }
                            openAITools.append(contentsOf: MCPClientSession.toOpenAITools(tools))
                            allMCPSessions.append(session)
                        } catch {
                            // Continue without this server
                        }
                    }

                    // Build messages as [[String: Any]] to support both text and vision content
                    var conversationMessages: [[String: Any]] = []
                    if let sp = systemPrompt, !sp.isEmpty {
                        conversationMessages.append(["role": "system", "content": sp])
                    }
                    for h in history { conversationMessages.append(["role": h.role, "content": h.content]) }

                    // Build user content: text + optional base64 images
                    let userContent: Any
                    if imageAttachments.isEmpty {
                        userContent = message
                    } else {
                        var contentParts: [[String: Any]] = [
                            ["type": "text", "text": message]
                        ]
                        for img in imageAttachments {
                            contentParts.append([
                                "type": "image_url",
                                "image_url": ["url": "data:\(img.mimeType);base64,\(img.base64Data)"]
                            ])
                        }
                        userContent = contentParts
                    }
                    conversationMessages.append(["role": "user", "content": userContent])

                    continuation.yield(.systemInit(sessionId: sessionId))
                    var usageInputTokens: Int? = nil
                    var usageOutputTokens: Int? = nil
                    var totalAccumulated = ""

                    // MARK: Agentic loop — handles MCP tool calls transparently
                    // Max 10 iterations to prevent infinite loops
                    for _ in 0..<10 {
                    var bodyDict: [String: Any] = ["model": apiModel, "messages": conversationMessages, "stream": true]
                    if !openAITools.isEmpty { bodyDict["tools"] = openAITools }

                    let requestId = UUID().uuidString
                    var req = URLRequest(url: self.endpoint)
                    req.httpMethod = "POST"
                    req.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                    req.setValue("vscode-chat", forHTTPHeaderField: "Copilot-Integration-Id")
                    req.setValue(requestId, forHTTPHeaderField: "X-Request-Id")
                    req.httpBody = try JSONSerialization.data(withJSONObject: bodyDict)

                    let (stream, response) = try await URLSession.shared.bytes(for: req)
                    if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                        var errData = Data()
                        for try await byte in stream { errData.append(byte) }
                        let msg = String(data: errData, encoding: .utf8) ?? "HTTP \(http.statusCode)"
                        throw GitHubModelsError.httpError(http.statusCode, msg)
                    }

                    var accumulated = ""

                    // Accumulate streaming tool_calls (OpenAI delta format: partial arguments per chunk)
                    struct PendingTool { var id: String; var name: String; var args: String }
                    var pendingTools: [Int: PendingTool] = [:]
                    var toolsFlushed = false

                    for try await line in stream.lines {
                        guard line.hasPrefix("data: ") else { continue }
                        let rawData = String(line.dropFirst(6))
                        if rawData == "[DONE]" {
                            // Flush any remaining tool calls that never got a follow-up content chunk
                            if !toolsFlushed {
                                for key in pendingTools.keys.sorted() {
                                    guard let t = pendingTools[key] else { continue }
                                    continuation.yield(.toolUseEvent(
                                        id: t.id, name: t.name,
                                        input: Self.extractToolDisplay(from: t.args),
                                        model: "github/\(apiModel)", sessionId: sessionId
                                    ))
                                }
                            }
                            break
                        }
                        guard let jsonData = rawData.data(using: .utf8),
                              let obj = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
                              let choices = obj["choices"] as? [[String: Any]],
                              let delta = choices.first?["delta"] as? [String: Any]
                        else {
                            // Letzter Chunk kann usage ohne choices enthalten
                            if let jsonData = rawData.data(using: .utf8),
                               let obj = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
                               let usage = obj["usage"] as? [String: Any] {
                                usageInputTokens  = usage["prompt_tokens"]     as? Int
                                usageOutputTokens = usage["completion_tokens"] as? Int
                            }
                            continue
                        }

                        // Parse tool_call chunks (web search / function calling)
                        if let tcs = delta["tool_calls"] as? [[String: Any]] {
                            for tc in tcs {
                                let idx = tc["index"] as? Int ?? 0
                                if let id = tc["id"] as? String,
                                   let fn = tc["function"] as? [String: Any],
                                   let nm = fn["name"] as? String {
                                    pendingTools[idx] = PendingTool(id: id, name: nm, args: "")
                                }
                                if let fn = tc["function"] as? [String: Any],
                                   let argChunk = fn["arguments"] as? String, !argChunk.isEmpty {
                                    pendingTools[idx, default: PendingTool(id: UUID().uuidString, name: "search", args: "")].args += argChunk
                                }
                            }
                            continue
                        }

                        // Text content — flush pending tool calls first (once)
                        guard let text = delta["content"] as? String, !text.isEmpty else { continue }

                        if !pendingTools.isEmpty && !toolsFlushed {
                            for key in pendingTools.keys.sorted() {
                                guard let t = pendingTools[key] else { continue }
                                continuation.yield(.toolUseEvent(
                                    id: t.id, name: t.name,
                                    input: Self.extractToolDisplay(from: t.args),
                                    model: "github/\(apiModel)", sessionId: sessionId
                                ))
                            }
                            toolsFlushed = true
                        }

                        accumulated += text
                        // Wenn ein Tool-Call stattgefunden hat (toolsFlushed), Zwischentext nicht streamen —
                        // nur am Ende via resultSuccess sauber ausgeben (kein Research-Rauschen).
                        if !toolsFlushed {
                            continuation.yield(.textDelta(text, model: "github/\(apiModel)", sessionId: sessionId))
                        }
                    }

                    totalAccumulated += accumulated

                    // MARK: MCP Tool Execution — if the model requested tools AND we have MCP sessions
                    let hasMCPToolCalls = !pendingTools.isEmpty && !mcpSessionByTool.isEmpty
                    if hasMCPToolCalls {
                        // Yield tool-use events to UI
                        for key in pendingTools.keys.sorted() {
                            guard let t = pendingTools[key] else { continue }
                            if !toolsFlushed {
                                continuation.yield(.toolUseEvent(
                                    id: t.id, name: t.name,
                                    input: Self.extractToolDisplay(from: t.args),
                                    model: "github/\(apiModel)", sessionId: sessionId
                                ))
                            }
                        }

                        // Add assistant message with tool_calls to conversation
                        let toolCallsForMsg: [[String: Any]] = pendingTools.keys.sorted().compactMap { key in
                            guard let t = pendingTools[key] else { return nil }
                            return ["id": t.id, "type": "function",
                                    "function": ["name": t.name, "arguments": t.args] as [String: Any]]
                        }
                        var assistantMsg: [String: Any] = ["role": "assistant", "tool_calls": toolCallsForMsg]
                        if !accumulated.isEmpty { assistantMsg["content"] = accumulated }
                        conversationMessages.append(assistantMsg)

                        // Execute each tool via its MCP session and append results
                        for key in pendingTools.keys.sorted() {
                            guard let t = pendingTools[key] else { continue }
                            var toolResult: String
                            if let session = mcpSessionByTool[t.name] {
                                do {
                                    let rawArgs = t.args.data(using: .utf8) ?? Data()
                                    let args = (try? JSONSerialization.jsonObject(with: rawArgs) as? [String: Any]) ?? [:]
                                    toolResult = try await session.callTool(name: t.name, arguments: args)
                                } catch {
                                    toolResult = "Error calling tool '\(t.name)': \(error.localizedDescription)"
                                }
                            } else {
                                toolResult = "Tool '\(t.name)' is not available in the connected MCP servers."
                            }
                            conversationMessages.append([
                                "role": "tool",
                                "tool_call_id": t.id,
                                "content": toolResult
                            ])
                        }
                        // Continue agentic loop with updated conversation
                        continue
                    }

                    // No MCP tool calls (or no sessions) — done
                    break
                    } // end agentic loop

                    // Cleanup MCP sessions
                    for session in allMCPSessions { session.stop() }

                    continuation.yield(.resultSuccess(text: totalAccumulated, model: "github/\(apiModel)", sessionId: sessionId, inputTokens: usageInputTokens, outputTokens: usageOutputTokens))
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

/// A single image attachment for vision-capable GitHub Models calls.
struct GitHubImageAttachment {
    let mimeType: String        // "image/png", "image/jpeg", etc.
    let base64Data: String
}

extension GitHubModelsService {
    /// Extracts a human-readable display string from JSON tool-call arguments.
    fileprivate static func extractToolDisplay(from argsJson: String) -> String {
        guard !argsJson.isEmpty,
              let data = argsJson.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return String(argsJson.prefix(80)) }
        // Common search/query field names
        for key in ["query", "q", "input", "search", "prompt", "text"] {
            if let v = obj[key] as? String { return v }
        }
        return obj.values.compactMap { $0 as? String }.first ?? String(argsJson.prefix(80))
    }
}

extension StreamEvent {
    static func toolUseEvent(id: String, name: String, input: String, model: String, sessionId: String) -> StreamEvent {
        let toolInput = StreamToolInput(description: input)
        let block = StreamContent(type: "tool_use", id: id, name: name, toolInput: toolInput)
        let msg = StreamMessage(role: "assistant", content: [block], model: model, usage: nil)
        return StreamEvent(type: "assistant", subtype: nil, sessionId: sessionId,
                           message: msg, costUsd: nil, inputTokens: nil, outputTokens: nil,
                           isError: nil, result: nil, error: nil)
    }

    static func systemInit(sessionId: String) -> StreamEvent {
        StreamEvent(type: "system", subtype: "init", sessionId: sessionId,
                    message: nil, costUsd: nil, inputTokens: nil, outputTokens: nil,
                    isError: nil, result: nil, error: nil)
    }
    static func textDelta(_ text: String, model: String, sessionId: String) -> StreamEvent {
        let content = StreamContent(type: "text", text: text)
        let msg = StreamMessage(role: "assistant", content: [content], model: model, usage: nil)
        return StreamEvent(type: "assistant", subtype: nil, sessionId: sessionId,
                           message: msg, costUsd: nil, inputTokens: nil, outputTokens: nil,
                           isError: nil, result: nil, error: nil)
    }
    static func resultSuccess(text: String, model: String, sessionId: String, inputTokens: Int? = nil, outputTokens: Int? = nil) -> StreamEvent {
        StreamEvent(type: "result", subtype: "success", sessionId: sessionId,
                    message: nil, costUsd: 0, inputTokens: inputTokens, outputTokens: outputTokens,
                    isError: false, result: text, error: nil)
    }
}
