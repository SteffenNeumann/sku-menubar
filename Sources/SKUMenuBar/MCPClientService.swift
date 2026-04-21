import Foundation

// MARK: - MCP Client Session
// Lightweight MCP (Model Context Protocol) JSON-RPC client.
// Supports stdio and HTTP(S) transports.
// Calls are strictly sequential — no concurrent RPC supported by design.

final class MCPClientSession: @unchecked Sendable {

    let config: MCPServerConfig

    private var process: Process?
    private var stdinHandle: FileHandle?
    private var stdoutHandle: FileHandle?
    private var nextId = 1
    private let lock = NSLock()
    private var readBuffer = ""
    // id → (result, errorMessage)
    private var pendingResponses: [Int: (result: [String: Any]?, error: String?)] = [:]
    private let responseSemaphore = DispatchSemaphore(value: 0)
    private var connected = false

    init(config: MCPServerConfig) {
        self.config = config
    }

    // MARK: - Connect

    func connect() async throws {
        guard !connected else { return }
        if config.transport == "stdio" {
            try await connectStdio()
        }
        // HTTP transport: no persistent connection; initialize is done per call
        connected = true
    }

    private func connectStdio() async throws {
        let proc = Process()
        var env = ProcessInfo.processInfo.environment
        let home = NSHomeDirectory()
        env["PATH"] = "\(home)/.local/bin:/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin:" + (env["PATH"] ?? "")
        for kv in config.envVars {
            let parts = kv.split(separator: "=", maxSplits: 1)
            if parts.count == 2 { env[String(parts[0])] = String(parts[1]) }
        }

        proc.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        proc.arguments = [config.commandOrUrl] + config.args
        proc.environment = env

        let inPipe  = Pipe()
        let outPipe = Pipe()
        proc.standardInput  = inPipe
        proc.standardOutput = outPipe
        proc.standardError  = Pipe()

        try proc.run()

        self.process      = proc
        self.stdinHandle  = inPipe.fileHandleForWriting
        self.stdoutHandle = outPipe.fileHandleForReading

        // Set up async reader using readabilityHandler
        outPipe.fileHandleForReading.readabilityHandler = { [weak self] fh in
            guard let self else { return }
            let data = fh.availableData
            guard !data.isEmpty, let str = String(data: data, encoding: .utf8) else { return }
            self.processIncoming(str)
        }

        // MCP initialize handshake
        _ = try await sendRPC(method: "initialize", params: [
            "protocolVersion": "2024-11-05",
            "capabilities": ["tools": [:] as [String: Any]],
            "clientInfo": ["name": "myClaude", "version": "1.0"]
        ])

        // Initialized notification (fire-and-forget, no response expected)
        sendNotification("notifications/initialized")
    }

    // MARK: - Incoming data processing

    private func processIncoming(_ str: String) {
        lock.lock()
        readBuffer += str
        var completedLines: [String] = []
        while let nl = readBuffer.range(of: "\n") {
            let line = String(readBuffer[..<nl.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            readBuffer.removeSubrange(..<nl.upperBound)
            if !line.isEmpty { completedLines.append(line) }
        }
        lock.unlock()

        for line in completedLines {
            guard let data = line.data(using: .utf8),
                  let obj  = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let id   = obj["id"] as? Int else { continue }

            let result   = obj["result"] as? [String: Any]
            let errorMsg = (obj["error"] as? [String: Any])?["message"] as? String

            lock.lock()
            pendingResponses[id] = (result: result, error: errorMsg)
            lock.unlock()
            responseSemaphore.signal()
        }
    }

    // MARK: - JSON-RPC send

    private func sendNotification(_ method: String, params: [String: Any]? = nil) {
        var msg: [String: Any] = ["jsonrpc": "2.0", "method": method]
        if let p = params { msg["params"] = p }
        guard let data = try? JSONSerialization.data(withJSONObject: msg) else { return }
        var line = data; line.append(0x0a)
        stdinHandle?.write(line)
    }

    private func sendRPC(method: String, params: [String: Any]? = nil) async throws -> [String: Any] {
        // HTTP/SSE: stateless POST per call
        let isHTTP = config.transport == "http" || config.transport == "sse"
            || (config.transport == "unknown" && config.commandOrUrl.hasPrefix("http"))
        if isHTTP {
            return try await sendHTTPRPC(method: method, params: params)
        }

        lock.lock()
        let id = nextId; nextId += 1
        lock.unlock()

        var msg: [String: Any] = ["jsonrpc": "2.0", "id": id, "method": method]
        if let p = params { msg["params"] = p }
        guard let data = try? JSONSerialization.data(withJSONObject: msg) else {
            throw MCPClientError.encodingError
        }
        var lineData = data; lineData.append(0x0a)
        stdinHandle?.write(lineData)

        // Wait for matching response in a background thread (blocks)
        return try await Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { throw MCPClientError.disconnected }
            return try self.waitForResponse(id: id, timeout: 30)
        }.value
    }

    /// Blocks until the response for `id` arrives or times out.
    private func waitForResponse(id: Int, timeout: TimeInterval) throws -> [String: Any] {
        let deadline = DispatchTime.now() + timeout
        while true {
            switch responseSemaphore.wait(timeout: deadline) {
            case .timedOut:
                throw MCPClientError.timeout
            case .success:
                lock.lock()
                let response = pendingResponses.removeValue(forKey: id)
                lock.unlock()

                if let response {
                    if let err = response.error { throw MCPClientError.serverError(err) }
                    return response.result ?? [:]
                }
                // Signal was for a different ID — put it back and retry briefly
                responseSemaphore.signal()
                Thread.sleep(forTimeInterval: 0.001)
            }
        }
    }

    private func sendHTTPRPC(method: String, params: [String: Any]?) async throws -> [String: Any] {
        guard let url = URL(string: config.commandOrUrl) else { throw MCPClientError.invalidURL }

        lock.lock()
        let id = nextId; nextId += 1
        lock.unlock()

        var body: [String: Any] = ["jsonrpc": "2.0", "id": id, "method": method]
        if let p = params { body["params"] = p }

        var req = URLRequest(url: url, timeoutInterval: 30)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        for h in config.headers {
            let parts = h.split(separator: ":", maxSplits: 1)
            if parts.count == 2 {
                req.setValue(
                    String(parts[1]).trimmingCharacters(in: .whitespaces),
                    forHTTPHeaderField: String(parts[0]).trimmingCharacters(in: .whitespaces)
                )
            }
        }
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, _) = try await URLSession.shared.data(for: req)
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw MCPClientError.invalidResponse
        }
        if let err = obj["error"] as? [String: Any], let msg = err["message"] as? String {
            throw MCPClientError.serverError(msg)
        }
        return (obj["result"] as? [String: Any]) ?? [:]
    }

    // MARK: - Public MCP API

    /// Connects (if needed) and returns available tools.
    func listTools() async throws -> [[String: Any]] {
        if !connected { try await connect() }
        let result = try await sendRPC(method: "tools/list")
        return (result["tools"] as? [[String: Any]]) ?? []
    }

    /// Calls a tool and returns the text output.
    func callTool(name: String, arguments: [String: Any]) async throws -> String {
        let result = try await sendRPC(
            method: "tools/call",
            params: ["name": name, "arguments": arguments]
        )
        if let content = result["content"] as? [[String: Any]] {
            let texts = content.compactMap { block -> String? in
                guard block["type"] as? String == "text" else { return nil }
                return block["text"] as? String
            }
            if !texts.isEmpty { return texts.joined(separator: "\n") }
        }
        if let data = try? JSONSerialization.data(withJSONObject: result),
           let str  = String(data: data, encoding: .utf8) { return str }
        return ""
    }

    // MARK: - Cleanup

    func stop() {
        stdoutHandle?.readabilityHandler = nil
        stdinHandle?.closeFile()
        process?.terminate()
        process   = nil
        connected = false
        lock.lock()
        pendingResponses.removeAll()
        lock.unlock()
    }

    deinit { stop() }
}

// MARK: - Tool format conversion

extension MCPClientSession {
    /// Converts MCP tool definitions to OpenAI-compatible `tools` array format.
    static func toOpenAITools(_ mcpTools: [[String: Any]]) -> [[String: Any]] {
        mcpTools.compactMap { tool -> [String: Any]? in
            guard let name = tool["name"] as? String else { return nil }
            let description  = tool["description"] as? String ?? ""
            let inputSchema  = tool["inputSchema"]  as? [String: Any]
                            ?? ["type": "object", "properties": [:] as [String: Any]]
            return [
                "type": "function",
                "function": [
                    "name":        name,
                    "description": description,
                    "parameters":  inputSchema
                ] as [String: Any]
            ]
        }
    }
}

// MARK: - Errors

enum MCPClientError: LocalizedError {
    case serverError(String)
    case encodingError
    case invalidURL
    case invalidResponse
    case disconnected
    case timeout

    var errorDescription: String? {
        switch self {
        case .serverError(let m): return "MCP server error: \(m)"
        case .encodingError:      return "MCP encoding error"
        case .invalidURL:         return "MCP invalid URL"
        case .invalidResponse:    return "MCP invalid response"
        case .disconnected:       return "MCP disconnected"
        case .timeout:            return "MCP request timed out"
        }
    }
}
