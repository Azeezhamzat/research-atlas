import ResearchAtlasCore
import SwiftUI

struct KnowledgeAtlasView: View {
    @EnvironmentObject private var model: AppModel
    @State private var showingConceptSheet = false
    @State private var showingRelationshipSheet = false
    @State private var conceptPendingDeletion: ResearchConcept?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Picker("Presentation", selection: $model.knowledgeAtlasPresentation) {
                    Label("Visual Map", systemImage: "point.3.connected.trianglepath.dotted").tag(0)
                    Label("Records", systemImage: "list.bullet.rectangle").tag(1)
                }
                .pickerStyle(.segmented)
                .frame(width: 300)
                Spacer()
                Button("New Concept", systemImage: "plus") { showingConceptSheet = true }
                Button("New Relationship", systemImage: "link.badge.plus") { showingRelationshipSheet = true }
            }
            .padding(12)
            Divider()
            if model.knowledgeAtlasPresentation == 0 {
                KnowledgeGraphMapView(onCreateRelationship: { showingRelationshipSheet = true })
            } else {
                recordsView
            }
        }
        .sheet(isPresented: $showingConceptSheet) { NewConceptSheet() }
        .sheet(isPresented: $showingRelationshipSheet) { NewKnowledgeRelationshipSheet() }
        .confirmationDialog(
            "Delete this concept and its relationships?",
            isPresented: Binding(get: { conceptPendingDeletion != nil }, set: { if !$0 { conceptPendingDeletion = nil } }),
            titleVisibility: .visible
        ) {
            Button("Delete Concept", role: .destructive) {
                if let conceptPendingDeletion { model.deleteConcept(conceptPendingDeletion) }
                conceptPendingDeletion = nil
            }
            Button("Cancel", role: .cancel) { conceptPendingDeletion = nil }
        }
    }

    private var recordsView: some View {
        HSplitView {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("Concepts").font(.title2.weight(.semibold))
                    Spacer()
                }
                .padding(14)
                Divider()
                List(model.concepts) { concept in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(concept.name).font(.headline)
                            Spacer()
                            Text(concept.verification.rawValue).font(.caption).foregroundStyle(.secondary)
                        }
                        Text(concept.definition.isEmpty ? "No recorded definition" : concept.definition)
                            .font(.callout).foregroundStyle(.secondary).lineLimit(4)
                    }
                    .padding(.vertical, 5)
                    .contextMenu {
                        Button("Delete Concept", systemImage: "trash", role: .destructive) { conceptPendingDeletion = concept }
                    }
                }
                .overlay {
                    if model.concepts.isEmpty {
                        ContentUnavailableView("No concepts", systemImage: "circle.hexagongrid", description: Text("Create a carefully defined concept, then connect it to papers, questions, or arguments."))
                    }
                }
            }
            .frame(minWidth: 300, idealWidth: 360)

            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Evidence-bearing relationships").font(.title2.weight(.semibold))
                        Text("Manual and imported records remain distinct from any future AI suggestions.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(14)
                Divider()
                List(model.knowledgeRelationships) { relationship in
                    RelationshipCard(relationship: relationship)
                }
                .overlay {
                    if model.knowledgeRelationships.isEmpty {
                        ContentUnavailableView(
                            "No knowledge relationships",
                            systemImage: "point.3.connected.trianglepath.dotted",
                            description: Text("Add a typed relationship with source evidence or an explicit rationale.")
                        )
                    }
                }
            }
            .frame(minWidth: 540)
        }
    }
}

private struct RelationshipCard: View {
    @EnvironmentObject private var model: AppModel
    let relationship: KnowledgeRelationship
    @State private var showingDeleteConfirmation = false

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .firstTextBaseline) {
                Text(model.nodeLabel(type: relationship.sourceType, id: relationship.sourceID)).font(.headline)
                Image(systemName: "arrow.right").foregroundStyle(.secondary)
                Text(relationship.relationship.rawValue).font(.subheadline.weight(.semibold)).foregroundStyle(.indigo)
                Image(systemName: "arrow.right").foregroundStyle(.secondary)
                Text(model.nodeLabel(type: relationship.targetType, id: relationship.targetID)).font(.headline)
                Spacer()
            }
            HStack(spacing: 12) {
                Label(relationship.sourceType.rawValue, systemImage: "circle.fill").font(.caption)
                Label(relationship.targetType.rawValue, systemImage: "circle").font(.caption)
                Text(relationship.verification.rawValue).font(.caption.weight(.medium))
                Text(relationship.origin.rawValue).font(.caption).foregroundStyle(.secondary)
            }
            if !relationship.notes.isEmpty { Text(relationship.notes).textSelection(.enabled) }
            HStack {
                if let evidenceID = relationship.evidenceRelationshipID,
                   let evidence = model.evidenceRecords.first(where: { $0.id == evidenceID }) {
                    Button("Open linked evidence", systemImage: "checkmark.shield") { model.openEvidenceInReadingDesk(evidence) }
                        .controlSize(.small)
                } else if let passageID = relationship.sourcePassageID,
                          let passage = model.retrievedPassages.first(where: { $0.sourcePassageID == passageID }) {
                    Button("Open source passage", systemImage: "doc.text.magnifyingglass") { model.openRetrievedPassage(passage) }
                        .controlSize(.small)
                } else {
                    Label("Rationale only", systemImage: "text.bubble").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Delete", systemImage: "trash", role: .destructive) { showingDeleteConfirmation = true }
                    .controlSize(.small)
            }
        }
        .padding(.vertical, 8)
        .confirmationDialog("Delete this relationship?", isPresented: $showingDeleteConfirmation) {
            Button("Delete Relationship", role: .destructive) { model.deleteKnowledgeRelationship(relationship) }
            Button("Cancel", role: .cancel) {}
        }
    }
}

private struct NewConceptSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var definition = ""
    @State private var notes = ""
    @State private var verification: VerificationState = .unverified

    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            Text("New Research Concept").font(.title2.weight(.semibold))
            TextField("Concept name", text: $name)
            TextField("Definition — preserve the source's terminology where applicable", text: $definition, axis: .vertical).lineLimit(3...7)
            TextField("Notes, boundaries, or competing definitions", text: $notes, axis: .vertical).lineLimit(3...7)
            Picker("Verification", selection: $verification) {
                ForEach(VerificationState.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Create") { model.saveConcept(name: name, definition: definition, notes: notes, verification: verification); dismiss() }
                    .buttonStyle(.borderedProminent)
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 640)
    }
}

private struct NewKnowledgeRelationshipSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var sourceType: KnowledgeNodeType = .paper
    @State private var sourceID = ""
    @State private var targetType: KnowledgeNodeType = .concept
    @State private var targetID = ""
    @State private var relationshipType: KnowledgeRelationshipType = .relatesTo
    @State private var evidenceID = ""
    @State private var passageID = ""
    @State private var verification: VerificationState = .unverified
    @State private var notes = ""

    private var evidenceOptions: [EvidenceRelationship] { model.evidenceRecords }
    private var passageOptions: [RetrievedPassage] {
        var seen = Set<String>()
        return model.retrievedPassages.filter { seen.insert($0.sourcePassageID).inserted }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("New Knowledge Relationship").font(.title2.weight(.semibold))
            Text("A relationship must retain linked evidence, an indexed source passage, or your explicit rationale.")
                .font(.callout).foregroundStyle(.secondary)
            HStack {
                nodePicker(title: "From", type: $sourceType, id: $sourceID)
                nodePicker(title: "To", type: $targetType, id: $targetID)
            }
            Picker("Relationship", selection: $relationshipType) {
                ForEach(KnowledgeRelationshipType.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            Picker("Linked argument evidence", selection: $evidenceID) {
                Text("None").tag("")
                ForEach(evidenceOptions) { evidence in
                    Text(evidenceLabel(evidence)).tag(evidence.id.uuidString)
                }
            }
            Picker("Linked retrieved passage", selection: $passageID) {
                Text("None").tag("")
                ForEach(passageOptions) { passage in
                    Text(passageLabel(passage)).tag(passage.sourcePassageID)
                }
            }
            Picker("Verification", selection: $verification) {
                ForEach(VerificationState.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            TextField("Rationale, boundary condition, or qualification", text: $notes, axis: .vertical).lineLimit(3...6)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Create Relationship") {
                    model.saveKnowledgeRelationship(KnowledgeRelationship(
                        sourceType: sourceType, sourceID: sourceID,
                        targetType: targetType, targetID: targetID,
                        relationship: relationshipType,
                        evidenceRelationshipID: UUID(uuidString: evidenceID),
                        sourcePassageID: passageID.isEmpty ? nil : passageID,
                        verification: verification,
                        notes: notes
                    ))
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(sourceID.isEmpty || targetID.isEmpty || (evidenceID.isEmpty && passageID.isEmpty && notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty))
            }
        }
        .padding(24)
        .frame(width: 760)
        .onAppear { resetSource(); resetTarget() }
        .onChange(of: sourceType) { _, _ in resetSource() }
        .onChange(of: targetType) { _, _ in resetTarget() }
    }

    private func nodePicker(title: String, type: Binding<KnowledgeNodeType>, id: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            Picker("Type", selection: type) {
                ForEach(KnowledgeNodeType.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            Picker("Record", selection: id) {
                Text("Select…").tag("")
                ForEach(model.nodeOptions(for: type.wrappedValue), id: \.id) { option in
                    Text(option.label).tag(option.id)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func resetSource() { sourceID = model.nodeOptions(for: sourceType).first?.id ?? "" }
    private func resetTarget() { targetID = model.nodeOptions(for: targetType).first?.id ?? "" }

    private func evidenceLabel(_ evidence: EvidenceRelationship) -> String {
        let paper = model.literature.first { $0.id == evidence.literatureID }?.title ?? "Unavailable source"
        return "\(paper) — \(evidence.relation.rawValue)"
    }

    private func passageLabel(_ passage: RetrievedPassage) -> String {
        let paper = model.literature.first { $0.id == passage.literatureID }?.title ?? "Unavailable source"
        return "\(paper), p. \(passage.page)"
    }
}
