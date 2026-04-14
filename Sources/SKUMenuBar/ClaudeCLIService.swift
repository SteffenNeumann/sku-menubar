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
        mcpConfigJSON: String? = nil   // wenn gesetzt: --strict-mcp-config + --mcp-config <json>
    ) -> AsyncThrowingStream<StreamEvent, Error> {
        let path = claudePath
        return AsyncThrowingStream { continuation in
            Task.detached(priority: .userInitiated) {
                var args: [String] = ["--print", "--output-format", "stream-json", "--verbose"]
                if skipPermissions {
                    args.append("--dangerously-skip-permissions")
                }
                if let mcpJson = mcpConfigJSON, !mcpJson.isEmpty {
                    args += ["--strict-mcp-config", "--mcp-config", mcpJson]
                }

                if let sid = sessionId, !sid.isEmpty {
                    // Use --continue instead of --resume to avoid "no deferred tool marker" error
                    // (--resume is for resuming interrupted tool calls; --continue continues the
                    //  most recent session in the current working directory)
                    _ = sid
                    args += ["--continue"]
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
                // Remove VS Code / IDE proxy variables so the CLI uses the
                // claude.ai subscription instead of a proxied API key.
                env.removeValue(forKey: "ANTHROPIC_BASE_URL")
                env.removeValue(forKey: "ANTHROPIC_AUTH_TOKEN")
                env.removeValue(forKey: "ANTHROPIC_API_KEY")
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
                    // Write message via stdin, then close to signal EOF
                    if let data = message.data(using: .utf8) {
                        try? stdinPipe.fileHandleForWriting.write(contentsOf: data)
                        try? stdinPipe.fileHandleForWriting.close()
                    }
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    // MARK: - Run claude command (non-streaming, returns full stdout)

    func runCommand(_ args: [String]) async throws -> String {
        let path = claudePath   // capture MainActor property before Task.detached
        return try await withCheckedThrowingContinuation { continuation in
            Task.detached(priority: .userInitiated) {
                let process = Process()
                let home = NSHomeDirectory()
                process.executableURL = URL(fileURLWithPath: path)
                process.arguments = args

                var env = ProcessInfo.processInfo.environment
                let extraPaths = "\(home)/.local/bin:/usr/local/bin:/opt/homebrew/bin"
                env["PATH"] = extraPaths + ":" + (env["PATH"] ?? "/usr/bin:/bin")
                env["HOME"] = home
                env.removeValue(forKey: "ANTHROPIC_BASE_URL")
                env.removeValue(forKey: "ANTHROPIC_AUTH_TOKEN")
                env.removeValue(forKey: "ANTHROPIC_API_KEY")
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

    /// Like runCommand but returns (exitCode, stdout+stderr combined).
    private func runCommandFull(_ args: [String]) async -> (Int32, String) {
        let path = claudePath
        return await withCheckedContinuation { continuation in
            Task.detached(priority: .userInitiated) {
                let process = Process()
                let home = NSHomeDirectory()
                process.executableURL = URL(fileURLWithPath: path)
                process.arguments = args

                var env = ProcessInfo.processInfo.environment
                let extraPaths = "\(home)/.local/bin:/usr/local/bin:/opt/homebrew/bin"
                env["PATH"] = extraPaths + ":" + (env["PATH"] ?? "/usr/bin:/bin")
                env["HOME"] = home
                env.removeValue(forKey: "ANTHROPIC_BASE_URL")
                env.removeValue(forKey: "ANTHROPIC_AUTH_TOKEN")
                env.removeValue(forKey: "ANTHROPIC_API_KEY")
                process.environment = env

                let outPipe = Pipe()
                let errPipe = Pipe()
                process.standardOutput = outPipe
                process.standardError  = errPipe

                do {
                    try process.run()
                    process.waitUntilExit()
                    let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
                    let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
                    let outStr = String(data: outData, encoding: .utf8) ?? ""
                    let errStr = String(data: errData, encoding: .utf8) ?? ""
                    let combined = [outStr, errStr].filter { !$0.isEmpty }.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
                    continuation.resume(returning: (process.terminationStatus, combined))
                } catch {
                    continuation.resume(returning: (1, error.localizedDescription))
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

                // Extract transport from (HTTP)/(SSE)/(stdio) in rest
                if let pOpen = rest.firstIndex(of: "("),
                   let pClose = rest[pOpen...].firstIndex(of: ")") {
                    transport = String(rest[rest.index(after: pOpen)..<pClose]).lowercased()
                }

                // Extract status after " - "
                if let dashRange = rest.range(of: " - ") {
                    statusText = String(rest[dashRange.upperBound...])
                        .trimmingCharacters(in: .whitespaces)
                        // strip leading unicode checkmarks/crosses
                        .replacingOccurrences(of: "^[✓✗!?·\\s]+", with: "", options: .regularExpression)
                        .trimmingCharacters(in: .whitespaces)
                } else {
                    statusText = rest
                }
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
                detail: statusText
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
        // name + command first, then -e flags, then "--" + subprocess args
        cliArgs += [name, commandOrUrl]
        for e in envVars { cliArgs += ["-e", e] }
        // Use "--" separator so the CLI doesn't interpret args like "-y" as its own flags
        if !args.isEmpty {
            cliArgs += ["--"] + args
        }
        let (code, output) = await runCommandFull(cliArgs)
        return (code == 0, output.isEmpty ? (code == 0 ? "OK" : "Unbekannter Fehler (exit \(code))") : output)
    }

    func removeMCPServer(name: String, scope: MCPScope = .user, projectDir: String? = nil) async -> (Bool, String) {
        var cliArgs = ["mcp", "remove", "--scope", scope.cliFlag]
        if let dir = projectDir, !dir.isEmpty, scope == .project || scope == .local {
            cliArgs += ["--project-dir", dir]
        }
        cliArgs += [name]
        let (code, output) = await runCommandFull(cliArgs)
        return (code == 0, output)
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
            } else if trimmed.lowercased().hasPrefix("command:") {
                commandOrUrl = trimmed.dropFirst("command:".count).trimmingCharacters(in: .whitespaces)
            } else if trimmed.lowercased().hasPrefix("url:") {
                commandOrUrl = trimmed.dropFirst("url:".count).trimmingCharacters(in: .whitespaces)
            } else if trimmed.lowercased().hasPrefix("args:") {
                let raw = trimmed.dropFirst("args:".count).trimmingCharacters(in: .whitespaces)
                args = raw.split(separator: " ").map(String.init)
            } else if trimmed.lowercased().hasPrefix("env:") {
                let raw = trimmed.dropFirst("env:".count).trimmingCharacters(in: .whitespaces)
                if !raw.isEmpty { envVars.append(raw) }
            } else if trimmed.lowercased().hasPrefix("header:") {
                let raw = trimmed.dropFirst("header:".count).trimmingCharacters(in: .whitespaces)
                if !raw.isEmpty { headers.append(raw) }
            } else if trimmed.contains("=") && !trimmed.hasPrefix("#") && commandOrUrl.isEmpty {
                // Bare KEY=VALUE lines
                envVars.append(trimmed)
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
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: sessionsDir,
            includingPropertiesForKeys: nil
        ) else { return [] }

        let decoder = JSONDecoder()
        var sessions: [ActiveCLISession] = []

        for file in files where file.pathExtension == "json" {
            guard let data = try? Data(contentsOf: file),
                  let raw = try? decoder.decode(ActiveSessionFile.self, from: data),
                  let pid = raw.pid,
                  let sid = raw.sessionId,
                  let cwd = raw.cwd else { continue }

            let running = kill(Int32(pid), 0) == 0
            if running {
                let started = raw.startedAt.map { Date(timeIntervalSince1970: $0 / 1000) } ?? .now
                sessions.append(ActiveCLISession(
                    id: file.lastPathComponent,
                    pid: pid,
                    sessionId: sid,
                    cwd: cwd,
                    startedAt: started,
                    kind: raw.kind ?? "interactive"
                ))
            }
        }
        return sessions.sorted { $0.startedAt > $1.startedAt }
    }

    func loadActiveSessions() -> [ActiveCLISession] {
        let home = NSHomeDirectory()
        let sessionsDir = URL(fileURLWithPath: "\(home)/.claude/sessions")
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: sessionsDir,
            includingPropertiesForKeys: nil
        ) else { return [] }

        let decoder = JSONDecoder()
        var sessions: [ActiveCLISession] = []

        for file in files where file.pathExtension == "json" {
            guard let data = try? Data(contentsOf: file),
                  let raw = try? decoder.decode(ActiveSessionFile.self, from: data),
                  let pid = raw.pid,
                  let sid = raw.sessionId,
                  let cwd = raw.cwd else { continue }

            // Check if process is still running
            let running = kill(Int32(pid), 0) == 0

            if running {
                let started = raw.startedAt.map { Date(timeIntervalSince1970: $0 / 1000) } ?? .now
                sessions.append(ActiveCLISession(
                    id: file.lastPathComponent,
                    pid: pid,
                    sessionId: sid,
                    cwd: cwd,
                    startedAt: started,
                    kind: raw.kind ?? "interactive"
                ))
            }
        }
        return sessions.sorted { $0.startedAt > $1.startedAt }
    }
}
