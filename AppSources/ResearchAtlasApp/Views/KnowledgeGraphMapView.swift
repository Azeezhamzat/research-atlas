import ResearchAtlasCore
import SwiftUI

private struct KnowledgeGraphNodeKey: Hashable {
    let type: KnowledgeNodeType
    let id: String
}

private struct KnowledgeGraphNode: Identifiable, Hashable {
    let key: KnowledgeGraphNodeKey
    let label: String
    var id: KnowledgeGraphNodeKey { key }
}

private enum KnowledgeGraphScope: String, CaseIterable, Identifiable {
    case connected = "Connected"
    case allRecords = "All records"

    var id: String { rawValue }
}

struct KnowledgeGraphMapView: View {
    @EnvironmentObject private var model: AppModel
    let onCreateRelationship: () -> Void

    @State private var relationshipFilter: KnowledgeRelationshipType?
    @State private var verificationFilter: VerificationState?
    @State private var originFilter: RecordOrigin?
    @State private var nodeTypeFilter: KnowledgeNodeType?
    @State private var scope: KnowledgeGraphScope = .connected
    @State private var searchText = ""
    @State private var selectedNodeKey: KnowledgeGraphNodeKey?
    @State private var hoveredNodeKey: KnowledgeGraphNodeKey?
    @State private var focusOnSelection = false
    @State private var showLabels = true
    @State private var scale = 1.0
    @State private var pan = CGSize.zero
    @GestureState private var liveMagnification = 1.0
    @GestureState private var liveDrag = CGSize.zero

    private let nodeLimit = 240

    private var allNodes: [KnowledgeGraphNode] {
        var nodes: [KnowledgeGraphNodeKey: KnowledgeGraphNode] = [:]
        for type in KnowledgeNodeType.allCases {
            for option in model.nodeOptions(for: type) {
                let key = KnowledgeGraphNodeKey(type: type, id: option.id)
                nodes[key] = KnowledgeGraphNode(key: key, label: option.label)
            }
        }
        for relationship in model.knowledgeRelationships {
            let source = KnowledgeGraphNodeKey(type: relationship.sourceType, id: relationship.sourceID)
            let target = KnowledgeGraphNodeKey(type: relationship.targetType, id: relationship.targetID)
            if nodes[source] == nil {
                nodes[source] = KnowledgeGraphNode(key: source, label: model.nodeLabel(type: source.type, id: source.id))
            }
            if nodes[target] == nil {
                nodes[target] = KnowledgeGraphNode(key: target, label: model.nodeLabel(type: target.type, id: target.id))
            }
        }
        return nodes.values.sorted(by: nodeSort)
    }

    private var baseRelationships: [KnowledgeRelationship] {
        model.knowledgeRelationships.filter { relationship in
            (relationshipFilter == nil || relationship.relationship == relationshipFilter) &&
            (verificationFilter == nil || relationship.verification == verificationFilter) &&
            (originFilter == nil || relationship.origin == originFilter) &&
            (nodeTypeFilter == nil || relationship.sourceType == nodeTypeFilter || relationship.targetType == nodeTypeFilter)
        }
    }

    private var searchedRelationships: [KnowledgeRelationship] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return baseRelationships }
        return baseRelationships.filter { relationship in
            model.nodeLabel(type: relationship.sourceType, id: relationship.sourceID).localizedCaseInsensitiveContains(query) ||
            model.nodeLabel(type: relationship.targetType, id: relationship.targetID).localizedCaseInsensitiveContains(query) ||
            relationship.relationship.rawValue.localizedCaseInsensitiveContains(query) ||
            relationship.notes.localizedCaseInsensitiveContains(query)
        }
    }

    private var filteredNodesAndRelationships: (nodes: [KnowledgeGraphNode], relationships: [KnowledgeRelationship]) {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        var relationships = searchedRelationships
        var keys = Set(relationships.flatMap {
            [KnowledgeGraphNodeKey(type: $0.sourceType, id: $0.sourceID),
             KnowledgeGraphNodeKey(type: $0.targetType, id: $0.targetID)]
        })

        let relationshipFiltersAreClear = relationshipFilter == nil && verificationFilter == nil && originFilter == nil
        if scope == .allRecords && relationshipFiltersAreClear {
            for node in allNodes where (nodeTypeFilter == nil || node.key.type == nodeTypeFilter) &&
                (query.isEmpty || node.label.localizedCaseInsensitiveContains(query)) {
                keys.insert(node.key)
            }
        } else if !query.isEmpty {
            // An isolated record should remain discoverable while Connected is active.
            for node in allNodes where (nodeTypeFilter == nil || node.key.type == nodeTypeFilter) &&
                node.label.localizedCaseInsensitiveContains(query) {
                keys.insert(node.key)
            }
        }

        if focusOnSelection, let selectedNodeKey {
            relationships = baseRelationships.filter {
                ($0.sourceType == selectedNodeKey.type && $0.sourceID == selectedNodeKey.id) ||
                ($0.targetType == selectedNodeKey.type && $0.targetID == selectedNodeKey.id)
            }
            keys = Set(relationships.flatMap {
                [KnowledgeGraphNodeKey(type: $0.sourceType, id: $0.sourceID),
                 KnowledgeGraphNodeKey(type: $0.targetType, id: $0.targetID)]
            })
            keys.insert(selectedNodeKey)
        }

        let degrees = degreeMap(for: relationships)
        let candidates = allNodes.filter { keys.contains($0.key) }.sorted {
            nodePrioritySort($0, $1, degrees: degrees)
        }
        let nodes = Array(candidates.prefix(nodeLimit))
        let visibleKeys = Set(nodes.map(\.key))
        relationships = relationships.filter {
            visibleKeys.contains(KnowledgeGraphNodeKey(type: $0.sourceType, id: $0.sourceID)) &&
            visibleKeys.contains(KnowledgeGraphNodeKey(type: $0.targetType, id: $0.targetID))
        }
        return (nodes, relationships)
    }

    private var visibleNodes: [KnowledgeGraphNode] { filteredNodesAndRelationships.nodes }
    private var visibleRelationships: [KnowledgeRelationship] { filteredNodesAndRelationships.relationships }
    private var selectedNode: KnowledgeGraphNode? { allNodes.first { $0.key == selectedNodeKey } }

    private var allConnectedKeys: Set<KnowledgeGraphNodeKey> {
        Set(model.knowledgeRelationships.flatMap {
            [KnowledgeGraphNodeKey(type: $0.sourceType, id: $0.sourceID),
             KnowledgeGraphNodeKey(type: $0.targetType, id: $0.targetID)]
        })
    }

    private var hasActiveFilters: Bool {
        nodeTypeFilter != nil || relationshipFilter != nil || verificationFilter != nil ||
        originFilter != nil || !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            filterBar
            Divider()
            HSplitView {
                graphSurface.frame(minWidth: 560)
                inspector.frame(minWidth: 300, idealWidth: 340, maxWidth: 400)
            }
        }
        .onChange(of: scope) { _, _ in
            if scope == .allRecords {
                focusOnSelection = false
            }
            resetViewport()
        }
        .onAppear { applyRequestedNodeSelection() }
        .onChange(of: model.requestedKnowledgeNodeID) { _, _ in applyRequestedNodeSelection() }
        .onChange(of: model.requestedKnowledgeNodeType) { _, _ in applyRequestedNodeSelection() }
    }

    private var filterBar: some View {
        VStack(spacing: 9) {
            HStack(spacing: 10) {
                TextField("Find a record, relationship, or note", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .frame(minWidth: 230)
                Picker("Scope", selection: $scope) {
                    ForEach(KnowledgeGraphScope.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .frame(width: 210)
                .help("Connected hides isolated records. All records groups every item by type.")
                Picker("Node type", selection: $nodeTypeFilter) {
                    Text("All node types").tag(nil as KnowledgeNodeType?)
                    ForEach(KnowledgeNodeType.allCases, id: \.self) { Text($0.rawValue).tag($0 as KnowledgeNodeType?) }
                }
                Picker("Relationship", selection: $relationshipFilter) {
                    Text("All relationships").tag(nil as KnowledgeRelationshipType?)
                    ForEach(KnowledgeRelationshipType.allCases, id: \.self) { Text($0.rawValue).tag($0 as KnowledgeRelationshipType?) }
                }
            }
            HStack(spacing: 12) {
                Picker("Verification", selection: $verificationFilter) {
                    Text("Any verification").tag(nil as VerificationState?)
                    ForEach(VerificationState.allCases, id: \.self) { Text($0.rawValue).tag($0 as VerificationState?) }
                }
                .frame(maxWidth: 230)
                Picker("Origin", selection: $originFilter) {
                    Text("Any origin").tag(nil as RecordOrigin?)
                    ForEach(RecordOrigin.allCases, id: \.self) { Text($0.rawValue).tag($0 as RecordOrigin?) }
                }
                .frame(maxWidth: 240)
                Toggle("Labels", isOn: $showLabels).toggleStyle(.switch).controlSize(.small)
                Text("\(visibleNodes.count) visible · \(visibleRelationships.count) relationships")
                    .font(.caption).foregroundStyle(.secondary)
                if scope == .connected && allNodes.count > allConnectedKeys.count && !hasActiveFilters {
                    Label("\(allNodes.count - allConnectedKeys.count) isolated records hidden", systemImage: "eye.slash")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if visibleNodes.count == nodeLimit {
                    Label("Node limit reached", systemImage: "line.3.horizontal.decrease.circle")
                        .font(.caption).foregroundStyle(.orange)
                }
                Spacer()
                if hasActiveFilters {
                    Button("Clear filters", systemImage: "xmark.circle", action: clearFilters).controlSize(.small)
                }
                Button("Neighborhood", systemImage: "scope") {
                    focusOnSelection = true
                    scope = .connected
                    resetViewport()
                }
                .controlSize(.small)
                .disabled(selectedNodeKey == nil)
                Button("Fit", systemImage: "arrow.up.left.and.arrow.down.right", action: resetViewport)
                    .controlSize(.small)
            }
        }
        .padding(11)
    }

    private func applyRequestedNodeSelection() {
        guard let type = model.requestedKnowledgeNodeType,
              let id = model.requestedKnowledgeNodeID,
              allNodes.contains(where: { $0.key.type == type && $0.key.id == id }) else { return }
        selectedNodeKey = KnowledgeGraphNodeKey(type: type, id: id)
        scope = .connected
        focusOnSelection = true
        searchText = ""
        resetViewport()
        // Consume the request so selecting the same record again later still retriggers focus.
        model.requestedKnowledgeNodeID = nil
        model.requestedKnowledgeNodeType = nil
    }

    private var graphSurface: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let graph = filteredNodesAndRelationships
            let nodes = graph.nodes
            let relationships = graph.relationships
            let degrees = degreeMap(for: relationships)
            let effectiveScale = clampedScale(scale * liveMagnification)
            let effectivePan = CGSize(width: pan.width + liveDrag.width, height: pan.height + liveDrag.height)
            ZStack {
                Canvas { context, canvasSize in
                    let positions = nodePositions(nodes: nodes, relationships: relationships, size: canvasSize)
                    if scope == .allRecords { drawTypeClusters(nodes: nodes, size: canvasSize, context: &context) }
                    for relationship in relationships {
                        let sourceKey = KnowledgeGraphNodeKey(type: relationship.sourceType, id: relationship.sourceID)
                        let targetKey = KnowledgeGraphNodeKey(type: relationship.targetType, id: relationship.targetID)
                        guard let source = positions[sourceKey], let target = positions[targetKey] else { continue }
                        let active = selectedNodeKey == nil || selectedNodeKey == sourceKey || selectedNodeKey == targetKey
                        drawEdge(
                            relationship,
                            from: transformed(source, in: canvasSize, scale: effectiveScale, pan: effectivePan),
                            to: transformed(target, in: canvasSize, scale: effectiveScale, pan: effectivePan),
                            context: &context,
                            emphasized: active,
                            showLabel: active && (relationships.count <= 18 || selectedNodeKey != nil)
                        )
                    }
                    for node in nodes {
                        guard let position = positions[node.key] else { continue }
                        let degree = degrees[node.key, default: 0]
                        let selected = node.key == selectedNodeKey
                        let hovered = node.key == hoveredNodeKey
                        let emphasized = isNodeEmphasized(node.key, relationships: relationships)
                        drawNode(
                            node,
                            at: transformed(position, in: canvasSize, scale: effectiveScale, pan: effectivePan),
                            degree: degree,
                            selected: selected,
                            hovered: hovered,
                            emphasized: emphasized,
                            showLabel: showLabels && shouldDrawLabel(
                                for: node, degree: degree, nodeCount: nodes.count,
                                selected: selected, hovered: hovered
                            ),
                            scale: effectiveScale,
                            context: &context
                        )
                    }
                }
                if nodes.isEmpty { emptyGraphView }
                VStack {
                    Spacer()
                    HStack(alignment: .bottom) {
                        legend
                        Spacer()
                        Text("Pinch to zoom · drag to pan · click a node · hover to reveal")
                            .font(.caption2).foregroundStyle(.secondary)
                            .padding(8).background(.regularMaterial, in: Capsule())
                    }
                    .padding(12)
                }
            }
            .background(Color(nsColor: .textBackgroundColor).opacity(0.42))
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                switch phase {
                case .active(let location):
                    hoveredNodeKey = hitTest(
                        location, nodes: nodes, relationships: relationships,
                        size: size, scale: effectiveScale, pan: effectivePan
                    )
                case .ended:
                    hoveredNodeKey = nil
                }
            }
            .gesture(
                SpatialTapGesture().onEnded { value in
                    selectedNodeKey = hitTest(
                        value.location, nodes: nodes, relationships: relationships,
                        size: size, scale: effectiveScale, pan: effectivePan
                    )
                    if selectedNodeKey == nil { focusOnSelection = false }
                }
            )
            .simultaneousGesture(
                DragGesture(minimumDistance: 3)
                    .updating($liveDrag) { value, state, _ in state = value.translation }
                    .onEnded { value in
                        pan.width += value.translation.width
                        pan.height += value.translation.height
                    }
            )
            .simultaneousGesture(
                MagnificationGesture()
                    .updating($liveMagnification) { value, state, _ in state = value }
                    .onEnded { value in scale = clampedScale(scale * value) }
            )
        }
    }

    private var emptyGraphView: some View {
        VStack(spacing: 12) {
            Image(systemName: "point.3.connected.trianglepath.dotted")
                .font(.system(size: 34)).foregroundStyle(.secondary)
            Text(scope == .connected ? "No connected records match" : "No records match")
                .font(.title3.weight(.semibold))
            Text(scope == .connected
                 ? "Create a typed relationship, switch to All records, or loosen the filters."
                 : "Create a concept or loosen the filters.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            HStack {
                if scope == .connected && !allNodes.isEmpty {
                    Button("Show all records") { scope = .allRecords }
                }
                Button("New Relationship", systemImage: "link.badge.plus", action: onCreateRelationship)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(28)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private var inspector: some View {
        ScrollView {
            if let node = selectedNode { selectedNodeInspector(node) } else { mapOverview }
        }
        .background(.bar)
    }

    private func selectedNodeInspector(_ node: KnowledgeGraphNode) -> some View {
        let relationships = inspectorRelationships(to: node.key)
        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                Circle().fill(nodeColor(node.key.type)).frame(width: 14, height: 14).padding(.top, 4)
                VStack(alignment: .leading, spacing: 4) {
                    Text(node.label).font(.title3.weight(.semibold)).textSelection(.enabled)
                    Text("\(node.key.type.rawValue) · \(relationships.count) connection\(relationships.count == 1 ? "" : "s")")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            HStack {
                if canOpen(node.key.type) {
                    Button("Open in \(workspaceName(node.key.type))", systemImage: "arrow.up.right.square") {
                        model.openKnowledgeNode(type: node.key.type, id: node.key.id)
                    }
                }
                Button(focusOnSelection ? "Showing neighborhood" : "Show neighborhood", systemImage: "scope") {
                    focusOnSelection = true
                    scope = .connected
                    resetViewport()
                }
                .disabled(focusOnSelection)
            }
            Divider()
            Text("Connected relationships").font(.headline)
            if relationships.isEmpty {
                Text("This record is currently isolated. Add a qualified relationship or inspect it in its source workspace.")
                    .foregroundStyle(.secondary)
                Button("New Relationship", systemImage: "link.badge.plus", action: onCreateRelationship)
            }
            ForEach(relationships) { relationship in
                inspectorRelationship(relationship, selected: node.key)
                Divider()
            }
            Button("Clear selection", systemImage: "xmark.circle") {
                selectedNodeKey = nil
                focusOnSelection = false
                resetViewport()
            }
            .controlSize(.small)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var mapOverview: some View {
        let connectedCount = allConnectedKeys.count
        let totalCount = allNodes.count
        let coverage = totalCount == 0 ? 0 : Double(connectedCount) / Double(totalCount)
        let verifiedCount = model.knowledgeRelationships.filter { $0.verification == .verified }.count
        return VStack(alignment: .leading, spacing: 16) {
            Label("Map overview", systemImage: "point.3.connected.trianglepath.dotted")
                .font(.title3.weight(.semibold))
            Text("The Atlas opens as a connected evidence map. Isolated records stay available in All records without overwhelming the relationships you are trying to inspect.")
                .font(.callout).foregroundStyle(.secondary)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                metricCard(value: "\(totalCount)", label: "Records", color: .blue)
                metricCard(value: "\(model.knowledgeRelationships.count)", label: "Relationships", color: .indigo)
                metricCard(value: "\(connectedCount)", label: "Connected", color: .teal)
                metricCard(value: "\(verifiedCount)", label: "Verified links", color: .green)
            }
            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    Text("Connection coverage").font(.subheadline.weight(.semibold))
                    Spacer()
                    Text(coverage.formatted(.percent.precision(.fractionLength(0))))
                        .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }
                ProgressView(value: coverage)
                if totalCount > connectedCount {
                    Text("\(totalCount - connectedCount) records are not yet part of a typed relationship.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Divider()
            Text("Work with the map").font(.headline)
            Label("Select a node to inspect every typed connection and its provenance.", systemImage: "cursorarrow.click.2")
            Label("Use Neighborhood to isolate one record and its immediate evidence context.", systemImage: "scope")
            Label("Use All records to find isolated material and connect it deliberately.", systemImage: "square.grid.3x3")
            HStack {
                Button("New Relationship", systemImage: "link.badge.plus", action: onCreateRelationship)
                    .buttonStyle(.borderedProminent)
                Button("Show all records") {
                    scope = .allRecords
                    resetViewport()
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func metricCard(value: String, label: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value).font(.title2.weight(.semibold)).monospacedDigit()
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 9))
    }

    private var legend: some View {
        HStack(spacing: 9) {
            ForEach(KnowledgeNodeType.allCases, id: \.self) { type in
                HStack(spacing: 4) {
                    Circle().fill(nodeColor(type)).frame(width: 7, height: 7)
                    Text(type.rawValue).font(.caption2)
                }
            }
        }
        .padding(8)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private func inspectorRelationship(_ relationship: KnowledgeRelationship, selected: KnowledgeGraphNodeKey) -> some View {
        let selectedIsSource = relationship.sourceType == selected.type && relationship.sourceID == selected.id
        let otherType = selectedIsSource ? relationship.targetType : relationship.sourceType
        let otherID = selectedIsSource ? relationship.targetID : relationship.sourceID
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(relationship.relationship.rawValue)
                    .font(.subheadline.weight(.semibold)).foregroundStyle(edgeColor(relationship.relationship))
                Spacer()
                Text(relationship.verification.rawValue)
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 7).padding(.vertical, 3)
                    .background(.quaternary, in: Capsule())
            }
            HStack(alignment: .top) {
                Image(systemName: selectedIsSource ? "arrow.right" : "arrow.left").foregroundStyle(.secondary)
                Button(model.nodeLabel(type: otherType, id: otherID)) {
                    selectedNodeKey = KnowledgeGraphNodeKey(type: otherType, id: otherID)
                }
                .buttonStyle(.link)
            }
            Text(relationship.origin.rawValue).font(.caption).foregroundStyle(.secondary)
            if !relationship.notes.isEmpty { Text(relationship.notes).font(.callout).textSelection(.enabled) }
            if let evidenceID = relationship.evidenceRelationshipID,
               let evidence = model.evidenceRecords.first(where: { $0.id == evidenceID }) {
                Button("Open linked evidence", systemImage: "checkmark.shield") {
                    model.openEvidenceInReadingDesk(evidence)
                }
                .controlSize(.small)
            } else if let passageID = relationship.sourcePassageID,
                      let passage = model.retrievedPassages.first(where: { $0.sourcePassageID == passageID }) {
                Button("Open source passage", systemImage: "doc.text.magnifyingglass") {
                    model.openRetrievedPassage(passage)
                }
                .controlSize(.small)
            } else {
                Label("Rationale-only relationship", systemImage: "text.bubble")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func nodePositions(
        nodes: [KnowledgeGraphNode], relationships: [KnowledgeRelationship], size: CGSize
    ) -> [KnowledgeGraphNodeKey: CGPoint] {
        guard !nodes.isEmpty else { return [:] }
        if scope == .allRecords {
            return typeClusterPositions(nodes: nodes, relationships: relationships, size: size)
        }
        return componentPositions(nodes: nodes, relationships: relationships, size: size)
    }

    private func typeClusterFrames(nodes: [KnowledgeGraphNode], size: CGSize) -> [KnowledgeNodeType: CGRect] {
        let populatedTypes = KnowledgeNodeType.allCases.filter { type in nodes.contains { $0.key.type == type } }
        guard !populatedTypes.isEmpty else { return [:] }
        let available = CGRect(x: 18, y: 18, width: max(1, size.width - 36), height: max(1, size.height - 88))
        let columns = min(populatedTypes.count, size.width > 920 ? 3 : 2)
        let rows = Int(ceil(Double(populatedTypes.count) / Double(columns)))
        let gap = 12.0
        let cellWidth = (available.width - gap * Double(columns - 1)) / Double(columns)
        let cellHeight = (available.height - gap * Double(rows - 1)) / Double(rows)
        var result: [KnowledgeNodeType: CGRect] = [:]
        for (index, type) in populatedTypes.enumerated() {
            let column = index % columns
            let row = index / columns
            result[type] = CGRect(
                x: available.minX + Double(column) * (cellWidth + gap),
                y: available.minY + Double(row) * (cellHeight + gap),
                width: cellWidth,
                height: cellHeight
            )
        }
        return result
    }

    private func typeClusterPositions(
        nodes: [KnowledgeGraphNode], relationships: [KnowledgeRelationship], size: CGSize
    ) -> [KnowledgeGraphNodeKey: CGPoint] {
        let frames = typeClusterFrames(nodes: nodes, size: size)
        let degrees = degreeMap(for: relationships)
        var result: [KnowledgeGraphNodeKey: CGPoint] = [:]
        for type in KnowledgeNodeType.allCases {
            guard let frame = frames[type] else { continue }
            let group = nodes.filter { $0.key.type == type }.sorted {
                nodePrioritySort($0, $1, degrees: degrees)
            }
            guard !group.isEmpty else { continue }
            let content = frame.insetBy(dx: 16, dy: 16)
            let top = content.minY + 24
            let usableHeight = max(24, content.maxY - top)
            let aspect = max(0.35, content.width / usableHeight)
            let columns = max(1, Int(ceil(sqrt(Double(group.count) * aspect))))
            let rows = max(1, Int(ceil(Double(group.count) / Double(columns))))
            let xStep = content.width / Double(columns)
            let yStep = usableHeight / Double(rows)
            for (index, node) in group.enumerated() {
                let column = index % columns
                let row = index / columns
                result[node.key] = CGPoint(
                    x: content.minX + (Double(column) + 0.5) * xStep,
                    y: top + (Double(row) + 0.5) * yStep
                )
            }
        }
        return result
    }

    private func componentPositions(
        nodes: [KnowledgeGraphNode], relationships: [KnowledgeRelationship], size: CGSize
    ) -> [KnowledgeGraphNodeKey: CGPoint] {
        let visibleKeys = Set(nodes.map(\.key))
        var adjacency: [KnowledgeGraphNodeKey: Set<KnowledgeGraphNodeKey>] = [:]
        for key in visibleKeys { adjacency[key] = [] }
        for relationship in relationships {
            let source = KnowledgeGraphNodeKey(type: relationship.sourceType, id: relationship.sourceID)
            let target = KnowledgeGraphNodeKey(type: relationship.targetType, id: relationship.targetID)
            guard visibleKeys.contains(source), visibleKeys.contains(target) else { continue }
            adjacency[source, default: []].insert(target)
            adjacency[target, default: []].insert(source)
        }

        var unseen = visibleKeys
        var components: [[KnowledgeGraphNodeKey]] = []
        while let start = unseen.first {
            var queue = [start]
            var component: [KnowledgeGraphNodeKey] = []
            unseen.remove(start)
            while !queue.isEmpty {
                let current = queue.removeFirst()
                component.append(current)
                for neighbor in adjacency[current, default: []] where unseen.contains(neighbor) {
                    unseen.remove(neighbor)
                    queue.append(neighbor)
                }
            }
            components.append(component)
        }
        components.sort {
            if $0.count != $1.count { return $0.count > $1.count }
            return ($0.first?.id ?? "") < ($1.first?.id ?? "")
        }

        let available = CGRect(x: 30, y: 30, width: max(1, size.width - 60), height: max(1, size.height - 100))
        let aspect = max(0.6, available.width / max(1, available.height))
        let columns = max(1, min(components.count, Int(ceil(sqrt(Double(components.count) * aspect)))))
        let rows = max(1, Int(ceil(Double(components.count) / Double(columns))))
        let cellWidth = available.width / Double(columns)
        let cellHeight = available.height / Double(rows)
        var result: [KnowledgeGraphNodeKey: CGPoint] = [:]

        for (componentIndex, component) in components.enumerated() {
            let column = componentIndex % columns
            let row = componentIndex / columns
            let center = CGPoint(
                x: available.minX + (Double(column) + 0.5) * cellWidth,
                y: available.minY + (Double(row) + 0.5) * cellHeight
            )
            guard component.count > 1 else {
                result[component[0]] = center
                continue
            }
            let hub = component.max {
                adjacency[$0, default: []].count < adjacency[$1, default: []].count
            } ?? component[0]
            var distances: [KnowledgeGraphNodeKey: Int] = [hub: 0]
            var queue = [hub]
            while !queue.isEmpty {
                let current = queue.removeFirst()
                for neighbor in adjacency[current, default: []] where distances[neighbor] == nil {
                    distances[neighbor] = distances[current, default: 0] + 1
                    queue.append(neighbor)
                }
            }
            let maximumLevel = max(1, distances.values.max() ?? 1)
            let maximumRadius = max(54, min(cellWidth, cellHeight) * 0.38)
            for level in 0...maximumLevel {
                let levelNodes = component.filter { distances[$0, default: maximumLevel] == level }.sorted {
                    if $0.type.rawValue != $1.type.rawValue { return $0.type.rawValue < $1.type.rawValue }
                    return $0.id < $1.id
                }
                if level == 0 {
                    result[hub] = center
                    continue
                }
                let radius = maximumRadius * Double(level) / Double(maximumLevel)
                for (index, key) in levelNodes.enumerated() {
                    let angle = -Double.pi / 2 + 2 * Double.pi * Double(index) / Double(max(1, levelNodes.count))
                    result[key] = CGPoint(x: center.x + cos(angle) * radius, y: center.y + sin(angle) * radius)
                }
            }
        }
        return result
    }

    private func drawTypeClusters(nodes: [KnowledgeGraphNode], size: CGSize, context: inout GraphicsContext) {
        let frames = typeClusterFrames(nodes: nodes, size: size)
        for type in KnowledgeNodeType.allCases {
            guard let frame = frames[type] else { continue }
            let count = nodes.filter { $0.key.type == type }.count
            let path = Path(roundedRect: frame, cornerRadius: 12)
            context.fill(path, with: .color(nodeColor(type).opacity(0.035)))
            context.stroke(path, with: .color(nodeColor(type).opacity(0.24)), lineWidth: 1)
            let heading = context.resolve(
                Text("\(type.rawValue) · \(count)")
                    .font(.caption.weight(.semibold)).foregroundStyle(nodeColor(type))
            )
            context.draw(heading, at: CGPoint(x: frame.minX + 12, y: frame.minY + 9), anchor: .topLeading)
        }
    }

    private func transformed(_ point: CGPoint, in size: CGSize, scale: Double, pan: CGSize) -> CGPoint {
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        return CGPoint(
            x: center.x + (point.x - center.x) * scale + pan.width,
            y: center.y + (point.y - center.y) * scale + pan.height
        )
    }

    private func hitTest(
        _ location: CGPoint,
        nodes: [KnowledgeGraphNode],
        relationships: [KnowledgeRelationship],
        size: CGSize,
        scale: Double,
        pan: CGSize
    ) -> KnowledgeGraphNodeKey? {
        let positions = nodePositions(nodes: nodes, relationships: relationships, size: size)
        let degrees = degreeMap(for: relationships)
        return nodes.reversed().first { node in
            guard let point = positions[node.key] else { return false }
            let screen = transformed(point, in: size, scale: scale, pan: pan)
            let radius = nodeRadius(degree: degrees[node.key, default: 0], selected: false)
            return hypot(location.x - screen.x, location.y - screen.y) <= max(15, radius * scale + 4)
        }?.key
    }

    private func drawNode(
        _ node: KnowledgeGraphNode,
        at point: CGPoint,
        degree: Int,
        selected: Bool,
        hovered: Bool,
        emphasized: Bool,
        showLabel: Bool,
        scale: Double,
        context: inout GraphicsContext
    ) {
        let radius = nodeRadius(degree: degree, selected: selected || hovered)
        let circle = Path(ellipseIn: CGRect(
            x: point.x - radius, y: point.y - radius,
            width: radius * 2, height: radius * 2
        ))
        let opacity = emphasized ? 1.0 : 0.22
        context.fill(circle, with: .color(nodeColor(node.key.type).opacity(opacity)))
        context.stroke(
            circle,
            with: .color((selected ? Color.primary : Color.white).opacity(emphasized ? 0.82 : 0.25)),
            lineWidth: selected ? 3 : (hovered ? 2 : 1)
        )
        guard showLabel && (scale >= 0.58 || selected || hovered) else { return }
        let shortened = node.label.count > 42 ? String(node.label.prefix(41)) + "…" : node.label
        let label = context.resolve(
            Text(shortened)
                .font((selected || hovered) ? .caption.weight(.semibold) : .caption2)
                .foregroundStyle(emphasized ? Color.primary : Color.secondary)
        )
        context.draw(label, at: CGPoint(x: point.x, y: point.y + radius + 7), anchor: .top)
    }

    private func drawEdge(
        _ relationship: KnowledgeRelationship,
        from source: CGPoint,
        to target: CGPoint,
        context: inout GraphicsContext,
        emphasized: Bool,
        showLabel: Bool
    ) {
        let dx = target.x - source.x
        let dy = target.y - source.y
        let length = max(1, hypot(dx, dy))
        let ux = dx / length
        let uy = dy / length
        let end = CGPoint(x: target.x - ux * 16, y: target.y - uy * 16)
        var line = Path()
        line.move(to: source)
        line.addLine(to: end)
        let color = edgeColor(relationship.relationship)
        let opacity = emphasized ? (relationship.verification == .verified ? 0.92 : 0.68) : 0.13
        context.stroke(
            line,
            with: .color(color.opacity(opacity)),
            style: StrokeStyle(
                lineWidth: emphasized && relationship.verification == .verified ? 2.2 : 1.25,
                dash: relationship.verification == .unverified ? [5, 4] : []
            )
        )
        let wing = 7.0
        let left = CGPoint(x: end.x - ux * wing - uy * wing * 0.65, y: end.y - uy * wing + ux * wing * 0.65)
        let right = CGPoint(x: end.x - ux * wing + uy * wing * 0.65, y: end.y - uy * wing - ux * wing * 0.65)
        var arrow = Path()
        arrow.move(to: end); arrow.addLine(to: left)
        arrow.move(to: end); arrow.addLine(to: right)
        context.stroke(arrow, with: .color(color.opacity(opacity)), lineWidth: 1.4)
        if showLabel {
            let midpoint = CGPoint(x: (source.x + target.x) / 2, y: (source.y + target.y) / 2)
            let label = context.resolve(
                Text(relationship.relationship.rawValue)
                    .font(.system(size: 9, weight: .medium)).foregroundStyle(color)
            )
            context.draw(label, at: midpoint, anchor: .bottom)
        }
    }

    private func degreeMap(for relationships: [KnowledgeRelationship]) -> [KnowledgeGraphNodeKey: Int] {
        var result: [KnowledgeGraphNodeKey: Int] = [:]
        for relationship in relationships {
            result[KnowledgeGraphNodeKey(type: relationship.sourceType, id: relationship.sourceID), default: 0] += 1
            result[KnowledgeGraphNodeKey(type: relationship.targetType, id: relationship.targetID), default: 0] += 1
        }
        return result
    }

    private func nodeRadius(degree: Int, selected: Bool) -> Double {
        min(selected ? 19 : 16, (selected ? 11 : 7) + sqrt(Double(max(0, degree))) * 3.0)
    }

    private func shouldDrawLabel(
        for node: KnowledgeGraphNode,
        degree: Int,
        nodeCount: Int,
        selected: Bool,
        hovered: Bool
    ) -> Bool {
        if selected || hovered { return true }
        if !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return true }
        if scope == .connected { return nodeCount <= 44 || degree >= 2 }
        return nodeCount <= 28 || degree > 0
    }

    private func isNodeEmphasized(
        _ key: KnowledgeGraphNodeKey,
        relationships: [KnowledgeRelationship]
    ) -> Bool {
        guard let selectedNodeKey else { return true }
        if key == selectedNodeKey { return true }
        return relationships.contains {
            let source = KnowledgeGraphNodeKey(type: $0.sourceType, id: $0.sourceID)
            let target = KnowledgeGraphNodeKey(type: $0.targetType, id: $0.targetID)
            return (source == selectedNodeKey && target == key) || (target == selectedNodeKey && source == key)
        }
    }

    private func inspectorRelationships(to key: KnowledgeGraphNodeKey) -> [KnowledgeRelationship] {
        baseRelationships.filter {
            ($0.sourceType == key.type && $0.sourceID == key.id) ||
            ($0.targetType == key.type && $0.targetID == key.id)
        }
        .sorted {
            if $0.verification != $1.verification { return $0.verification.rawValue < $1.verification.rawValue }
            return $0.relationship.rawValue < $1.relationship.rawValue
        }
    }

    private func nodePrioritySort(
        _ lhs: KnowledgeGraphNode,
        _ rhs: KnowledgeGraphNode,
        degrees: [KnowledgeGraphNodeKey: Int]
    ) -> Bool {
        let leftDegree = degrees[lhs.key, default: 0]
        let rightDegree = degrees[rhs.key, default: 0]
        if leftDegree != rightDegree { return leftDegree > rightDegree }
        return nodeSort(lhs, rhs)
    }

    private func nodeSort(_ lhs: KnowledgeGraphNode, _ rhs: KnowledgeGraphNode) -> Bool {
        if lhs.key.type.rawValue != rhs.key.type.rawValue { return lhs.key.type.rawValue < rhs.key.type.rawValue }
        if lhs.label != rhs.label { return lhs.label.localizedCaseInsensitiveCompare(rhs.label) == .orderedAscending }
        return lhs.key.id < rhs.key.id
    }

    private func clearFilters() {
        searchText = ""
        nodeTypeFilter = nil
        relationshipFilter = nil
        verificationFilter = nil
        originFilter = nil
        focusOnSelection = false
        resetViewport()
    }

    private func resetViewport() {
        scale = 1
        pan = .zero
    }

    private func clampedScale(_ value: Double) -> Double { min(3.4, max(0.45, value)) }
    private func canOpen(_ type: KnowledgeNodeType) -> Bool { type != .concept && type != .note }

    private func workspaceName(_ type: KnowledgeNodeType) -> String {
        switch type {
        case .paper: "Reading Desk"
        case .argument: "Argument Workspace"
        case .researchQuestion: "Research Questions"
        case .claim: "Evidence Explorer"
        case .idea: "Idea Laboratory"
        case .concept: "Knowledge Atlas"
        case .note: "Literature Library"
        }
    }

    private func nodeColor(_ type: KnowledgeNodeType) -> Color {
        switch type {
        case .paper: .blue
        case .concept: .teal
        case .argument: .orange
        case .researchQuestion: .purple
        case .note: .gray
        case .claim: .pink
        case .idea: .yellow
        }
    }

    private func edgeColor(_ type: KnowledgeRelationshipType) -> Color {
        switch type {
        case .supports, .extends: .green
        case .challenges, .contradicts, .alternative: .red
        case .qualifies, .dependsOn: .orange
        case .context, .relatedConstruct, .relatesTo: .blue
        case .investigates, .operationalises: .purple
        case .requiresInvestigation: .pink
        }
    }
}
