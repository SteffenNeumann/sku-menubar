import Foundation
import SwiftUI

// MARK: - ConvergenceSession
// Observable state machine for one co-design loop.
// Drives ConvergenceView and owns all iteration data.

@MainActor
final class ConvergenceSession: ObservableObject {

    // MARK: Config

    struct Config {
        var maxIterations: Int = 6
        var autorun: Bool = false
        var filePath: String
        var fileContent: String
        var critic: AgentDefinition
        var designer: AgentDefinition
        var implementor: AgentDefinition
    }

    // MARK: Published state

    @Published var phase: ConvergencePhase = .idle
    @Published var iteration: Int = 0
    @Published var snapshots: [ConvergenceSnapshot] = []
    @Published var currentFileContent: String = ""
    @Published var errorMessage: String? = nil
    @Published var escalationReason: EscalationReason? = nil
    @Published var lastCritique: CritiqueReport? = nil
    @Published var lastDecision: DesignDecision? = nil
    @Published var awaitingNextRound: Bool = false    // step-mode: waiting for user tap

    // MARK: Private

    private let config: Config
    private let runner: ConvergenceRunner
    private var runTask: Task<Void, Never>? = nil

    // Patt-Detector: last two issue-hashes
    private var recentIssueHashes: [Int] = []

    init(config: Config, cli: ClaudeCLIService) {
        self.config = config
        self.runner = ConvergenceRunner(cli: cli)
        self.currentFileContent = config.fileContent
    }

    // MARK: - Control

    func start() {
        guard phase == .idle else { return }
        runTask = Task { await runLoop() }
    }

    func continueRound() {
        awaitingNextRound = false
    }

    func cancel() {
        runTask?.cancel()
        phase = .cancelled
    }

    // MARK: - Loop

    private func runLoop() async {
        while !Task.isCancelled {
            // Step-mode: wait for user confirmation before next round
            if config.autorun == false && iteration > 0 {
                awaitingNextRound = true
                while awaitingNextRound && !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 200_000_000)
                }
                if Task.isCancelled { break }
            }

            iteration += 1

            // Cap check
            if iteration > config.maxIterations {
                escalate(.capReached)
                return
            }

            let historyContext = buildHistoryContext()
            let roundInput = ConvergenceRunner.RoundInput(
                fileContent: currentFileContent,
                filePath: config.filePath,
                critic: config.critic,
                designer: config.designer,
                implementor: config.implementor,
                historyContext: historyContext,
                lastCritique: lastCritique
            )

            do {
                let output = try await runner.runRound(input: roundInput) { [weak self] p in
                    Task { @MainActor [weak self] in self?.phase = p }
                }

                // Save snapshot
                let snapshot = ConvergenceSnapshot(
                    iteration: iteration,
                    fileContent: output.newFileContent,
                    critique: output.critique,
                    decision: output.decision,
                    implementation: output.implementation,
                    createdAt: Date()
                )
                snapshots.append(snapshot)
                lastCritique = output.critique
                lastDecision = output.decision
                currentFileContent = output.newFileContent

                // Check convergence
                if output.critique.verdict == .approve && output.decision.feasible {
                    phase = .converged
                    return
                }

                // Check reject_final
                if output.critique.verdict == .rejectFinal {
                    escalate(.rejectFinal)
                    return
                }

                // Check designer infeasible with no alternatives
                if output.decision.allRejectedWithoutAlternative {
                    escalate(.designerInfeasibleNoAlternative)
                    return
                }

                // Patt-Detector
                if detectStalemate(critique: output.critique) {
                    escalate(.stalemate)
                    return
                }

            } catch {
                if Task.isCancelled { break }
                errorMessage = error.localizedDescription
                phase = .escalation
                return
            }
        }
    }

    // MARK: - Helpers

    private func escalate(_ reason: EscalationReason) {
        escalationReason = reason
        phase = .escalation
    }

    private func buildHistoryContext() -> String {
        snapshots.map { snap in
            let verdict = snap.critique?.verdict.rawValue ?? "?"
            let mainIssue = snap.critique?.issues.first?.what ?? "—"
            let feasible = snap.decision?.feasible == true ? "feasible" : "infeasible"
            return "Runde \(snap.iteration): verdict=\(verdict), issue=\(mainIssue), designer=\(feasible)"
        }.joined(separator: "\n")
    }

    private func detectStalemate(critique: CritiqueReport) -> Bool {
        let hash = critique.issues.map { $0.what }.sorted().joined().hashValue
        recentIssueHashes.append(hash)
        if recentIssueHashes.count > 2 { recentIssueHashes.removeFirst() }
        return recentIssueHashes.count == 2 && recentIssueHashes[0] == recentIssueHashes[1]
    }

    // MARK: - Snapshot restore

    func restore(snapshot: ConvergenceSnapshot) {
        guard let idx = snapshots.firstIndex(where: { $0.id == snapshot.id }) else { return }
        snapshots = Array(snapshots.prefix(idx + 1))
        currentFileContent = snapshot.fileContent
        lastCritique = snapshot.critique
        iteration = snapshot.iteration
        phase = .idle
        recentIssueHashes = []
    }
}
