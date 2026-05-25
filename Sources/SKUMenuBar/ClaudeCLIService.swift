import Foundation
import SwiftUI

@MainActor
final class ClaudeCLIService: ObservableObject {

    // MARK: - Computed path

    var claudePath: String {
        let home = NSHomeDirectory()
        return "\(home)/.local/bin/claude"
    }

    // MARK: - Send message (streaming)

    func send(
        message: String,
        sessionId: String? = nil,
        agentName: String? = nil,
        systemPrompt: String? = nil,
        model: String? = nil,
        fallbackModel: String? = nil,
        workingDirectory: String? = nil,
        addDirs: [String] = [],
        skipPermissions: Bool = false,
        maxTurns: Int? = nil,
        mcpConfigJSON: String? = nil,   // wenn gesetzt: --mcp-config <json>
        mcpStrictMode: Bool = true,     // wenn true zusätzlich --strict-mcp-config (disabled für OAuth-MCPs)
        imagePaths: [String] = []       // optional image files to attach (for persona reviews)
    ) -> AsyncThrowingStream<StreamEvent, Error> {
        let path = claudePath
        return AsyncThrowingStream { continuation in
            Task.detached(priority: .userInitiated) {
                var args: [String] = ["--print", "--output-format", "stream-json", "--verbose"]
                if skipPermissions {
                    args.append("--dangerously-skip-permissions")
                }
                if let mcpJson = mcpConfigJSON, !mcpJson.isEmpty {
                    if mcpStrictMode { args.append("--strict-mcp-config") }
                    args += ["--mcp-config", mcpJson]
                }

                if let sid = sessionId, !sid.isEmpty {
                    // --resume <sessionId> resumes a specific session by ID (each tab keeps
                    // its own currentSessionId → tabs are fully independent)
                    args += ["--resume", sid]
                }
                if let sp = systemPrompt, !sp.isEmpty {
                    args += ["--system-prompt", sp]
                }
                if let m = model, !m.isEmpty {
                    args += ["--model", m]
                }
                if let fb = fallbackModel, !fb.isEmpty {
                    args += ["--fallback-model", fb]
                }
                if let mt = maxTurns, mt > 0 {
                    args += ["--max-turns", "\(mt)"]
                }
                for dir in addDirs where !dir.isEmpty {
                    args += ["--add-dir", dir]
                }
                // When images are present, switch to stream-json input so we can
                // send image content blocks as base64 (--image flag does not exist).
                if !imagePaths.isEmpty {
                    args += ["--input-format", "stream-json"]
                }
                guard !message.isEmpty else {
                    continuation.finish(throwing: NSError(domain: "ClaudeCLI", code: -1,
                        userInfo: [NSLocalizedDescriptionKey: "Kein Prompt eingegeben."]))
                    return
                }
                // Always pipe the message via stdin — positional args break when --add-dir
                // or --continue is present in newer Claude CLI versions.

                let process = Process()
                let home = NSHomeDirectory()
                process.executableURL = URL(fileURLWithPath: path)
                process.arguments = args

                // Set working directory if specified
                if let cwd = workingDirectory, !cwd.isEmpty {
                    process.currentDirectoryURL = URL(fileURLWithPath: cwd)
                }

                // Augment PATH so claude can find node/npm/etc
                var env = ProcessInfo.processInfo.environment
                let extraPaths = "\(home)/.local/bin:/usr/local/bin:/opt/homebrew/bin:/opt/homebrew/sbin"
                env["PATH"] = extraPaths + ":" + (env["PATH"] ?? "/usr/bin:/bin")
                env["HOME"] = home
                // Ensure claude can find its config
                env["XDG_CONFIG_HOME"] = "\(home)/.config"
                for k in env.keys where k.hasPrefix("ANTHROPIC_") || k.hasPrefix("CLAUDE_") || k.hasPrefix("__CF") {
                    env.removeValue(forKey: k)
                }
                process.environment = env

                let stdoutPipe = Pipe()
                let stderrPipe = Pipe()
                let stdinPipe  = Pipe()
                process.standardOutput = stdoutPipe
                process.standardError  = stderrPipe
                process.standardInput  = stdinPipe

                var lineBuffer = Data()
                var stderrBuffer = Data()
                let decoder = JSONDecoder()

                stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
                    let data = handle.availableData
                    guard !data.isEmpty else { return }
                    lineBuffer.append(data)

                    // Process complete newline-terminated lines
                    while let nlRange = lineBuffer.range(of: Data([0x0A])) {
                        let lineData = Data(lineBuffer[lineBuffer.startIndex..<nlRange.lowerBound])
                        lineBuffer.removeSubrange(lineBuffer.startIndex...nlRange.lowerBound)

                        guard !lineData.isEmpty else { continue }
                        if let event = try? decoder.decode(StreamEvent.self, from: lineData) {
                            continuation.yield(event)
                        }
                        // else: non-JSON line (e.g. debug output), silently skip
                    }
                }

                stderrPipe.fileHandleForReading.readabilityHandler = { handle in
                    let data = handle.availableData
                    guard !data.isEmpty else { return }
                    stderrBuffer.append(data)
                }

                process.terminationHandler = { proc in
                    // Process any remaining stdout buffer
                    if !lineBuffer.isEmpty,
                       let event = try? decoder.decode(StreamEvent.self, from: lineBuffer) {
                        continuation.yield(event)
                    }

                    let exitCode = proc.terminationStatus
                    let errText = String(data: stderrBuffer, encoding: .utf8)?
                        .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

                    if exitCode != 0 {
                        let detail = errText.isEmpty ? "exit code \(exitCode)" : errText
                        continuation.finish(throwing: CLIError.processError(exitCode: Int(exitCode), stderr: detail))
                    } else {
                        continuation.finish()
                    }
                }

                do {
                    try process.run()
                    // Write message via stdin, then close to signal EOF.
                    // When images are provided we send a stream-json message with
                    // image content blocks (base64); otherwise plain text.
                    if imagePaths.isEmpty {
                        if let data = message.data(using: .utf8) {
                            try? stdinPipe.fileHandleForWriting.write(contentsOf: data)
                            try? stdinPipe.fileHandleForWriting.close()
                        }
                    } else {
                        var contentBlocks: [[String: Any]] = [
                            ["type": "text", "text": message]
                        ]
                        for imgPath in imagePaths where !imgPath.isEmpty {
                            if let imgData = FileManager.default.contents(atPath: imgPath) {
                                let b64 = imgData.base64EncodedString()
                                let ext = (imgPath as NSString).pathExtension.lowercased()
                                let mime: String
                                switch ext {
                                case "jpg", "jpeg": mime = "image/jpeg"
                                case "gif":         mime = "image/gif"
                                case "webp":        mime = "image/webp"
                                default:            mime = "image/png"
                                }
                                contentBlocks.append([
                                    "type": "image",
                                    "source": [
                                        "type": "base64",
                                        "media_type": mime,
                                        "data": b64
                                    ] as [String: Any]
                                ])
                            }
                        }
                        let userMsg: [String: Any] = [
                            "type": "user",
                            "message": [
                                "role": "user",
                                "content": contentBlocks
                            ] as [String: Any]
                        ]
                        if let jsonData = try? JSONSerialization.data(withJSONObject: userMsg),
                           let jsonLine = String(data: jsonData, encoding: .utf8) {
                            let payload = (jsonLine + "\n").data(using: .utf8)!
                            try? stdinPipe.fileHandleForWriting.write(contentsOf: payload)
                            try? stdinPipe.fileHandleForWriting.close()
                        }
                    }
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    // MARK: - Run claude command with stdin (non-streaming, returns full stdout)

    /// Runs claude with the given args, pipes `stdinText` via stdin, returns stdout.
    func runWithStdin(_ args: [String], stdin stdinText: String, workingDirectory: String? = nil) async throws -> String {
        let path = claudePath
        return try await withCheckedThrowingContinuation { continuation in
            // DispatchQueue.global statt Task.detached — waitUntilExit() darf keinen
            // Swift-Concurrency-Thread blockieren (erschöpft den Cooperative Thread Pool).
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                let home = NSHomeDirectory()
                process.executableURL = URL(fileURLWithPath: path)
                process.arguments = args

                if let cwd = workingDirectory, !cwd.isEmpty {
                    process.currentDirectoryURL = URL(fileURLWithPath: cwd)
                }

                var env = ProcessInfo.processInfo.environment
                let extraPaths = "\(home)/.local/bin:/usr/local/bin:/opt/homebrew/bin:/opt/homebrew/sbin"
                env["PATH"] = extraPaths + ":" + (env["PATH"] ?? "/usr/bin:/bin")
                env["HOME"] = home
                env["XDG_CONFIG_HOME"] = "\(home)/.config"
                for k in env.keys where k.hasPrefix("ANTHROPIC_") || k.hasPrefix("CLAUDE_") || k.hasPrefix("__CF") {
                    env.removeValue(forKey: k)
                }
                process.environment = env

                let outPipe   = Pipe()
                let stdinPipe = Pipe()
                process.standardOutput = outPipe
                process.standardError  = Pipe()
                process.standardInput  = stdinPipe

                do {
                    try process.run()
                    if let data = stdinText.data(using: .utf8) {
                        stdinPipe.fileHandleForWriting.write(data)
                    }
                    try? stdinPipe.fileHandleForWriting.close()
                    process.waitUntilExit()
                    let data = outPipe.fileHandleForReading.readDataToEndOfFile()
                    let output = String(data: data, encoding: .utf8) ?? ""
                    continuation.resume(returning: output)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    // MARK: - Auth Login

    /// Runs `claude auth login` — opens the system browser for OAuth.
    /// Resolves when login completes successfully, throws on failure.
    func login() async throws {
        let path = claudePath
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            Task.detached(priority: .userInitiated) {
                let process = Process()
                let home = NSHomeDirectory()
                process.executableURL = URL(fileURLWithPath: path)
                process.arguments = ["auth", "login"]

                var env = ProcessInfo.processInfo.environment
                let extraPaths = "\(home)/.local/bin:/usr/local/bin:/opt/homebrew/bin:/opt/homebrew/sbin"
                env["PATH"] = extraPaths + ":" + (env["PATH"] ?? "/usr/bin:/bin")
                env["HOME"] = home
                env["XDG_CONFIG_HOME"] = "\(home)/.config"
                for k in env.keys where k.hasPrefix("ANTHROPIC_") || k.hasPrefix("CLAUDE_") || k.hasPrefix("__CF") {
                    env.removeValue(forKey: k)
                }
                process.environment = env

                let outPipe = Pipe()
                let errPipe = Pipe()
                process.standardOutput = outPipe
                process.standardError  = errPipe

                process.terminationHandler = { proc in
                    if proc.terminationStatus == 0 {
                        continuation.resume()
                    } else {
                        let out = String(data: outPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                        let err = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                        let msg = [out, err].filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.joined(separator: "\n")
                        continuation.resume(throwing: CLIError.processError(
                            exitCode: Int(proc.terminationStatus),
                            stderr: msg.isEmpty ? "Login fehlgeschlagen (exit \(proc.terminationStatus))" : msg
                        ))
                    }
                }

                do { try process.run() } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    // MARK: - Run claude command (non-streaming, returns full stdout)

    func runCommand(_ args: [String]) async throws -> String {
        let path = claudePath   // capture MainActor property before leaving actor
        return try await withCheckedThrowingContinuation { continuation in
            // DispatchQueue.global statt Task.detached — waitUntilExit() darf keinen
            // Swift-Concurrency-Thread blockieren (erschöpft den Cooperative Thread Pool).
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                let home = NSHomeDirectory()
                process.executableURL = URL(fileURLWithPath: path)
                process.arguments = args

                var env = ProcessInfo.processInfo.environment
                let extraPaths = "\(home)/.local/bin:/usr/local/bin:/opt/homebrew/bin"
                env["PATH"] = extraPaths + ":" + (env["PATH"] ?? "/usr/bin:/bin")
                env["HOME"] = home
                for k in env.keys where k.hasPrefix("ANTHROPIC_") || k.hasPrefix("CLAUDE_") || k.hasPrefix("__CF") {
                    env.removeValue(forKey: k)
                }
                process.environment = env

                let outPipe = Pipe()
                process.standardOutput = outPipe
                process.standardError  = Pipe()

                do {
                    try process.run()
                    process.waitUntilExit()
                    let data = outPipe.fileHandleForReading.readDataToEndOfFile()
                    let output = String(data: data, encoding: .utf8) ?? ""
                    continuation.resume(returning: output)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    // MARK: - List MCP servers

    func listMCPServers() async -> [MCPServer] {
        guard let output = try? await runCommand(["mcp", "list"]) else { return [] }
        return parseMCPList(output)
    }

    private func parseMCPList(_ output: String) -> [MCPServer] {
        var servers: [MCPServer] = []
        let lines = output.components(separatedBy: "\n").filter { !$0.isEmpty }

        for line in lines {
            // Formats emitted by current Claude CLI:
            //   "  name: https://url (HTTP) - ✓ Connected"
            //   "  name: https://url (SSE) - ✗ Failed to connect"
            //   "  name: npx -y pkg --stdio - ✓ Connected"
            //   "  name (stdio): Connected"   (older format)
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { continue }

            var name      = trimmed
            var transport = "unknown"
            var statusText = ""
            var urlDetail = ""  // actual URL or command string for this server

            // Detect which format we have:
            // Old format: "name (type): status"  → paren before first colon
            // New format: "name: rest (TYPE) - status" → colon before first paren (or no paren)

            let firstColon = trimmed.firstIndex(of: ":")
            let firstParen = trimmed.firstIndex(of: "(")

            if let pOpen = firstParen, let fc = firstColon, pOpen < fc {
                // Old format: "name (type): status"
                if let pClose = trimmed[pOpen...].firstIndex(of: ")") {
                    transport = String(trimmed[trimmed.index(after: pOpen)..<pClose]).lowercased()
                    let afterClose = trimmed[trimmed.index(after: pClose)...]
                    if let col = afterClose.firstIndex(of: ":") {
                        name = String(trimmed[..<pOpen]).trimmingCharacters(in: .whitespaces)
                        statusText = String(afterClose[afterClose.index(after: col)...]).trimmingCharacters(in: .whitespaces)
                    }
                }
            } else if let fc = firstColon {
                // New format: "name: rest (TYPE) - ✓ status"
                name = String(trimmed[..<fc]).trimmingCharacters(in: .whitespaces)
                let rest = String(trimmed[trimmed.index(after: fc)...]).trimmingCharacters(in: .whitespaces)

                // Extract transport from (HTTP)/(SSE)/(stdio) in rest, URL is before the paren
                var urlOrCommand = rest
                if let pOpen = rest.firstIndex(of: "("),
                   let pClose = rest[pOpen...].firstIndex(of: ")") {
                    transport = String(rest[rest.index(after: pOpen)..<pClose]).lowercased()
                    urlOrCommand = String(rest[..<pOpen]).trimmingCharacters(in: .whitespaces)
                }

                // Extract status after " - "
                if let dashRange = rest.range(of: " - ") {
                    statusText = String(rest[dashRange.upperBound...])
                        .trimmingCharacters(in: .whitespaces)
                        .replacingOccurrences(of: "^[✓✗!?·\\s]+", with: "", options: .regularExpression)
                        .trimmingCharacters(in: .whitespaces)
                    // Also trim " - status" from the URL part
                    if let dashInUrl = urlOrCommand.range(of: " - ") {
                        urlOrCommand = String(urlOrCommand[..<dashInUrl.lowerBound]).trimmingCharacters(in: .whitespaces)
                    }
                } else {
                    statusText = rest
                }
                // Store the actual URL/command separately so buildMCPConfigJSON can use it
                urlDetail = urlOrCommand
            }

            guard !name.isEmpty else { continue }

            let lower = statusText.lowercased()
            let status: MCPStatus
            if lower.contains("connect") {
                status = .connected
            } else if lower.contains("auth") || lower.contains("login") || lower.contains("needs") {
                status = .needsAuth
            } else if lower.contains("error") || lower.contains("fail") {
                status = .error(statusText)
            } else {
                status = .unknown
            }

            servers.append(MCPServer(
                id: name,
                name: name,
                type: transport,
                status: status,
                detail: urlDetail.isEmpty ? statusText : urlDetail
            ))
        }
        return servers
    }

    // MARK: - Add / Remove MCP servers

    /// Add an MCP server. Returns (success, output).
    func addMCPServer(
        name: String,
        transport: String,      // "stdio", "http", "sse"
        commandOrUrl: String,
        args: [String] = [],
        headers: [String] = [], // e.g. ["Authorization: Bearer xxx"]
        envVars: [String] = [], // e.g. ["API_KEY=xxx"]
        scope: MCPScope = .user,
        projectDir: String? = nil
    ) async -> (Bool, String) {
        var cliArgs = ["mcp", "add", "--transport", transport, "--scope", scope.cliFlag]
        if let dir = projectDir, !dir.isEmpty, scope == .project || scope == .local {
            cliArgs += ["--project-dir", dir]
        }
        for h in headers { cliArgs += ["--header", h] }
        for e in envVars { cliArgs += ["-e", e] }
        cliArgs += ["--", name, commandOrUrl]
        cliArgs += args
        let output = (try? await runCommand(cliArgs)) ?? "Fehler"
        return (!output.lowercased().contains("error"), output)
    }

    func removeMCPServer(name: String, scope: MCPScope = .user, projectDir: String? = nil) async -> (Bool, String) {
        var cliArgs = ["mcp", "remove", "--scope", scope.cliFlag]
        if let dir = projectDir, !dir.isEmpty, scope == .project || scope == .local {
            cliArgs += ["--project-dir", dir]
        }
        cliArgs += [name]
        let output = (try? await runCommand(cliArgs)) ?? "Fehler"
        return (!output.lowercased().contains("error"), output)
    }

    /// Fetch full config of one MCP server via `claude mcp get <name>`.
    func getMCPServerConfig(name: String) async -> MCPServerConfig? {
        guard let output = try? await runCommand(["mcp", "get", name]) else { return nil }
        return parseMCPGet(name: name, output: output)
    }

    private func parseMCPGet(name: String, output: String) -> MCPServerConfig? {
        // Try JSON first (Claude CLI may output JSON)
        if let data = output.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            let transport = (json["transport"] as? String) ?? "stdio"
            let command   = (json["command"] as? String) ?? ""
            let args      = (json["args"] as? [String]) ?? []
            let envDict   = (json["env"] as? [String: String]) ?? [:]
            let envVars   = envDict.map { "\($0.key)=\($0.value)" }
            let headers   = (json["headers"] as? [String: String])?.map { "\($0.key): \($0.value)" } ?? []
            let url       = (json["url"] as? String) ?? command
            return MCPServerConfig(name: name, transport: transport,
                                   commandOrUrl: command.isEmpty ? url : command,
                                   args: args, headers: headers, envVars: envVars, scope: .user)
        }

        // Fallback: parse text output line by line
        var transport = "stdio"
        var commandOrUrl = ""
        var args: [String] = []
        var envVars: [String] = []
        var headers: [String] = []

        for line in output.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.lowercased().hasPrefix("transport:") {
                transport = trimmed.dropFirst("transport:".count).trimmingCharacters(in: .whitespaces)
            } else if trimmed.lowercased().hasPrefix("type:") {
                // "Type: stdio" — synonym for transport in some CLI versions
                let t = trimmed.dropFirst("type:".count).trimmingCharacters(in: .whitespaces).lowercased()
                if !t.isEmpty { transport = t }
            } else if trimmed.lowercased().hasPrefix("command:") {
                commandOrUrl = trimmed.dropFirst("command:".count).trimmingCharacters(in: .whitespaces)
            } else if trimmed.lowercased().hasPrefix("url:") {
                commandOrUrl = trimmed.dropFirst("url:".count).trimmingCharacters(in: .whitespaces)
            } else if trimmed.lowercased().hasPrefix("args:") {
                let raw = trimmed.dropFirst("args:".count).trimmingCharacters(in: .whitespaces)
                // Multi-value: could be space-separated or a single path
                args = raw.split(separator: " ").map(String.init)
            } else if trimmed.lowercased().hasPrefix("env:") {
                let raw = trimmed.dropFirst("env:".count).trimmingCharacters(in: .whitespaces)
                if !raw.isEmpty { envVars.append(raw) }
            } else if trimmed.lowercased().hasPrefix("header:") {
                let raw = trimmed.dropFirst("header:".count).trimmingCharacters(in: .whitespaces)
                if !raw.isEmpty { headers.append(raw) }
            } else if trimmed.contains("=") && !trimmed.hasPrefix("#") {
                // KEY=VALUE env var lines (e.g. under "Environment:" section).
                // Only treat as env var if the key part contains no spaces/colons.
                let key = String(trimmed.prefix(while: { $0 != "=" }))
                if !key.contains(" ") && !key.contains(":") && !key.isEmpty {
                    envVars.append(trimmed)
                }
            }
        }

        guard !commandOrUrl.isEmpty || !output.isEmpty else { return nil }
        return MCPServerConfig(name: name, transport: transport,
                               commandOrUrl: commandOrUrl,
                               args: args, headers: headers, envVars: envVars, scope: .user)
    }

    // MARK: - Active sessions

    /// Static variant — safe to call from a detached Task (no @MainActor dependency)
    nonisolated static func loadActiveSessionsSync() -> [ActiveCLISession] {
        let home = NSHomeDirectory()
        let sessionsDir = URL(fileURLWithPath: "\(home)/.claude/sessions")

        let decoder = JSONDecoder()
        var sessions: [ActiveCLISession] = []
        var knownPIDs: Set<Int> = []

        // 1) Session-Dateien auswerten
        if let files = try? FileManager.default.contentsOfDirectory(
            at: sessionsDir, includingPropertiesForKeys: nil
        ) {
            for file in files where file.pathExtension == "json" {
                guard let data = try? Data(contentsOf: file),
                      let raw = try? decoder.decode(ActiveSessionFile.self, from: data),
                      let pid = raw.pid,
                      let sid = raw.sessionId,
                      let cwd = raw.cwd else { continue }

                let running = kill(Int32(pid), 0) == 0
                if running {
                    knownPIDs.insert(pid)
                    let started = raw.startedAt.map { Date(timeIntervalSince1970: $0 / 1000) } ?? .now
                    let topic = Self.extractSessionTopic(sessionId: sid, home: home)
                    sessions.append(ActiveCLISession(
                        id: file.lastPathComponent,
                        pid: pid,
                        sessionId: sid,
                        cwd: cwd,
                        startedAt: started,
                        kind: raw.kind ?? "interactive",
                        entrypoint: raw.entrypoint ?? "",
                        version: raw.version ?? "",
                        topic: topic
                    ))
                }
            }
        }

        // 2) pgrep-Fallback: Claude-Prozesse ohne Session-Datei erkennen
        sessions.append(contentsOf: discoverOrphanedCLIProcesses(knownPIDs: knownPIDs))

        return sessions.sorted { $0.startedAt > $1.startedAt }
    }

    /// Findet laufende Claude-CLI-Prozesse, die keine Session-Datei haben.
    private nonisolated static func discoverOrphanedCLIProcesses(knownPIDs: Set<Int>) -> [ActiveCLISession] {
        let proc = Foundation.Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        proc.arguments = ["-lf", "claude.*--model"]
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = FileHandle.nullDevice
        guard (try? proc.run()) != nil else { return [] }
        proc.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8), !output.isEmpty else { return [] }

        let myPID = Int(ProcessInfo.processInfo.processIdentifier)
        var orphans: [ActiveCLISession] = []

        for line in output.components(separatedBy: "\n") where !line.isEmpty {
            let parts = line.split(separator: " ", maxSplits: 1)
            guard let pidVal = parts.first, let pid = Int(pidVal) else { continue }
            if knownPIDs.contains(pid) || pid == myPID { continue }

            let cmdLine = parts.count > 1 ? String(parts[1]) : ""

            let model = Self.extractFlag(from: cmdLine, flag: "--model") ?? "unknown"
            let isResume = cmdLine.contains("--resume")
            let entrypoint = cmdLine.contains("claude-desktop") ? "claude-desktop"
                           : cmdLine.contains("sdk-cli") ? "sdk-cli" : "cli"

            let startDate = Self.processStartDate(pid: pid) ?? .now

            orphans.append(ActiveCLISession(
                id: "pgrep-\(pid)",
                pid: pid,
                sessionId: Self.extractFlag(from: cmdLine, flag: "--resume") ?? "unknown",
                cwd: "/",
                startedAt: startDate,
                kind: isResume ? "resumed" : "background",
                entrypoint: entrypoint,
                version: model,
                topic: isResume ? "Resumed Session (\(model))" : "Background (\(model))"
            ))
        }
        return orphans
    }

    private nonisolated static func extractFlag(from cmdLine: String, flag: String) -> String? {
        guard let range = cmdLine.range(of: flag + " ") else { return nil }
        let after = cmdLine[range.upperBound...]
        let value = after.prefix(while: { $0 != " " && $0 != "-" })
        return value.isEmpty ? nil : String(value)
    }

    private nonisolated static func processStartDate(pid: Int) -> Date? {
        let proc = Foundation.Process()
        proc.executableURL = URL(fileURLWithPath: "/bin/ps")
        proc.arguments = ["-o", "lstart=", "-p", "\(pid)"]
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = FileHandle.nullDevice
        guard (try? proc.run()) != nil else { return nil }
        proc.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let str = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !str.isEmpty else { return nil }
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.dateFormat = "EEE MMM dd HH:mm:ss yyyy"
        return fmt.date(from: str)
    }

    func loadActiveSessions() -> [ActiveCLISession] {
        Self.loadActiveSessionsSync()
    }

    private nonisolated static func extractSessionTopic(sessionId: String, home: String) -> String {
        let projectsDir = URL(fileURLWithPath: "\(home)/.claude/projects")
        guard let projectFolders = try? FileManager.default.contentsOfDirectory(
            at: projectsDir, includingPropertiesForKeys: nil
        ) else { return "" }

        let jsonlName = "\(sessionId).jsonl"
        for folder in projectFolders {
            let jsonlPath = folder.appendingPathComponent(jsonlName)
            guard FileManager.default.fileExists(atPath: jsonlPath.path) else { continue }
            guard let handle = FileHandle(forReadingAtPath: jsonlPath.path) else { continue }
            defer { handle.closeFile() }

            let chunkSize = 32_768
            guard let chunk = try? handle.read(upToCount: chunkSize), !chunk.isEmpty,
                  let text = String(data: chunk, encoding: .utf8) else { continue }

            for line in text.components(separatedBy: "\n") {
                guard !line.isEmpty,
                      let lineData = line.data(using: .utf8),
                      let obj = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
                      obj["type"] as? String == "user",
                      let msg = obj["message"] as? [String: Any],
                      msg["role"] as? String == "user",
                      let content = msg["content"] else { continue }

                if let arr = content as? [[String: Any]] {
                    for item in arr {
                        if item["type"] as? String == "text",
                           let t = item["text"] as? String, t.count > 5 {
                            let clean = t.components(separatedBy: "\n").first ?? t
                            return String(clean.prefix(120))
                        }
                    }
                } else if let s = content as? String, s.count > 5 {
                    let clean = s.components(separatedBy: "\n").first ?? s
                    return String(clean.prefix(120))
                }
            }
        }
        return ""
    }
}
