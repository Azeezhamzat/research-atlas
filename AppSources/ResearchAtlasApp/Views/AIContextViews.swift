import ResearchAtlasCore
import SwiftUI

struct AIProviderStatusPill: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: statusIcon)
            VStack(alignment: .leading, spacing: 1) {
                Text(model.aiProviderConfiguration.provider.displayName)
                    .font(.caption.weight(.semibold))
                Text(model.aiProviderStatusText)
                    .font(.caption2)
            }
        }
        .foregroundStyle(positiveStatus ? Color.green : Color.orange)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background((positiveStatus ? Color.green : Color.orange).opacity(0.09), in: Capsule())
        .help(providerHelp)
    }

    private var statusIcon: String {
        guard model.aiProviderConfiguration.provider != .disabled else { return "sparkles" }
        if model.aiProviderReadyForRequests {
            return model.aiProviderConfiguration.provider.isLocal ? "desktopcomputer" : "checkmark.shield.fill"
        }
        return "exclamationmark.triangle.fill"
    }

    private var providerHelp: String {
        guard model.aiProviderConfiguration.provider != .disabled else {
            return "Choose a hosted or local provider in Integrations. Core research workflows remain available without AI."
        }
        return "\(model.aiProviderConfiguration.model) · \(model.aiProviderConfiguration.provider.transportDescription)"
    }

    private var positiveStatus: Bool {
        guard model.aiProviderReadyForRequests else { return false }
        if model.aiProviderConfiguration.provider == .ollamaLocal,
           case .unavailable = model.ollamaRuntimeStatus { return false }
        return true
    }
}

struct GroundedAIContextCard: View {
    @EnvironmentObject private var model: AppModel
    let title: String
    let detail: String
    let suggestedQuery: String
    var retrievalSetID: UUID? = nil
    var argument: ResearchArgument? = nil
    var expectedLiteratureIDs: Set<UUID> = []

    private var resolvedSetID: UUID? {
        if let retrievalSetID, model.groundedSourceCount(for: retrievalSetID) > 0 { return retrievalSetID }
        return model.suggestedRetrievalSetID(matching: expectedLiteratureIDs)
    }

    private var resolvedSet: RetrievalSet? {
        resolvedSetID.flatMap { id in model.retrievalSets.first { $0.id == id } }
    }

    private var sourceCount: Int {
        resolvedSetID.map { model.groundedSourceCount(for: $0) } ?? 0
    }

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "sparkles.rectangle.stack.fill")
                        .font(.title2)
                        .foregroundStyle(.purple)
                        .frame(width: 30)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(title).font(.headline)
                        Text(detail).font(.callout).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 12)
                    AIProviderStatusPill()
                }

                if let resolvedSet {
                    Label(
                        "Evidence set: \(resolvedSet.name) · \(sourceCount) current source snapshot\(sourceCount == 1 ? "" : "s")",
                        systemImage: "checkmark.shield"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    if !expectedLiteratureIDs.isEmpty {
                        GroundingFitSummary(
                            retrievalSetID: resolvedSet.id,
                            expectedLiteratureIDs: expectedLiteratureIDs
                        )
                    }
                } else {
                    Label(
                        "Create a retrieval set first so the model receives inspectable source snapshots rather than the whole library.",
                        systemImage: "text.magnifyingglass"
                    )
                    .font(.caption)
                    .foregroundStyle(.orange)
                }

                HStack(spacing: 10) {
                    if let resolvedSetID {
                        Button("Open Grounded Assistant", systemImage: "sparkles") {
                            model.openResearchAssistant(
                                query: suggestedQuery,
                                retrievalSetID: resolvedSetID,
                                expectedLiteratureIDs: expectedLiteratureIDs
                            )
                        }
                        .buttonStyle(.borderedProminent)
                    } else {
                        Button("Build Evidence Set", systemImage: "text.magnifyingglass") {
                            model.evidenceExplorerMode = 0
                            model.selectedSection = .evidence
                        }
                        .buttonStyle(.borderedProminent)
                    }

                    if let argument {
                        Button("Critical Review", systemImage: "checkmark.shield") {
                            model.openBiasAuditor(for: argument)
                        }
                        Button("Argument Room", systemImage: "person.3.sequence") {
                            model.openArgumentRoom(for: argument)
                        }
                    }

                    if !model.aiProviderReadyForRequests {
                        Button("Finish AI Setup", systemImage: "gearshape") {
                            model.selectedSection = .settings
                        }
                    }

                    Menu("More AI Tools", systemImage: "ellipsis.circle") {
                        Button("Research Assistant", systemImage: "sparkles") { model.selectedSection = .assistant }
                        Button("Research Bias Auditor", systemImage: "checkmark.shield") { model.selectedSection = .bias }
                        Button("Argument Room", systemImage: "person.3.sequence") { model.selectedSection = .argumentRoom }
                        Button("Contradiction Detective", systemImage: "arrow.left.arrow.right") { model.selectedSection = .contradictions }
                        Button("Collective Intelligence Lab", systemImage: "brain.head.profile") { model.selectedSection = .collectiveLab }
                        Divider()
                        Button("AI Provider Settings", systemImage: "gearshape") { model.selectedSection = .settings }
                    }
                    Spacer()
                }

                Text("Nothing is sent automatically. Every model request shows the exact provider, model, task, source labels, and request size for approval. Model output remains a reviewable suggestion and never edits research records by itself.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
        }
    }
}

struct GroundingFitSummary: View {
    @EnvironmentObject private var model: AppModel
    let retrievalSetID: UUID?
    var expectedLiteratureIDs: Set<UUID> = []

    var body: some View {
        if !expectedLiteratureIDs.isEmpty, let retrievalSetID {
            let overlap = model.retrievalSetOverlap(retrievalSetID, with: expectedLiteratureIDs)
            if overlap > 0 {
                Label(
                    "This set includes current passages from \(overlap) of \(expectedLiteratureIDs.count) linked paper\(expectedLiteratureIDs.count == 1 ? "" : "s").",
                    systemImage: "checkmark.circle.fill"
                )
                .font(.caption)
                .foregroundStyle(.green)
            } else {
                Label(
                    "This set contains no current passages from the papers linked here. Choose or build a better-matched set before approving a request.",
                    systemImage: "exclamationmark.triangle.fill"
                )
                .font(.caption)
                .foregroundStyle(.orange)
            }
        }
    }
}
