import Foundation

// MARK: - Git Shell Service

final class GitShellService {

    struct GitResult {
        let success: Bool
        let output: String
        let error: String
        var combined: String { [output, error].filter { !$0.isEmpty }.joined(separator: "\n") }
    }

    // MARK: - Git binary discovery

    static let gitPath: String = {
        let candidates = [
            "/opt/homebrew/bin/git",   // Apple Silicon Homebrew
            "/usr/local/bin/git",       // Intel Homebrew
            "/usr/bin/git",             // Xcode CLT stub
        ]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) } ?? "/usr/bin/git"
    }()

    // MARK: - Internal runner (called directly for background execution)

    func run(_ args: [String], in directory: URL) -> GitResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: Self.gitPath)
        process.arguments = args
        process.currentDirectoryURL = directory

        // Ensure Homebrew path is included
        var env = ProcessInfo.processInfo.environment
        let extraPaths = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
        env["PATH"] = extraPaths + ":" + (env["PATH"] ?? "")
        process.environment = env

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        do { try process.run() } catch {
            return GitResult(success: false, output: "", error: error.localizedDescription)
        }
        process.waitUntilExit()

        let output = String(data: outPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let errOut = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return GitResult(success: process.terminationStatus == 0, output: output, error: errOut)
    }

    // MARK: - Repo discovery

    /// Returns the git repo root for the given file or directory URL, or nil if not in a repo.
    func repoRoot(for url: URL) -> URL? {
        let dir = url.hasDirectoryPath ? url : url.deletingLastPathComponent()
        let result = run(["rev-parse", "--show-toplevel"], in: dir)
        guard result.success else { return nil }
        let path = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
        return URL(fileURLWithPath: path)
    }

    func currentBranch(in repoURL: URL) -> String {
        let result = run(["branch", "--show-current"], in: repoURL)
        return result.output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Returns the remote origin URL (e.g. https://github.com/user/repo.git)
    func remoteURL(in repoURL: URL) -> String? {
        let result = run(["remote", "get-url", "origin"], in: repoURL)
        guard result.success else { return nil }
        return result.output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Builds a GitHub compare URL for creating a PR after push.
    func prURL(in repoURL: URL) -> URL? {
        guard let remote = remoteURL(in: repoURL) else { return nil }
        // Normalize ssh → https
        var web = remote
        if web.hasPrefix("git@github.com:") {
            web = web.replacingOccurrences(of: "git@github.com:", with: "https://github.com/")
        }
        if web.hasSuffix(".git") { web = String(web.dropLast(4)) }
        let branch = currentBranch(in: repoURL)
        guard !web.isEmpty, !branch.isEmpty else { return nil }
        return URL(string: "\(web)/compare/\(branch)?expand=1")
    }

    // MARK: - Git operations (async)

    func pull(in repoURL: URL) async -> GitResult {
        await Task.detached(priority: .userInitiated) { self.run(["pull"], in: repoURL) }.value
    }

    func add(_ fileURL: URL, in repoURL: URL) async -> GitResult {
        await Task.detached(priority: .userInitiated) {
            self.run(["add", fileURL.path], in: repoURL)
        }.value
    }

    func commit(message: String, in repoURL: URL) async -> GitResult {
        await Task.detached(priority: .userInitiated) {
            self.run(["commit", "-m", message], in: repoURL)
        }.value
    }

    func push(in repoURL: URL) async -> GitResult {
        await Task.detached(priority: .userInitiated) { self.run(["push"], in: repoURL) }.value
    }
}
