import Foundation

// MARK: - EmailPollingService
// Polls Mail.app via AppleScript for unread emails and creates Mail drafts for replies.

@MainActor
final class EmailPollingService: ObservableObject {

    @Published var isPolling: Bool = false
    @Published var lastPollDate: Date? = nil
    @Published var lastError: String? = nil

    private let ud = UserDefaults(suiteName: "SKUMenuBar") ?? .standard
    private let processedIdsKey = "email_processed_message_ids_v1"
    private var pollingTimer: Timer?
    weak var workflow: CustomerInquiryWorkflow?

    // MARK: - Duplicate Prevention

    var processedIds: Set<String> {
        get { Set(ud.stringArray(forKey: processedIdsKey) ?? []) }
        set {
            // Rotate to cap at 5000 entries
            ud.set(Array(newValue.suffix(5000)), forKey: processedIdsKey)
        }
    }

    // MARK: - Lifecycle

    func start(workflow: CustomerInquiryWorkflow) {
        self.workflow = workflow
        guard pollingTimer == nil else { return }
        pollingTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in await self?.poll() }
        }
        Task { await poll() }
    }

    func stop() {
        pollingTimer?.invalidate()
        pollingTimer = nil
    }

    // MARK: - Poll

    func poll() async {
        guard !isPolling else { return }
        isPolling = true
        lastError = nil
        defer { isPolling = false; lastPollDate = Date() }

        do {
            let raw = try await fetchUnreadEmails()
            let emails = parseEmailList(raw)
            for email in emails {
                if !processedIds.contains(email.messageId) {
                    var ids = processedIds
                    ids.insert(email.messageId)
                    processedIds = ids
                    await workflow?.processNewEmail(email)
                }
            }
            // Also check for replies to open inquiries
            if let wf = workflow {
                let waiting = wf.recentInquiries.filter { $0.status == .waitingForCustomer }
                if !waiting.isEmpty {
                    let allMails = emails // already fetched above
                    for var inquiry in waiting {
                        let replies = allMails.filter { mail in
                            let subjectMatch = mail.subject.lowercased().contains(inquiry.subject.lowercased())
                                || mail.subject.lowercased().contains("re: \(inquiry.subject.lowercased())")
                            let senderMatch = mail.senderAddress.lowercased() == inquiry.senderAddress.lowercased()
                            let notProcessed = !inquiry.replyMessageIds.contains(mail.messageId)
                            return subjectMatch && senderMatch && notProcessed
                        }
                        if !replies.isEmpty {
                            let replyBodies = replies.map(\.body).joined(separator: "\n\n---\n\n")
                            inquiry.replyMessageIds += replies.map(\.messageId)
                            await wf.handleCustomerReply(for: inquiry, replyBody: replyBodies)
                        }
                    }
                }
            }
        } catch {
            lastError = error.localizedDescription
        }
    }

    // MARK: - AppleScript Execution

    func runAppleScript(_ script: String) async throws -> String {
        return try await withCheckedThrowingContinuation { continuation in
            Task.detached(priority: .userInitiated) {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
                process.arguments = ["-e", script]
                let outPipe = Pipe()
                let errPipe = Pipe()
                process.standardOutput = outPipe
                process.standardError  = errPipe
                do {
                    try process.run()
                    process.waitUntilExit()
                    let out = String(data: outPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                    if process.terminationStatus == 0 {
                        continuation.resume(returning: out.trimmingCharacters(in: .whitespacesAndNewlines))
                    } else {
                        let err = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                        continuation.resume(throwing: NSError(
                            domain: "AppleScript", code: Int(process.terminationStatus),
                            userInfo: [NSLocalizedDescriptionKey: err.isEmpty ? "osascript failed" : err]
                        ))
                    }
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    // MARK: - Fetch unread emails

    private func fetchUnreadEmails() async throws -> String {
        let script = """
tell application "Mail"
    set result to ""
    set msgs to every message of inbox whose read status is false
    repeat with m in msgs
        set msgId to message id of m
        set subj to subject of m
        set sndr to sender of m
        set bd to (content of m)
        if (count of bd) > 8000 then set bd to (text 1 thru 8000 of bd)
        set result to result & "---MESSAGE---" & return
        set result to result & "ID:" & msgId & return
        set result to result & "SUBJECT:" & subj & return
        set result to result & "SENDER:" & sndr & return
        set result to result & "BODY:" & bd & return
    end repeat
    return result
end tell
"""
        return try await runAppleScript(script)
    }

    // MARK: - Parse email list

    func parseEmailList(_ raw: String) -> [CustomerInquiry] {
        var results: [CustomerInquiry] = []
        let blocks = raw.components(separatedBy: "---MESSAGE---")
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

        for block in blocks {
            var messageId = "", subject = "", sender = ""
            var bodyLines: [String] = []
            var inBody = false

            for line in block.components(separatedBy: "\n") {
                if inBody { bodyLines.append(line); continue }
                if line.hasPrefix("ID:")       { messageId = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces) }
                else if line.hasPrefix("SUBJECT:") { subject = String(line.dropFirst(8)).trimmingCharacters(in: .whitespaces) }
                else if line.hasPrefix("SENDER:")  { sender  = String(line.dropFirst(7)).trimmingCharacters(in: .whitespaces) }
                else if line.hasPrefix("BODY:")    {
                    inBody = true
                    bodyLines.append(String(line.dropFirst(5)))
                }
            }

            guard !messageId.isEmpty else { continue }
            let (senderName, senderAddress) = parseSender(sender)
            results.append(CustomerInquiry(
                messageId: messageId,
                subject: subject,
                senderAddress: senderAddress,
                senderName: senderName,
                body: bodyLines.joined(separator: "\n").prefix(8000).description,
                receivedAt: Date()
            ))
        }
        return results
    }

    // MARK: - Create draft reply

    func createDraftReply(to address: String, subject: String, body: String) async throws {
        let safe = { (s: String) in s.replacingOccurrences(of: "\\", with: "\\\\")
                                     .replacingOccurrences(of: "\"", with: "\\\"")
                                     .replacingOccurrences(of: "\n", with: "\\n") }
        let script = """
tell application "Mail"
    set newMsg to make new outgoing message with properties {subject:"\(safe(subject))", content:"\(safe(body))", visible:false}
    tell newMsg
        make new to recipient with properties {address:"\(safe(address))"}
    end tell
end tell
"""
        _ = try await runAppleScript(script)
    }

    // MARK: - Helpers

    private func parseSender(_ raw: String) -> (name: String, address: String) {
        if let lt = raw.firstIndex(of: "<"), let gt = raw.lastIndex(of: ">") {
            let name = String(raw[..<lt]).trimmingCharacters(in: .whitespaces)
            let addr = String(raw[raw.index(after: lt)..<gt])
            return (name, addr)
        }
        return ("", raw.trimmingCharacters(in: .whitespaces))
    }
}
