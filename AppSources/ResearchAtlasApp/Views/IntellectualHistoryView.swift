import ResearchAtlasCore
import SwiftUI

struct IntellectualHistoryView: View {
    @EnvironmentObject private var model: AppModel
    @State private var entityFilter = "All"

    private var entityTypes: [String] { ["All"] + Array(Set(model.historyEvents.map(\.entityType))).sorted() }
    private var events: [HistoryEvent] {
        entityFilter == "All" ? model.historyEvents : model.historyEvents.filter { $0.entityType == entityFilter }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Recorded intellectual history").font(.title2.weight(.semibold))
                    Text("Only application-observed events are shown; Research Atlas does not reconstruct unrecorded past states.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Picker("Record type", selection: $entityFilter) {
                    ForEach(entityTypes, id: \.self) { Text($0 == "All" ? "All records" : $0.replacingOccurrences(of: "_", with: " ").capitalized).tag($0) }
                }
                .frame(width: 220)
            }
            .padding(14).background(.bar)
            List(events) { event in
                HStack(alignment: .top, spacing: 14) {
                    VStack(spacing: 3) {
                        Circle().fill(tint(event.entityType)).frame(width: 10, height: 10)
                        Rectangle().fill(Color.secondary.opacity(0.25)).frame(width: 1, height: 54)
                    }
                    VStack(alignment: .leading, spacing: 5) {
                        HStack {
                            Text(event.title).font(.headline)
                            Spacer()
                            Text(event.recordedAt.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(.secondary)
                        }
                        Text("\(event.entityType.replacingOccurrences(of: "_", with: " ").capitalized) · \(event.eventType.capitalized)")
                            .font(.caption.weight(.medium)).foregroundStyle(tint(event.entityType))
                        if !event.detail.isEmpty { Text(event.detail).foregroundStyle(.secondary).textSelection(.enabled) }
                        if canNavigate(event) {
                            Button("Open Record", systemImage: "arrow.right.circle") { navigate(event) }.buttonStyle(.link)
                        }
                    }
                    .padding(.bottom, 8)
                }
            }
            .overlay {
                if events.isEmpty {
                    ContentUnavailableView(
                        "No recorded history",
                        systemImage: "clock.arrow.circlepath",
                        description: Text("Creating or revising questions, arguments, claims, ideas, evidence, and reviewed relationships will add dated events here.")
                    )
                }
            }
        }
    }

    private func tint(_ entityType: String) -> Color {
        switch entityType {
        case "question": .orange
        case "argument": .purple
        case "claim", "evidence": .indigo
        case "idea": .yellow
        case "contradiction": .red
        default: .secondary
        }
    }

    private func canNavigate(_ event: HistoryEvent) -> Bool {
        switch event.entityType {
        case "question", "argument", "claim", "idea", "contradiction": true
        default: false
        }
    }

    private func navigate(_ event: HistoryEvent) {
        model.openRecord(entityType: event.entityType, entityID: event.entityID)
    }
}
