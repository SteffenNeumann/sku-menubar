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
        model: String? = nil,
        workingDirectory: String? = nil,
        skipPermissions: Bool = false
    ) -> AsyncThrowingStream<StreamEvent, Error> {
        let path = claudePath
        return AsyncThrowingStream { continuation in
            Task.detached(priority: .userInitiated) {
                var args: [String] = ["--print", "--output-format", "stream-json", "--verbose"]
                if skipPermissions {
                    args.append("--dangerously-skip-permissions")
                }

                if let sid = sessionId, !sid.isEmpty {
                    args += ["--resume", sid]
                }
                if let a = agentName, !a.isEmpty {
                    args += ["--agent", a]
                }
                if let m = model, !m.isEmpty {
                    args += ["--model", m]
                }
                args.append(message)

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
                process.environment = env

                let stdoutPipe = Pipe()
                let stderrPipe = Pipe()
                process.standardOutput = stdoutPipe
                process.standardError  = stderrPipe

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
                    } else if !errText.isEmpty {
                        // Exit 0 but stderr has content — surface as an error for diagnosis
                        continuation.finish(throwing: CLIError.processError(exitCode: 0, stderr: errText))
                    } else {
                        continuation.finish()
                    }
                }

                do {
                    try process.run()
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
            // Expected formats:
            // "  server-name (http): Connected"
            // "  server-name (stdio): Needs authentication"
            // "  server-name: ..."
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { continue }

            // Try to parse "name (type): status" or "name: status"
            var name = trimmed
            var type = "unknown"
            var statusText = ""

            if let parenOpen = trimmed.firstIndex(of: "("),
               let parenClose = trimmed[parenOpen...].firstIndex(of: ")") {
                type = String(trimmed[trimmed.index(after: parenOpen)..<parenClose])
                let afterParen = trimmed[trimmed.index(after: parenClose)...]
                if let colon = afterParen.firstIndex(of: ":") {
                    name = String(trimmed[..<parenOpen]).trimmingCharacters(in: .whitespaces)
                    statusText = String(afterParen[afterParen.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
                }
            } else if let colon = trimmed.firstIndex(of: ":") {
                name = String(trimmed[..<colon]).trimmingCharacters(in: .whitespaces)
                statusText = String(trimmed[trimmed.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
            }

            let status: MCPStatus
            let lower = statusText.lowercased()
            if lower.contains("connect") {
                status = .connected
            } else if lower.contains("auth") || lower.contains("login") {
                status = .needsAuth
            } else if lower.contains("error") || lower.contains("fail") {
                status = .error(statusText)
            } else {
                status = .unknown
            }

            servers.append(MCPServer(
                id: name,
                name: name,
                type: type,
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
        envVars: [String] = []  // e.g. ["API_KEY=xxx"]
    ) async -> (Bool, String) {
        var cliArgs = ["mcp", "add", "--transport", transport]
        for h in headers { cliArgs += ["--header", h] }
        for e in envVars { cliArgs += ["-e", e] }
        cliArgs += [name, commandOrUrl]
        cliArgs += args
        let output = (try? await runCommand(cliArgs)) ?? "Fehler"
        return (!output.lowercased().contains("error"), output)
    }

    func removeMCPServer(name: String) async -> (Bool, String) {
        let output = (try? await runCommand(["mcp", "remove", name])) ?? "Fehler"
        return (!output.lowercased().contains("error"), output)
    }

    // MARK: - Active sessions

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
