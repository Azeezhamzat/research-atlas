import ResearchAtlasCore
import SwiftUI

struct AITransmissionPreviewSheet: View {
    @EnvironmentObject private var model: AppModel
    let preview: AITransmissionPreview
    @State private var consent = false
    @State private var showingExactSourceText = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                Image(systemName: preview.provider.isLocal ? "desktopcomputer" : "network.badge.shield.half.filled")
                    .font(.system(size: 30)).foregroundStyle(.purple)
                VStack(alignment: .leading, spacing: 3) {
                    Text(preview.provider.isLocal ? "Review Local Model Request" : "Review External Transmission")
                        .font(.title2.weight(.semibold))
                    Text("No content has been sent yet.").foregroundStyle(.secondary)
                }
            }
            Label(preview.analysisKind.rawValue, systemImage: "sparkles")
                .font(.headline).foregroundStyle(.purple)
            GroupBox("Destination") {
                Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 7) {
                    GridRow { Text("Provider").foregroundStyle(.secondary); Text(preview.provider.rawValue) }
                    GridRow { Text("Endpoint").foregroundStyle(.secondary); Text(preview.endpoint).textSelection(.enabled) }
                    GridRow { Text("Model").foregroundStyle(.secondary); Text(preview.model) }
                    if let reasoning = preview.reasoningEffort {
                        GridRow { Text("Reasoning").foregroundStyle(.secondary); Text(reasoning.displayName) }
                    }
                    GridRow { Text("Output limit").foregroundStyle(.secondary); Text("\(preview.maximumOutputTokens) tokens") }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            GroupBox("Research task") {
                Text(preview.query).frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled)
            }
            GroupBox("Source snapshots to send") {
                VStack(alignment: .leading, spacing: 7) {
                    ForEach(preview.sourceLabels, id: \.self) { Text($0) }
                    Divider()
                    Text("\(preview.passageCount) exact paper-passage and note-excerpt snapshots · \(preview.characterCount) total request characters")
                        .font(.caption.weight(.medium))
                    Button(showingExactSourceText ? "Hide Exact Source Text" : "Inspect Exact Source Text", systemImage: "text.magnifyingglass") {
                        showingExactSourceText.toggle()
                    }
                    .buttonStyle(.bordered)
                    if showingExactSourceText {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 14) {
                                ForEach(preview.sourcePreviews) { source in
                                    VStack(alignment: .leading, spacing: 5) {
                                        HStack(alignment: .firstTextBaseline) {
                                            Text("[\(source.label)]").font(.headline.monospaced())
                                            Text(source.title).font(.headline)
                                            Spacer()
                                            if let location = source.location { Text(location) }
                                        }
                                        Text(source.sourceClass)
                                            .font(.caption.weight(.medium))
                                            .foregroundStyle(source.label.hasPrefix("N") ? Color.indigo : Color.secondary)
                                        Text("“\(source.excerpt)”")
                                            .textSelection(.enabled)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                    .padding(10)
                                    .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
                                }
                            }
                        }
                        .frame(maxHeight: 260)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Text("The displayed task, its recorded application context, exact paper-passage text, separately labelled researcher-note excerpts, source titles/pages, and grounding instructions are included. Researcher notes are not described as published evidence. Your database, PDF files, Obsidian files, and credential are not uploaded as files.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Toggle(
                preview.provider.isLocal
                    ? "I approve sending these source snapshots and the displayed task context to \(preview.provider.displayName) on this Mac for this request"
                    : "I approve sending these source snapshots and the displayed task context to this provider for this request",
                isOn: $consent
            )
            HStack {
                Button("Cancel") { model.cancelAITransmission() }.keyboardShortcut(.cancelAction)
                Spacer()
                if model.isBusy { ProgressView().controlSize(.small) }
                Button("Send Approved Request") { model.confirmAITransmission(preview) }
                    .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
                    .disabled(!consent || model.isBusy)
            }
        }
        .padding(24)
        .frame(width: 700)
    }
}
