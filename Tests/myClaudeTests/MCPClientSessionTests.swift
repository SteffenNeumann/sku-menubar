import XCTest
@testable import myClaude

/// Regressionstest fuer den Datenverlust an Chunk-Grenzen.
///
/// `FileHandle.availableData` liefert stdout in 64-KiB-Haeppchen. Die alte Implementierung
/// dekodierte jedes Haeppchen einzeln per `String(data:encoding:.utf8)`. Endete eines mitten
/// in einer UTF-8-Multibyte-Sequenz — bei deutschen Texten die Regel, nicht die Ausnahme —
/// war das Ergebnis nil und das ganze Haeppchen wurde still verworfen. Die JSON-Zeile kam nie
/// vollstaendig an, der Call lief in den Timeout, die UI zeigte eine leere Liste.
final class MCPClientSessionTests: XCTestCase {

    /// Ein minimaler MCP-Server in Python: beantwortet `initialize` und liefert bei
    /// `tools/call` eine Antwort, deren Umlaute exakt auf den 64-KiB-Grenzen liegen.
    private func writeFakeServer(payloadBytes: Int, initDelay: Double = 0) throws -> URL {
        let script = """
        import sys, json, time

        CHUNK = 65536
        TARGET = \(payloadBytes)

        def build_line(req_id, pad):
            # Nur Umlaute: jedes Zeichen ist 2 Bytes, damit faellt jede Grenze mit
            # passender Paritaet mitten in eine Multibyte-Sequenz.
            text = "x" * pad + "\\u00e4" * (TARGET // 2)
            msg = {"jsonrpc": "2.0", "id": req_id,
                   "result": {"content": [{"type": "text", "text": text}]}}
            return json.dumps(msg, ensure_ascii=False).encode("utf-8") + b"\\n"

        def split_hits_multibyte(line):
            # Liegt mindestens eine Chunk-Grenze mitten in einer Multibyte-Sequenz?
            for off in range(CHUNK, len(line), CHUNK):
                if line[off] & 0xC0 == 0x80:
                    return True
            return False

        for raw in sys.stdin.buffer:
            raw = raw.strip()
            if not raw:
                continue
            try:
                req = json.loads(raw)
            except Exception:
                continue
            if req.get("method") == "initialize":
                time.sleep(\(initDelay))   # haelt connectStdio() offen
                out = json.dumps({"jsonrpc": "2.0", "id": req["id"],
                                  "result": {"protocolVersion": "2024-11-05"}}).encode() + b"\\n"
            elif req.get("method") == "tools/call":
                line = build_line(req["id"], 0)
                if len(line) > CHUNK:
                    if not split_hits_multibyte(line):
                        line = build_line(req["id"], 1)   # Paritaet kippen
                    assert split_hits_multibyte(line), "Testaufbau trifft keine Multibyte-Grenze"
                out = line
            else:
                continue
            sys.stdout.buffer.write(out)
            sys.stdout.buffer.flush()
        """
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("fake_mcp_\(UUID().uuidString).py")
        try script.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private func config(script: URL) -> MCPServerConfig {
        MCPServerConfig(name: "fake", transport: "stdio", commandOrUrl: "python3",
                        args: [script.path], headers: [], envVars: [], scope: .user)
    }

    /// 160 KB Antwort = drei Chunks, zwei Grenzen mitten im Umlaut.
    /// Vor dem Fix: Timeout. Danach: vollstaendiger Text.
    func testLargeResponseWithUmlautsOnChunkBoundary() async throws {
        let script = try writeFakeServer(payloadBytes: 160_000)
        defer { try? FileManager.default.removeItem(at: script) }

        let session = MCPClientSession(config: config(script: script))
        defer { session.stop() }

        try await session.connect()
        let text = try await session.callTool(name: "irgendwas", arguments: [:])

        // Auf die Umlaute zaehlen, nicht auf die Gesamtlaenge: der Fake-Server haengt
        // je nach Paritaet ein ASCII-Zeichen vorn an, um die Grenze zu treffen.
        XCTAssertEqual(text.filter { $0 == "ä" }.count, 80_000, "Antwort wurde abgeschnitten")
        XCTAssertTrue(text.hasSuffix("ä"), "Ende der Antwort fehlt")
        XCTAssertFalse(text.contains("\u{FFFD}"), "Ersatzzeichen — UTF-8 wurde zerschnitten")
    }

    /// Antwort unter der Chunk-Grenze: muss ebenfalls durchlaufen (kein Regress am kurzen Pfad).
    func testSmallResponseStillWorks() async throws {
        let script = try writeFakeServer(payloadBytes: 2_000)
        defer { try? FileManager.default.removeItem(at: script) }

        let session = MCPClientSession(config: config(script: script))
        defer { session.stop() }

        try await session.connect()
        let text = try await session.callTool(name: "irgendwas", arguments: [:])
        XCTAssertEqual(text.filter { $0 == "ä" }.count, 1_000)
    }

    /// Nach einem Serverabsturz darf ein Reconnect weder Deskriptoren liegenlassen noch
    /// die abgehaengten Pipes weiterlaufen lassen (EOF liess den readabilityHandler sonst
    /// endlos feuern — eine volle CPU pro toter Pipe, dauerhaft).
    func testReconnectAfterCrashDoesNotLeakDescriptors() async throws {
        let cfg = MCPServerConfig(name: "stirbt-sofort", transport: "stdio",
                                  commandOrUrl: "python3",
                                  args: ["-c", "import sys; sys.stdin.readline(); sys.exit(3)"],
                                  headers: [], envVars: [], scope: .user)
        let session = MCPClientSession(config: cfg)
        defer { session.stop() }

        func openDescriptors() -> Int {
            (try? FileManager.default.contentsOfDirectory(atPath: "/dev/fd").count) ?? 0
        }

        // Einmal warmlaufen, damit einmalige Allokationen nicht als Leck zaehlen.
        try? await session.connect()
        _ = try? await session.callTool(name: "x", arguments: [:])
        let before = openDescriptors()

        var cycles = 0
        for _ in 0 ..< 30 {
            try? await session.connect()
            do {
                _ = try await session.callTool(name: "x", arguments: [:])
                XCTFail("Ein toter Server darf keine Antwort liefern")
            } catch {
                cycles += 1   // beweist, dass der Zyklus wirklich lief
            }
        }
        let after = openDescriptors()

        XCTAssertEqual(cycles, 30, "Reconnect-Zyklus lief nicht wie erwartet")
        // Ein echtes Leck waere ein Vielfaches davon; die Toleranz deckt nur das
        // Rauschen anderer Aktivitaet im selben Testprozess ab.
        XCTAssertLessThanOrEqual(after - before, 4,
                                 "fd-Leck beim Reconnect: \(before) -> \(after)")
    }

    /// Reconnect, waehrend der alte Prozess noch LEBT. Haengt stop() den
    /// terminationHandler des alten Prozesses nicht ab, feuert der verzoegert und
    /// markiert die frisch gestartete Session sofort als tot.
    func testReconnectWhileOldProcessStillAlive() async throws {
        let script = try writeFakeServer(payloadBytes: 4_000)
        defer { try? FileManager.default.removeItem(at: script) }

        let session = MCPClientSession(config: config(script: script))
        defer { session.stop() }

        for runde in 1 ... 5 {
            try await session.connect()
            let text = try await session.callTool(name: "irgendwas", arguments: [:])
            XCTAssertEqual(text.filter { $0 == "ä" }.count, 2_000, "Runde \(runde)")
            session.stop()          // beendet einen noch laufenden Serverprozess
        }
    }

    /// Zwei gleichzeitige connect()-Aufrufe duerfen sich nicht gegenseitig den frisch
    /// gestarteten Serverprozess abschiessen. Ohne Serialisierung raeumt der zweite
    /// Aufruf in connectStdio() die Session des ersten ab -> serverTerminated.
    func testParallelConnectDoesNotKillEachOther() async throws {
        // Der Server laesst sich beim initialize Zeit — damit ist der erste connect()
        // garantiert noch im Aufbau, wenn der zweite hereinkommt. Genau dann raeumte
        // connectStdio() dem ersten den Prozess unter den Fuessen weg.
        let script = try writeFakeServer(payloadBytes: 4_000, initDelay: 0.4)
        defer { try? FileManager.default.removeItem(at: script) }

        // Eine Runde genuegt: wird das Fenster getroffen, ist der Fehlerfall
        // deterministisch. Wird es verfehlt, hilft auch Wiederholen nicht.
        for runde in 1 ... 1 {
            let session = MCPClientSession(config: config(script: script))
            defer { session.stop() }

            async let first: Void = session.connect()
            async let second: Void = {
                try await Task.sleep(nanoseconds: 150_000_000)   // erster ist im Aufbau
                try await session.connect()
            }()
            _ = try await (first, second)

            let text = try await session.callTool(name: "irgendwas", arguments: [:])
            XCTAssertEqual(text.filter { $0 == "ä" }.count, 2_000, "Runde \(runde)")
        }
    }

    /// Stirbt der Server, soll der wartende Call sofort scheitern statt 30s zu haengen.
    func testTerminatedServerFailsFast() async throws {
        let cfg = MCPServerConfig(name: "dies-sofort", transport: "stdio",
                                  commandOrUrl: "python3",
                                  args: ["-c", "import sys; sys.stdin.readline(); sys.exit(3)"],
                                  headers: [], envVars: [], scope: .user)
        let session = MCPClientSession(config: cfg)
        defer { session.stop() }

        let start = Date()
        do {
            _ = try await session.connect()
            _ = try await session.callTool(name: "irgendwas", arguments: [:])
            XCTFail("Aufruf haette scheitern muessen")
        } catch {
            XCTAssertLessThan(Date().timeIntervalSince(start), 10,
                              "Lief in den 30s-Timeout statt das Prozessende zu bemerken")
        }
    }
}
