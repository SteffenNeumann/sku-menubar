import Foundation

// MARK: - MCP Client Session
// Lightweight MCP (Model Context Protocol) JSON-RPC client.
// Supports stdio and HTTP(S) transports.
// Mehrere Calls duerfen gleichzeitig laufen; Antworten werden ueber die JSON-RPC-id
// zugeordnet und Warter per NSCondition geweckt.

final class MCPClientSession: @unchecked Sendable {

    let config: MCPServerConfig

    private var process: Process?
    private var stdinHandle: FileHandle?
    private var stdoutHandle: FileHandle?
    private var nextId = 1
    /// Deckt nextId, readBuffer, stderrTail, pendingResponses, awaitedIds und processExited ab
    /// und weckt zugleich die Warter in waitForResponse.
    private let lock = NSCondition()
    private var stderrHandle: FileHandle?
    /// Rohbytes; erst pro vollständiger Zeile dekodiert. Ein stdout-Chunk kann mitten in
    /// einer UTF-8-Multibyte-Sequenz enden (z.B. Umlaut auf der 64-KiB-Grenze) — dekodiert
    /// man chunkweise, liefert String(data:encoding:) nil und der Chunk geht still verloren.
    private var readBuffer = Data()
    /// Letzte stderr-Ausgabe des Servers, als Diagnosetext bei Timeout/Verbindungsfehler.
    private var stderrTail = Data()
    /// Notbremse gegen unbegrenztes Wachstum, falls ein Server nie "\n" sendet.
    private static let readBufferCap = 32 * 1024 * 1024
    private static let stderrTailCap = 16 * 1024
    // id → (result, errorMessage)
    private var pendingResponses: [Int: (result: [String: Any]?, error: String?)] = [:]
    /// Ids, auf die gerade jemand wartet. Antworten auf abgelaufene Calls werden verworfen,
    /// statt als Leichen in pendingResponses liegenzubleiben.
    private var awaitedIds: Set<Int> = []
    private var processExited = false
    /// Zaehlt die Prozess-Generationen. Der terminationHandler eines abgeloesten
    /// Prozesses feuert verzoegert und darf die neue Session nicht als tot markieren.
    private var generation = 0
    /// Laufender Verbindungsaufbau, damit parallele connect()-Aufrufe darauf warten,
    /// statt einen zweiten Prozess zu starten.
    private var connectTask: Task<Void, Error>?
    /// Gesetzt, wenn readBufferCap gerissen wurde — die Session ist dann nicht mehr
    /// synchron zum Server, weitere Antworten waeren Fragmente.
    private var bufferOverflowed = false
    private var connected = false

    /// Absicherung fuer Einstiege ohne App-Start (Tests, Kommandozeilen-Tools):
    /// ohne SIG_IGN beendet ein Write auf eine geschlossene Pipe den gesamten Prozess
    /// (SIGPIPE, exit 141) — write(contentsOf:) kommt gar nicht erst zum Werfen.
    /// Die App setzt es zusaetzlich frueher, in SKUMenuBarApp.init().
    private static let ignoreSIGPIPE: Void = { signal(SIGPIPE, SIG_IGN) }()

    init(config: MCPServerConfig) {
        _ = Self.ignoreSIGPIPE
        self.config = config
    }

    // MARK: - Connect

    func connect() async throws {
        // HTTP transport: no persistent connection; initialize is done per call
        guard config.transport == "stdio" else {
            connected = true
            return
        }

        lock.lock()
        // Nach Serverabsturz oder Pufferueberlauf ist die Session unbrauchbar —
        // ohne diesen Pfad bliebe sie es bis zum App-Neustart.
        let needsRestart = processExited || bufferOverflowed
        if connected && !needsRestart { lock.unlock(); return }
        // Zwei gleichzeitige Aufrufe duerfen sich nicht gegenseitig den frisch
        // gestarteten Prozess abschiessen (connectStdio raeumt eine Vorsession ab).
        let task: Task<Void, Error>
        if let existing = connectTask {
            task = existing
        } else {
            task = Task { [weak self] in
                guard let self else { throw MCPClientError.disconnected }
                try await self.connectStdio()
            }
            connectTask = task
        }
        lock.unlock()

        do {
            try await task.value
        } catch {
            clearConnectTask(task)
            throw error
        }
        clearConnectTask(task)
        connected = true
    }

    private func clearConnectTask(_ task: Task<Void, Error>) {
        lock.lock()
        if connectTask == task { connectTask = nil }
        lock.unlock()
    }

    private func connectStdio() async throws {
        // Reste einer vorherigen Session abraeumen — sonst bleiben Handler und
        // Deskriptoren der alten Pipes haengen (fd-Leak + Dauerlast nach EOF).
        if process != nil { stop() }

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
        let errPipe = Pipe()
        proc.standardInput  = inPipe
        proc.standardOutput = outPipe
        proc.standardError  = errPipe

        lock.lock()
        generation      += 1
        let myGeneration = generation
        processExited    = false
        bufferOverflowed = false
        readBuffer.removeAll(keepingCapacity: false)
        stderrTail.removeAll(keepingCapacity: false)
        lock.unlock()

        // Stirbt der Server (Crash, Kommando nicht gefunden), sollen Warter das sofort
        // erfahren statt volle 30s in den Timeout zu laufen.
        proc.terminationHandler = { [weak self] _ in
            guard let self else { return }
            // Die Pipes dieser Generation direkt fassen, nicht self.stdoutHandle —
            // das gehoert nach einem Reconnect schon der naechsten Session.
            outPipe.fileHandleForReading.readabilityHandler = nil
            errPipe.fileHandleForReading.readabilityHandler = nil
            self.lock.lock()
            if self.generation == myGeneration {
                self.processExited = true
                self.lock.broadcast()
            }
            self.lock.unlock()
        }

        try proc.run()

        self.process      = proc
        self.stdinHandle  = inPipe.fileHandleForWriting
        self.stdoutHandle = outPipe.fileHandleForReading
        self.stderrHandle = errPipe.fileHandleForReading

        // Set up async reader using readabilityHandler.
        // Rohbytes werden gepuffert und erst zeilenweise geparst — niemals chunkweise dekodiert.
        outPipe.fileHandleForReading.readabilityHandler = { [weak self] fh in
            guard let self else { fh.readabilityHandler = nil; return }
            let data = fh.availableData
            // Leeres availableData heisst EOF. Ohne Abhaengen ruft Foundation den
            // Handler danach endlos erneut auf (gemessen: ~1,5 Mio Aufrufe/s).
            guard !data.isEmpty else { fh.readabilityHandler = nil; return }
            self.processIncoming(data)
        }

        // stderr muss mitgelesen werden: ist der Pipe-Puffer (64 KiB) voll, blockiert der
        // Server im Schreibaufruf und liefert auch auf stdout nichts mehr.
        errPipe.fileHandleForReading.readabilityHandler = { [weak self] fh in
            guard let self else { fh.readabilityHandler = nil; return }
            let data = fh.availableData
            guard !data.isEmpty else { fh.readabilityHandler = nil; return }   // EOF
            self.lock.lock()
            self.stderrTail.append(data)
            if self.stderrTail.count > Self.stderrTailCap {
                let overflow = self.stderrTail.count - Self.stderrTailCap
                let cutEnd = self.stderrTail.index(self.stderrTail.startIndex, offsetBy: overflow)
                self.stderrTail.removeSubrange(self.stderrTail.startIndex ..< cutEnd)
            }
            self.lock.unlock()
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

    private func processIncoming(_ chunk: Data) {
        var completedLines: [Data] = []

        lock.lock()
        // Was vor dem Anhaengen im Puffer stand, enthaelt per Invariante keine Newline
        // mehr (unten wird bis zur letzten entfernt). Nur den neuen Bereich absuchen —
        // sonst skaliert jeder Chunk mit der Gesamtgroesse, also quadratisch.
        let searchFrom = readBuffer.count
        readBuffer.append(chunk)
        let searchStart = readBuffer.index(readBuffer.startIndex, offsetBy: searchFrom)
        if let lastNL = readBuffer[searchStart...].lastIndex(of: 0x0a) {
            var start = readBuffer.startIndex
            var i = searchStart
            while i <= lastNL {
                if readBuffer[i] == 0x0a {
                    if i > start { completedLines.append(Data(readBuffer[start ..< i])) }
                    start = readBuffer.index(after: i)
                }
                i = readBuffer.index(after: i)
            }
            // Ein einziges removeSubrange bis zur letzten Newline statt eines pro Zeile.
            readBuffer.removeSubrange(readBuffer.startIndex ... lastNL)
        }
        if readBuffer.count > Self.readBufferCap {
            readBuffer.removeAll(keepingCapacity: false)
            bufferOverflowed = true
            lock.broadcast()     // sonst warten alle Calls sinnlos die vollen 30s ab
        }
        lock.unlock()

        for var lineData in completedLines {
            if lineData.last == 0x0d { lineData.removeLast() }   // CRLF
            // JSONSerialization liest UTF-8-Bytes direkt — kein String-Umweg nötig.
            guard let obj = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
                  let id  = obj["id"] as? Int else { continue }

            let result   = obj["result"] as? [String: Any]
            let errorMsg = (obj["error"] as? [String: Any])?["message"] as? String

            lock.lock()
            if awaitedIds.contains(id) {
                pendingResponses[id] = (result: result, error: errorMsg)
                lock.broadcast()
            }   // sonst: Antwort auf einen laengst abgelaufenen Call — verwerfen
            lock.unlock()
        }
    }

    // MARK: - JSON-RPC send

    private func sendNotification(_ method: String, params: [String: Any]? = nil) {
        var msg: [String: Any] = ["jsonrpc": "2.0", "method": method]
        if let p = params { msg["params"] = p }
        guard let data = try? JSONSerialization.data(withJSONObject: msg) else { return }
        var line = data; line.append(0x0a)
        lock.lock(); let dead = processExited; lock.unlock()
        guard !dead else { return }
        try? stdinHandle?.write(contentsOf: line)
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
            throw MCPClientError.encodingError   // id bleibt ungenutzt, kein Eintrag noetig
        }
        var lineData = data; lineData.append(0x0a)

        guard let stdin = stdinHandle else { throw MCPClientError.disconnected }
        lock.lock()
        let dead = processExited
        if !dead { awaitedIds.insert(id) }
        lock.unlock()
        // Spart den zwecklosen Write; der eigentliche Schutz ist SIG_IGN oben.
        if dead { throw MCPClientError.serverTerminated(recentStderr()) }
        do {
            try stdin.write(contentsOf: lineData)
        } catch {
            lock.lock(); awaitedIds.remove(id); lock.unlock()
            throw MCPClientError.serverTerminated(recentStderr())
        }

        // Wait for matching response in a background thread (blocks)
        return try await Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { throw MCPClientError.disconnected }
            return try self.waitForResponse(id: id, timeout: 30)
        }.value
    }

    /// Blocks until the response for `id` arrives, the server dies, or the timeout expires.
    private func waitForResponse(id: Int, timeout: TimeInterval) throws -> [String: Any] {
        let deadline = Date().addingTimeInterval(timeout)
        lock.lock()
        defer {
            awaitedIds.remove(id)
            pendingResponses.removeValue(forKey: id)
            lock.unlock()
        }
        while true {
            if let response = pendingResponses[id] {
                if let err = response.error { throw MCPClientError.serverError(err) }
                return response.result ?? [:]
            }
            if bufferOverflowed {
                throw MCPClientError.responseTooLarge
            }
            if processExited {
                throw MCPClientError.serverTerminated(recentStderrLocked())
            }
            // Weckt bei jeder eintreffenden Antwort und beim Prozessende; die Schleife
            // prueft erneut, statt auf einen Zaehler zu vertrauen.
            if !lock.wait(until: deadline) {
                // Antwort kann exakt am Deadline-Rand eingetroffen sein.
                if let response = pendingResponses[id] {
                    if let err = response.error { throw MCPClientError.serverError(err) }
                    return response.result ?? [:]
                }
                throw MCPClientError.timeout(recentStderrLocked())
            }
        }
    }

    /// Nimmt das Lock selbst — nur aus ungelockten Kontexten aufrufen.
    private func recentStderr() -> String {
        lock.lock()
        defer { lock.unlock() }
        return recentStderrLocked()
    }

    /// Letzte stderr-Zeilen des Servers als lesbarer Diagnosetext (leer, wenn nichts anlag).
    /// Erwartet ein bereits gehaltenes `lock` — NSCondition ist nicht rekursiv.
    private func recentStderrLocked() -> String {
        let tail = stderrTail
        guard !tail.isEmpty else { return "" }
        return String(decoding: tail, as: UTF8.self)
            .components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            .suffix(3)
            .joined(separator: " | ")
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
        try await connect()   // entscheidet selbst, ob ein Aufbau noetig ist
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
        stderrHandle?.readabilityHandler = nil
        stdinHandle?.closeFile()
        // Muss vor terminate() weg, sonst markiert der Handler die naechste Session als tot.
        process?.terminationHandler = nil
        process?.terminate()
        // Lese-Deskriptoren schliessen — sonst leckt jeder Reconnect zwei fds.
        try? stdoutHandle?.close()
        try? stderrHandle?.close()
        stdoutHandle = nil
        stderrHandle = nil
        stdinHandle  = nil
        process      = nil
        connected    = false
        lock.lock()
        processExited = true
        connectTask?.cancel()
        connectTask = nil
        pendingResponses.removeAll()
        awaitedIds.removeAll()
        readBuffer.removeAll(keepingCapacity: false)
        lock.broadcast()          // wartende Calls nicht bis zum Timeout haengen lassen
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
    /// Assoziierter Wert: letzte stderr-Ausgabe des Servers (ggf. leer).
    case timeout(String)
    case serverTerminated(String)
    case responseTooLarge

    var errorDescription: String? {
        switch self {
        case .serverError(let m): return "MCP server error: \(m)"
        case .encodingError:      return "MCP encoding error"
        case .invalidURL:         return "MCP invalid URL"
        case .invalidResponse:    return "MCP invalid response"
        case .disconnected:       return "MCP disconnected"
        case .responseTooLarge:   return "MCP-Antwort zu gross — Verbindung nicht mehr synchron"
        case .serverTerminated(let stderr):
            return stderr.isEmpty
                ? "MCP server beendet"
                : "MCP server beendet — meldete: \(stderr)"
        case .timeout(let stderr):
            return stderr.isEmpty
                ? "MCP request timed out"
                : "MCP request timed out — Server meldete: \(stderr)"
        }
    }
}
