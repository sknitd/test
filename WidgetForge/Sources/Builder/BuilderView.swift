import SwiftUI
import AppKit

/// Entry point for the Widget Builder section.
struct BuilderHost: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        if let document = model.builderDocument {
            BuilderView(document: document, widgetID: model.builderWidgetID)
                .id(document.id + (model.builderWidgetID ?? ""))
        } else {
            ContentUnavailableView {
                Label("Widget Builder", systemImage: "hammer")
            } description: {
                Text("Design a widget by dragging components onto a canvas, binding them to live data and, if you like, scripting it.")
            } actions: {
                Button("New Widget") { model.newBuilderDocument() }.buttonStyle(.borderedProminent)
                Button("Start from a Template") { model.section = .templates }
            }
        }
    }
}

struct BuilderView: View {
    @EnvironmentObject private var app: AppModel
    @StateObject private var model: BuilderModel
    @State private var preview: WidgetRuntime?
    @State private var bottomTab = BottomTab.console
    let widgetID: String?

    enum BottomTab: String, CaseIterable { case console = "Console", script = "Script", data = "Data", settings = "Settings", json = "JSON" }

    init(document: WidgetDefinition, widgetID: String?) {
        _model = StateObject(wrappedValue: BuilderModel(document: document))
        self.widgetID = widgetID
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            HSplitView {
                BuilderPalette(model: model).frame(minWidth: 150, idealWidth: 170, maxWidth: 220)
                VSplitView {
                    BuilderCanvas(model: model, preview: preview)
                        .frame(minHeight: 260)
                    BuilderBottomPanel(model: model, tab: $bottomTab, preview: preview)
                        .frame(minHeight: 150, idealHeight: 210)
                }
                .frame(minWidth: 330)
                BuilderInspector(model: model, preview: preview).frame(minWidth: 250, idealWidth: 270, maxWidth: 340)
            }
        }
        .task(id: PreviewKey(document: model.document, on: model.isPreviewing, script: model.runScriptInPreview)) {
            // Debounced: rebuild the live preview shortly after the last edit.
            preview?.stop()
            guard model.isPreviewing else { preview = nil; return }
            try? await Task.sleep(nanoseconds: 350_000_000)
            if Task.isCancelled { return }
            startPreview()
        }
        .onDisappear { preview?.stop(); preview = nil }
    }

    private struct PreviewKey: Equatable {
        let document: WidgetDefinition
        let on: Bool
        let script: Bool
    }

    private func startPreview() {
        let definition = model.exportDefinition()
        // The author is previewing their own work, so the preview has what the content needs. Scripts still
        // need the explicit "Run script" switch.
        var granted = definition.permissions
        granted.scripting = model.runScriptInPreview
        var instance = WidgetInstance(definition: definition, placement: Placement(x: 0, y: 0, width: definition.size.width, height: definition.size.height, displayID: nil),
                                      granted: granted, origin: .builder, scriptTrusted: model.runScriptInPreview)
        if let widgetID, let existing = app.widgets.first(where: { $0.id == widgetID }) { instance.state = existing.state }
        let runtime = WidgetRuntime(instance: instance, services: app, persistsState: false)
        runtime.start()
        preview = runtime
        model.log("Preview started with \(WidgetContextBuilder.effectiveSources(for: definition).count) data source(s)")
    }

    private var toolbar: some View {
        HStack(spacing: 10) {
            TextField("Widget name", text: Binding(get: { model.document.name }, set: { name in model.mutate { $0.name = name } }))
                .textFieldStyle(.roundedBorder).frame(minWidth: 90, idealWidth: 160, maxWidth: 180)
            Button { model.undo() } label: { Image(systemName: "arrow.uturn.backward") }.disabled(!model.canUndo).help("Undo (⌘Z)")
            Button { model.redo() } label: { Image(systemName: "arrow.uturn.forward") }.disabled(!model.canRedo).help("Redo (⇧⌘Z)")
            Menu {
                ForEach(AlignMode.allCases, id: \.self) { mode in
                    Button { model.align(mode) } label: { Label(mode.title, systemImage: mode.symbol) }
                }
            } label: { Image(systemName: "align.horizontal.left") }
            .disabled(model.selectedNodes.count < 2).fixedSize().help("Align and distribute")
            Menu {
                Button("Bring to Front") { model.reorder(.front) }
                Button("Bring Forward") { model.reorder(.forward) }
                Button("Send Backward") { model.reorder(.backward) }
                Button("Send to Back") { model.reorder(.back) }
                Divider()
                Button("Group") { model.groupSelection() }.disabled(model.selectedNodes.count < 2)
                Button("Ungroup") { model.ungroupSelection() }
            } label: { Image(systemName: "square.3.layers.3d") }
            .disabled(model.selection.isEmpty).fixedSize().help("Layer order and grouping")
            Toggle(isOn: $model.showGrid) { Image(systemName: "grid") }.toggleStyle(.button).help("Show grid")
            Toggle(isOn: $model.snapToGrid) { Image(systemName: "rectangle.grid.1x2") }.toggleStyle(.button).help("Snap to grid")
            Picker("Zoom", selection: $model.zoom) {
                Text("75%").tag(0.75); Text("100%").tag(1.0); Text("150%").tag(1.5); Text("200%").tag(2.0)
            }
            .labelsHidden().frame(width: 80)
            Spacer()
            if !model.validation.isValid {
                Label("\(model.validation.errors.count) problem(s)", systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red).font(.caption)
                    .help(model.validation.errors.joined(separator: "\n"))
            }
            Toggle(isOn: $model.isPreviewing) { Image(systemName: model.isPreviewing ? "stop.fill" : "play.fill") }.toggleStyle(.button)
                .help("Live Preview: run with real data and make the widget interactive")
                .accessibilityLabel("Live Preview")
            Menu {
                Button("Save to Library") { save(toLibrary: true) }
                Button("Export…") { app.exportWidget(model.exportDefinition()) }
                Button("Close Builder") { app.builderDocument = nil; app.builderWidgetID = nil }
            } label: { Image(systemName: "ellipsis.circle") }
            .fixedSize()
            Button(widgetID == nil ? "Add" : "Save") { save(toLibrary: false) }
                .buttonStyle(.borderedProminent)
                .fixedSize()
                .help(widgetID == nil ? "Add this widget to your desktop and library" : "Save changes to the widget on your desktop")
                .disabled(!model.validation.isValid)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
    }

    private func save(toLibrary: Bool) {
        guard model.validation.isValid else { return }
        let definition = model.exportDefinition()
        if toLibrary {
            app.saveToLibrary(definition)
            model.log("Saved “\(definition.name)” to the library")
        } else if let widgetID {
            app.updateDefinition(widgetID, definition)
            model.log("Updated the widget on your desktop")
        } else {
            app.addWidget(definition, origin: .builder)
            app.saveToLibrary(definition)
            model.log("Added “\(definition.name)” to your desktop and library")
        }
        model.markSaved()
    }
}

// MARK: Palette (left)

struct BuilderPalette: View {
    @ObservedObject var model: BuilderModel
    @State private var query = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            TextField("Search components", text: $query).textFieldStyle(.roundedBorder).padding(8)
            List {
                Section("Components") {
                    ForEach(FuzzyMatcher.filter(NodeType.palette, query: query) { $0.displayName }, id: \.self) { type in
                        Label(type.displayName, systemImage: type.symbol)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                            .draggable("wf-node:\(type.rawValue)")
                            .onTapGesture(count: 2) { model.add(type) }
                            .help("Drag onto the canvas, or double-click to add")
                            .accessibilityAddTraits(.isButton)
                    }
                }
                Section("Layers") {
                    ForEach(model.document.root.children.reversed()) { node in
                        LayerRow(model: model, node: node, depth: 0)
                    }
                }
            }
            .listStyle(.sidebar)
        }
    }
}

struct LayerRow: View {
    @ObservedObject var model: BuilderModel
    let node: WidgetNode
    let depth: Int

    var body: some View {
        Label(title, systemImage: node.type.symbol)
            .font(.callout)
            .lineLimit(1)
            .padding(.leading, CGFloat(depth) * 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 1)
            .background(model.selection.contains(node.id) ? Color.accentColor.opacity(0.25) : Color.clear, in: RoundedRectangle(cornerRadius: 4))
            .contentShape(Rectangle())
            .onTapGesture { model.selection = [node.id] }
        if depth < 6 {
            ForEach(node.children) { child in LayerRow(model: model, node: child, depth: depth + 1) }
        }
    }

    private var title: String {
        let text = node.string("value") ?? node.string("title") ?? node.string("label") ?? ""
        return text.isEmpty ? node.type.displayName : "\(node.type.displayName): \(text.prefix(18))"
    }
}

// MARK: Canvas (center)

struct BuilderCanvas: View {
    @ObservedObject var model: BuilderModel
    let preview: WidgetRuntime?
    @State private var marquee: CGRect?
    @FocusState private var focused: Bool

    var body: some View {
        let document = model.document
        ScrollView([.horizontal, .vertical]) {
            Group {
                if model.isPreviewing, let preview {
                    BuilderPreviewSurface(runtime: preview)
                        .frame(width: CGFloat(document.size.width), height: CGFloat(document.size.height))
                } else {
                    editor(document)
                }
            }
            .scaleEffect(CGFloat(model.zoom))
            .frame(width: CGFloat(document.size.width * model.zoom) + 120, height: CGFloat(document.size.height * model.zoom) + 120)
        }
        .background(Color(nsColor: .underPageBackgroundColor))
        .focusable()
        .focusEffectDisabled()
        .focused($focused)
        .onKeyPress(phases: .down) { press in handleKey(press) }
        .onTapGesture { focused = true }
    }

    private var staticEnvironment: RenderEnvironment {
        var env = RenderEnvironment()
        env.isInteractive = false
        env.context = WidgetContextBuilder.context(state: model.document.initialState, settings: model.document.settings, data: [:], statuses: [:])
        env.scriptMessage = "Script output appears in Live Preview"
        env.tint = Theme.color(model.document.style.tint, fallback: .accentColor)
        env.designSize = model.canvasSize
        return env
    }

    private func editor(_ document: WidgetDefinition) -> some View {
        let size = model.canvasSize
        let env = staticEnvironment
        return WidgetChrome(style: document.style) {
            ZStack(alignment: .topLeading) {
                if model.showGrid { GridPattern(spacing: CGFloat(model.gridSize * 2)) }
                Color.clear
                    .contentShape(Rectangle())
                    .gesture(marqueeGesture)
                    .onTapGesture { model.selection = []; focused = true }
                ForEach(document.root.children) { child in item(child, env: env) }
                ForEach(Array(model.guides.enumerated()), id: \.offset) { _, guide in
                    Rectangle().fill(Color.pink)
                        .frame(width: guide.axis == .vertical ? 1 : CGFloat(size.width), height: guide.axis == .vertical ? CGFloat(size.height) : 1)
                        .offset(x: guide.axis == .vertical ? CGFloat(guide.position) : 0, y: guide.axis == .vertical ? 0 : CGFloat(guide.position))
                        .allowsHitTesting(false)
                }
                if let marquee {
                    Rectangle().fill(Color.accentColor.opacity(0.12)).overlay(Rectangle().strokeBorder(Color.accentColor))
                        .frame(width: marquee.width, height: marquee.height).offset(x: marquee.minX, y: marquee.minY).allowsHitTesting(false)
                }
            }
            .frame(width: CGFloat(size.width), height: CGFloat(size.height), alignment: .topLeading)
            .coordinateSpace(name: "canvas")
            .dropDestination(for: String.self) { items, location in
                guard let raw = items.first, raw.hasPrefix("wf-node:"), let type = NodeType(rawValue: String(raw.dropFirst(8))) else { return false }
                model.add(type, at: location)
                focused = true
                return true
            }
        }
        .frame(width: CGFloat(document.size.width), height: CGFloat(document.size.height))
        .shadow(color: .black.opacity(0.2), radius: 10, y: 3)
    }

    private func item(_ child: WidgetNode, env: RenderEnvironment) -> some View {
        let frame = child.frame?.rect ?? Rect(x: 0, y: 0, width: 120, height: 28)
        let selected = model.selection.contains(child.id)
        return NodeView(node: child, env: env)
            .frame(width: CGFloat(frame.width), height: CGFloat(frame.height), alignment: .topLeading)
            .allowsHitTesting(false)
            .overlay {
                if selected {
                    Rectangle().strokeBorder(Color.accentColor, lineWidth: 1.5)
                    if model.selection.count == 1 { handles(child.id, size: CGSize(width: frame.width, height: frame.height)) }
                } else {
                    Rectangle().strokeBorder(Color.primary.opacity(0.12), style: StrokeStyle(lineWidth: 0.5, dash: [2, 2]))
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                model.select(child.id, extend: NSEvent.modifierFlags.contains(.shift))
                focused = true
            }
            .gesture(
                DragGesture(minimumDistance: 2, coordinateSpace: .named("canvas"))
                    .onChanged { value in
                        if !model.selection.contains(child.id) { model.select(child.id, extend: NSEvent.modifierFlags.contains(.shift)) }
                        model.drag(by: value.translation, bypassSnapping: NSEvent.modifierFlags.contains(.command))
                    }
                    .onEnded { _ in model.endDrag() }
            )
            .position(x: CGFloat(frame.midX), y: CGFloat(frame.midY))
            .accessibilityLabel("\(child.type.displayName) component")
    }

    private func handles(_ id: String, size: CGSize) -> some View {
        ZStack {
            ForEach(Array(ResizeHandle.allCases.enumerated()), id: \.offset) { _, handle in
                Circle().fill(Color.white).overlay(Circle().strokeBorder(Color.accentColor, lineWidth: 1.5))
                    .frame(width: 9, height: 9)
                    .contentShape(Rectangle().inset(by: -4))
                    .position(x: handle.movesLeft ? 0 : (handle.movesRight ? size.width : size.width / 2),
                              y: handle.movesTop ? 0 : (handle.movesBottom ? size.height : size.height / 2))
                    .gesture(
                        DragGesture(minimumDistance: 1, coordinateSpace: .named("canvas"))
                            .onChanged { model.resize(id, handle: handle, by: $0.translation) }
                            .onEnded { _ in model.endDrag() }
                    )
            }
        }
    }

    private var marqueeGesture: some Gesture {
        DragGesture(minimumDistance: 3, coordinateSpace: .named("canvas"))
            .onChanged { value in
                let rect = CGRect(x: min(value.startLocation.x, value.location.x), y: min(value.startLocation.y, value.location.y),
                                  width: abs(value.translation.width), height: abs(value.translation.height))
                marquee = rect
                model.select(in: Rect(x: Double(rect.minX), y: Double(rect.minY), width: Double(rect.width), height: Double(rect.height)))
            }
            .onEnded { _ in marquee = nil }
    }

    private func handleKey(_ press: KeyPress) -> KeyPress.Result {
        guard !model.isPreviewing else { return .ignored }
        let command = press.modifiers.contains(.command)
        let step: Double = press.modifiers.contains(.shift) ? 10 : 1
        switch press.key {
        case .delete, .deleteForward: model.deleteSelection()
        case .leftArrow: model.nudge(dx: -step, dy: 0)
        case .rightArrow: model.nudge(dx: step, dy: 0)
        case .upArrow: model.nudge(dx: 0, dy: -step)
        case .downArrow: model.nudge(dx: 0, dy: step)
        case .escape: model.selection = []
        default:
            guard command else { return .ignored }
            switch press.characters.lowercased() {
            case "z": if press.modifiers.contains(.shift) { model.redo() } else { model.undo() }
            case "c": model.copySelection()
            case "x": model.copySelection(); model.deleteSelection()
            case "v": model.paste()
            case "d": model.duplicateSelection()
            case "a": model.selectAll()
            case "g": if press.modifiers.contains(.shift) { model.ungroupSelection() } else { model.groupSelection() }
            default: return .ignored
            }
        }
        return .handled
    }
}

struct GridPattern: View {
    let spacing: CGFloat
    var body: some View {
        Canvas { context, size in
            var path = Path()
            var x: CGFloat = 0
            while x <= size.width { path.move(to: CGPoint(x: x, y: 0)); path.addLine(to: CGPoint(x: x, y: size.height)); x += spacing }
            var y: CGFloat = 0
            while y <= size.height { path.move(to: CGPoint(x: 0, y: y)); path.addLine(to: CGPoint(x: size.width, y: y)); y += spacing }
            context.stroke(path, with: .color(.primary.opacity(0.07)), lineWidth: 0.5)
        }
        .allowsHitTesting(false)
    }
}

/// The running widget, exactly as it will appear on the desktop.
struct BuilderPreviewSurface: View {
    @ObservedObject var runtime: WidgetRuntime
    var body: some View {
        WidgetContentView(definition: runtime.instance.definition, env: runtime.environment())
            .shadow(color: .black.opacity(0.2), radius: 10, y: 3)
    }
}

// MARK: Inspector (right)

struct BuilderInspector: View {
    @ObservedObject var model: BuilderModel
    let preview: WidgetRuntime?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if let node = model.inspected {
                    nodeInspector(node)
                } else if model.selection.count > 1 {
                    Text("\(model.selection.count) components selected").font(.headline)
                    Text("Use the toolbar to align, distribute, group or reorder them. Arrow keys nudge; ⌘D duplicates.").font(.caption).foregroundStyle(.secondary)
                } else {
                    widgetInspector
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .controlSize(.small)
    }

    // Widget-level properties

    private var widgetInspector: some View {
        let doc = model.document
        return Group {
            Text("Widget").font(.headline)
            field("Summary") { TextField("Summary", text: Binding(get: { doc.summary }, set: { v in model.mutate { $0.summary = v } })) }
            field("Symbol") { TextField("SF Symbol", text: Binding(get: { doc.symbol }, set: { v in model.mutate { $0.symbol = v } })) }
            field("Size") {
                HStack {
                    NumberField(value: Binding(get: { doc.size.width }, set: { model.setSize(WidgetSize($0, doc.size.height)) }), range: 60...2400)
                    Text("×")
                    NumberField(value: Binding(get: { doc.size.height }, set: { model.setSize(WidgetSize(doc.size.width, $0)) }), range: 60...2400)
                }
            }
            Text("Resizing moves components according to their pinning (responsive layout).").font(.caption2).foregroundStyle(.secondary)
            Divider()
            Text("Appearance").font(.subheadline.weight(.semibold))
            field("Background") {
                Picker("", selection: Binding(get: { ["material", "clear"].contains(doc.style.background) ? doc.style.background : "color" }, set: { v in
                    model.mutate { $0.style.background = v == "color" ? "#1C1C1E" : v }
                })) {
                    Text("Translucent").tag("material"); Text("Clear").tag("clear"); Text("Colour").tag("color")
                }
                .labelsHidden()
            }
            if !["material", "clear"].contains(doc.style.background) {
                field("Colour") { ColorField(value: Binding(get: { doc.style.background }, set: { v in model.mutate { $0.style.background = v ?? "material" } }), allowsNamed: false) }
            }
            field("Tint") { ColorField(value: Binding(get: { doc.style.tint }, set: { v in model.mutate { $0.style.tint = v ?? "accent" } })) }
            slider("Corner radius", doc.style.cornerRadius, 0...48) { v in model.mutate { $0.style.cornerRadius = v } }
            slider("Padding", doc.style.padding, 0...40) { v in model.mutate { $0.style.padding = v } }
            slider("Shadow", doc.style.shadowRadius, 0...30) { v in model.mutate { $0.style.shadowRadius = v } }
            slider("Border width", doc.style.borderWidth, 0...8) { v in model.mutate { $0.style.borderWidth = v } }
            field("Border") { ColorField(value: Binding(get: { doc.style.borderColor }, set: { v in model.mutate { $0.style.borderColor = v } })) }
            Divider()
            Text("Permissions this widget will request").font(.subheadline.weight(.semibold))
            PermissionList(manifest: model.exportDefinition().permissions)
            ForEach(model.validation.errors, id: \.self) { Label($0, systemImage: "xmark.octagon.fill").font(.caption).foregroundStyle(.red) }
            ForEach(model.validation.warnings, id: \.self) { Label($0, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange) }
        }
    }

    // Component properties

    @ViewBuilder
    private func nodeInspector(_ node: WidgetNode) -> some View {
        Label(node.type.displayName, systemImage: node.type.symbol).font(.headline)
        if let frame = node.frame {
            Text("Position & Size").font(.subheadline.weight(.semibold))
            HStack {
                labeledNumber("X", frame.x) { model.setFrame(node.id, NodeFrame(x: $0, y: frame.y, width: frame.width, height: frame.height)) }
                labeledNumber("Y", frame.y) { model.setFrame(node.id, NodeFrame(x: frame.x, y: $0, width: frame.width, height: frame.height)) }
            }
            HStack {
                labeledNumber("W", frame.width) { model.setFrame(node.id, NodeFrame(x: frame.x, y: frame.y, width: max(8, $0), height: frame.height)) }
                labeledNumber("H", frame.height) { model.setFrame(node.id, NodeFrame(x: frame.x, y: frame.y, width: frame.width, height: max(8, $0))) }
            }
            let constraints = node.constraints ?? NodeConstraints()
            Text("Pin to edges when the widget resizes").font(.caption).foregroundStyle(.secondary)
            HStack {
                pin("Left", constraints.pinLeft) { v in var c = constraints; c.pinLeft = v; model.setConstraints(node.id, c) }
                pin("Right", constraints.pinRight) { v in var c = constraints; c.pinRight = v; model.setConstraints(node.id, c) }
                pin("Top", constraints.pinTop) { v in var c = constraints; c.pinTop = v; model.setConstraints(node.id, c) }
                pin("Bottom", constraints.pinBottom) { v in var c = constraints; c.pinBottom = v; model.setConstraints(node.id, c) }
            }
            Divider()
        }
        let content = PropSpec.content(for: node.type)
        if !content.isEmpty {
            Text("Content").font(.subheadline.weight(.semibold))
            ForEach(content) { spec in editor(spec, node) }
            Text("Text fields accept {{placeholders}}; pick one from the Data tab below.").font(.caption2).foregroundStyle(.secondary)
            Divider()
        }
        if PropSpec.hasTypography(node.type) {
            Text("Typography").font(.subheadline.weight(.semibold))
            ForEach(PropSpec.typography) { spec in editor(spec, node) }
            Divider()
        }
        Text("Style & Animation").font(.subheadline.weight(.semibold))
        ForEach(PropSpec.decoration) { spec in editor(spec, node) }
        Divider()
        Text("Visibility").font(.subheadline.weight(.semibold))
        visibilityEditor(node)
    }

    @ViewBuilder
    private func editor(_ spec: PropSpec, _ node: WidgetNode) -> some View {
        let current = node.props[spec.key]
        let text = Binding<String>(get: { current.map { $0.stringValue ?? $0.compactJSONString } ?? "" },
                                   set: { model.setProp(node.id, spec.key, .string($0)) })
        switch spec.kind {
        case .text:
            field(spec.label) { TextField(spec.label, text: text) }
        case .symbol:
            field(spec.label) {
                HStack {
                    TextField("SF Symbol name", text: text)
                    Image(systemName: text.wrappedValue.isEmpty ? "questionmark" : text.wrappedValue).frame(width: 18)
                }
            }
        case .multiline:
            VStack(alignment: .leading, spacing: 2) {
                Text(spec.label).font(.caption).foregroundStyle(.secondary)
                TextEditor(text: text).font(.system(size: 12)).frame(height: 54)
                    .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Color.primary.opacity(0.15)))
            }
        case .json:
            VStack(alignment: .leading, spacing: 2) {
                Text(spec.label).font(.caption).foregroundStyle(.secondary)
                TextField("{{source.path}} or JSON", text: Binding(get: { text.wrappedValue }, set: { raw in
                    let trimmed = raw.trimmingCharacters(in: .whitespaces)
                    if (trimmed.hasPrefix("[") || trimmed.hasPrefix("{")) && !trimmed.hasPrefix("{{"), let parsed = try? JSONValue.parse(trimmed) {
                        model.setProp(node.id, spec.key, parsed)
                    } else {
                        model.setProp(node.id, spec.key, .string(raw))
                    }
                }))
            }
        case .number(let range, let step):
            let value = current?.doubleValue
            field(spec.label) {
                HStack {
                    Slider(value: Binding(get: { value ?? range.lowerBound }, set: { model.setProp(node.id, spec.key, .number(($0 / step).rounded() * step)) }), in: range)
                    Text(value.map { JSONValue.format($0) } ?? "auto").font(.caption.monospacedDigit()).frame(width: 34, alignment: .trailing)
                    Button { model.setProp(node.id, spec.key, nil) } label: { Image(systemName: "xmark.circle") }.buttonStyle(.plain)
                        .opacity(value == nil ? 0 : 0.6).accessibilityLabel("Reset \(spec.label)")
                }
            }
        case .color:
            field(spec.label) { ColorField(value: Binding(get: { current?.stringValue }, set: { model.setProp(node.id, spec.key, $0.map { .string($0) }) })) }
        case .bool:
            Toggle(spec.label, isOn: Binding(get: { current?.boolValue ?? false }, set: { model.setProp(node.id, spec.key, .bool($0)) }))
        case .choice(let options):
            field(spec.label) {
                Picker("", selection: Binding(get: { current?.stringValue ?? "" }, set: { model.setProp(node.id, spec.key, $0.isEmpty ? nil : .string($0)) })) {
                    Text("Default").tag("")
                    ForEach(options, id: \.self) { Text($0).tag($0) }
                }
                .labelsHidden()
            }
        case .action:
            ActionEditor(label: spec.label, action: Binding(get: { WidgetAction(json: current) }, set: { model.setProp(node.id, spec.key, $0?.json) }))
        }
    }

    @ViewBuilder
    private func visibilityEditor(_ node: WidgetNode) -> some View {
        let rule = node.props["visibleWhen"]?.objectValue
        Toggle("Only show when a condition is true", isOn: Binding(get: { rule != nil }, set: { on in
            model.setProp(node.id, "visibleWhen", on ? ["path": "state.enabled", "op": "==", "value": true] : nil)
        }))
        if let rule {
            let condition = Condition(rule["path"]?.stringValue ?? "", Condition.Operator(rawValue: rule["op"]?.stringValue ?? "==") ?? .equals, rule["value"] ?? .null)
            HStack {
                ConditionFields(condition: Binding(get: { condition }, set: { new in
                    model.setProp(node.id, "visibleWhen", ["path": .string(new.path), "op": .string(new.op.rawValue), "value": new.value])
                }))
            }
        }
    }

    // Small building blocks

    private func field<Content: View>(_ label: String, @ViewBuilder _ content: () -> Content) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label).font(.caption).foregroundStyle(.secondary).frame(width: 78, alignment: .leading)
            content()
        }
        .textFieldStyle(.roundedBorder)
    }

    private func slider(_ label: String, _ value: Double, _ range: ClosedRange<Double>, _ set: @escaping (Double) -> Void) -> some View {
        field(label) {
            Slider(value: Binding(get: { value }, set: { set($0.rounded()) }), in: range)
            Text("\(Int(value))").font(.caption.monospacedDigit()).frame(width: 24, alignment: .trailing)
        }
    }

    private func labeledNumber(_ label: String, _ value: Double, _ set: @escaping (Double) -> Void) -> some View {
        HStack(spacing: 4) {
            Text(label).font(.caption).foregroundStyle(.secondary).frame(width: 14)
            NumberField(value: Binding(get: { value }, set: set), range: -5000...5000)
        }
    }

    private func pin(_ label: String, _ on: Bool, _ set: @escaping (Bool) -> Void) -> some View {
        Toggle(label, isOn: Binding(get: { on }, set: set)).toggleStyle(.button).font(.caption)
    }
}

struct NumberField: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    var body: some View {
        TextField("", value: Binding(get: { value.rounded() }, set: { value = min(range.upperBound, max(range.lowerBound, $0)) }), format: .number.grouping(.never))
            .textFieldStyle(.roundedBorder)
            .frame(minWidth: 48)
    }
}

/// Named system colours plus a custom colour picker, stored as a name or hex string.
struct ColorField: View {
    @Binding var value: String?
    var allowsNamed = true
    static let names = ["primary", "secondary", "accent", "red", "orange", "yellow", "green", "mint", "teal", "blue", "indigo", "purple", "pink", "gray", "white", "black"]

    var body: some View {
        HStack(spacing: 6) {
            if allowsNamed {
                Picker("", selection: Binding(get: { value.map { ColorField.names.contains($0) ? $0 : "custom" } ?? "" }, set: { choice in
                    if choice.isEmpty { value = nil } else if choice != "custom" { value = choice } else { value = "#888888" }
                })) {
                    Text("Default").tag("")
                    ForEach(ColorField.names, id: \.self) { Text($0.capitalized).tag($0) }
                    Text("Custom…").tag("custom")
                }
                .labelsHidden()
            }
            ColorPicker("", selection: Binding(get: { Theme.color(value, fallback: .gray) }, set: { value = ColorField.hex($0) }), supportsOpacity: true)
                .labelsHidden()
                .accessibilityLabel("Custom colour")
        }
    }

    static func hex(_ color: Color) -> String {
        guard let c = NSColor(color).usingColorSpace(.sRGB) else { return "#888888" }
        let r = Int((c.redComponent * 255).rounded()), g = Int((c.greenComponent * 255).rounded()), b = Int((c.blueComponent * 255).rounded())
        let a = Int((c.alphaComponent * 255).rounded())
        return a >= 255 ? String(format: "#%02X%02X%02X", r, g, b) : String(format: "#%02X%02X%02X%02X", r, g, b, a)
    }
}

struct ActionEditor: View {
    let label: String
    @Binding var action: WidgetAction?

    private var kind: String { action?.json["type"]?.stringValue ?? "" }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label).font(.caption).foregroundStyle(.secondary).frame(width: 78, alignment: .leading)
                Picker("", selection: Binding(get: { kind }, set: { action = ActionEditor.make($0) })) {
                    Text("None").tag("")
                    ForEach(WidgetAction.typeNames, id: \.self) { Text($0).tag($0) }
                }
                .labelsHidden()
            }
            switch action {
            case .setState(let key, let value):
                TextField("State key", text: Binding(get: { key }, set: { action = .setState(key: $0, value: value) }))
                TextField("Value", text: Binding(get: { value.displayString }, set: { action = .setState(key: key, value: ActionEditor.parse($0)) }))
            case .toggleState(let key): TextField("State key", text: Binding(get: { key }, set: { action = .toggleState(key: $0) }))
            case .incrementState(let key, let by):
                TextField("State key", text: Binding(get: { key }, set: { action = .incrementState(key: $0, by: by) }))
                TextField("Amount", value: Binding(get: { by }, set: { action = .incrementState(key: key, by: $0) }), format: .number)
            case .openURL(let url): TextField("https://", text: Binding(get: { url }, set: { action = .openURL($0) }))
            case .runShortcut(let name): TextField("Shortcut name", text: Binding(get: { name }, set: { action = .runShortcut($0) }))
            case .launchApp(let id): TextField("Bundle ID", text: Binding(get: { id }, set: { action = .launchApp($0) }))
            case .trigger(let name): TextField("Automation trigger name", text: Binding(get: { name }, set: { action = .trigger($0) }))
            case .script(let name): TextField("Script action name", text: Binding(get: { name }, set: { action = .script($0) }))
            case .copy(let text): TextField("Text to copy", text: Binding(get: { text }, set: { action = .copy($0) }))
            case .media(let command):
                Picker("", selection: Binding(get: { command }, set: { action = .media($0) })) {
                    Text("Play/Pause").tag("playpause"); Text("Next").tag("next"); Text("Previous").tag("previous")
                }
                .labelsHidden()
            case .refresh, .none: EmptyView()
            }
        }
        .textFieldStyle(.roundedBorder)
    }

    static func parse(_ text: String) -> JSONValue {
        if let number = Double(text) { return .number(number) }
        if text == "true" { return true }
        if text == "false" { return false }
        return .string(text)
    }

    static func make(_ kind: String) -> WidgetAction? {
        switch kind {
        case "setState": return .setState(key: "value", value: 1)
        case "toggleState": return .toggleState(key: "enabled")
        case "incrementState": return .incrementState(key: "count", by: 1)
        case "openURL": return .openURL("https://")
        case "runShortcut": return .runShortcut("")
        case "launchApp": return .launchApp("")
        case "refresh": return .refresh
        case "trigger": return .trigger("pressed")
        case "script": return .script("")
        case "media": return .media("playpause")
        case "copy": return .copy("")
        default: return nil
        }
    }
}

// MARK: Bottom panel (console, script, data, settings, JSON)

struct BuilderBottomPanel: View {
    @EnvironmentObject private var app: AppModel
    @ObservedObject var model: BuilderModel
    @Binding var tab: BuilderView.BottomTab
    let preview: WidgetRuntime?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Picker("", selection: $tab) {
                    ForEach(BuilderView.BottomTab.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented).labelsHidden().frame(maxWidth: 360)
                Spacer()
                if tab == .console { Button("Clear") { model.clearConsole() }.controlSize(.small).fixedSize() }
            }
            .padding(6)
            Divider()
            switch tab {
            case .console: console
            case .script: script
            case .data: BuilderDataPanel(model: model, preview: preview)
            case .settings: settings
            case .json: json
            }
        }
    }

    private var console: some View {
        let scriptLogs = preview.map { app.diagnostics.snapshot(widgetID: $0.id).suffix(60) } ?? []
        return ScrollView {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(model.validation.errors, id: \.self) { Text("✖ \($0)").foregroundStyle(.red) }
                ForEach(model.validation.warnings, id: \.self) { Text("⚠ \($0)").foregroundStyle(.orange) }
                ForEach(model.console) { line in
                    Text("\(line.date.formatted(date: .omitted, time: .standard))  \(line.text)").foregroundStyle(line.isError ? .red : .primary)
                }
                ForEach(Array(scriptLogs)) { entry in
                    Text("\(entry.date.formatted(date: .omitted, time: .standard))  [\(entry.category.rawValue)] \(entry.message)")
                        .foregroundStyle(entry.level == .error ? .red : (entry.level == .warning ? .orange : .secondary))
                }
                if let preview {
                    PreviewStatus(runtime: preview)
                } else {
                    Text("Turn on Live Preview to see data-source status, script output and errors here.").foregroundStyle(.secondary)
                }
            }
            .font(.system(size: 11, design: .monospaced))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8)
            .textSelection(.enabled)
        }
    }

    private var script: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Toggle("Run script in Live Preview", isOn: $model.runScriptInPreview).toggleStyle(.switch).controlSize(.small)
                Text(ScriptRuntime.watchdogAvailable ? "Runs in the restricted runtime with a time limit." : "Unavailable: this macOS build cannot interrupt runaway scripts.")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Insert Example") { model.mutate { $0.script = TemplateLibrary.customScript.script } }.controlSize(.small)
                Button("Remove Script") { model.mutate { $0.script = nil } }.controlSize(.small).disabled(!model.document.hasScript)
            }
            TextEditor(text: Binding(get: { model.document.script ?? "" }, set: { text in model.mutate { $0.script = text.isEmpty ? nil : text } }))
                .font(.system(size: 12, design: .monospaced))
                .autocorrectionDisabled()
            Text("Add a “Custom Script” component to the canvas to show what render() returns. API: docs/SDK.md").font(.caption2).foregroundStyle(.secondary)
        }
        .padding(8)
    }

    private var settings: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                Text("Settings are values your widget reads as {{settings.key}} and users edit without opening the builder.").font(.caption).foregroundStyle(.secondary)
                ForEach(model.document.settings.keys.sorted(), id: \.self) { key in
                    HStack {
                        Text(key).font(.callout.monospaced()).frame(width: 140, alignment: .leading)
                        TextField("Default value", text: Binding(get: { model.document.settings[key]?.displayString ?? "" },
                                                                  set: { text in model.mutate { $0.settings[key] = ActionEditor.parse(text) } }))
                        Button { model.mutate { $0.settings[key] = nil } } label: { Image(systemName: "minus.circle") }.buttonStyle(.plain)
                            .accessibilityLabel("Remove setting \(key)")
                    }
                }
                AddKeyRow(placeholder: "new setting key") { key in model.mutate { $0.settings[key] = "" } }
                Divider()
                TextField("Setup instructions shown to users", text: Binding(get: { model.document.setupInstructions ?? "" },
                                                                             set: { text in model.mutate { $0.setupInstructions = text.isEmpty ? nil : text } }))
            }
            .textFieldStyle(.roundedBorder).controlSize(.small).padding(8)
        }
    }

    private var json: some View {
        let text = (try? JSONValue.encode(model.exportDefinition()))?.prettyJSONString ?? "{}"
        return VStack(alignment: .trailing, spacing: 4) {
            Button("Copy JSON") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
            }
            .controlSize(.small)
            ScrollView {
                Text(text).font(.system(size: 11, design: .monospaced)).frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled)
            }
        }
        .padding(8)
    }
}

struct PreviewStatus: View {
    @ObservedObject var runtime: WidgetRuntime
    var body: some View {
        ForEach(runtime.sourceStatuses.keys.sorted(), id: \.self) { id in
            let status = runtime.sourceStatuses[id] ?? .idle
            Text("● \(id): \(status.label)\(status.detail.map { " – \($0)" } ?? "")").foregroundStyle(status.isHealthy ? .green : .orange)
        }
        if let message = runtime.scriptMessage { Text("script: \(message)").foregroundStyle(.orange) }
        if let notice = runtime.lastNotice { Text(notice).foregroundStyle(.orange) }
    }
}

struct AddKeyRow: View {
    let placeholder: String
    let add: (String) -> Void
    @State private var key = ""
    var body: some View {
        HStack {
            TextField(placeholder, text: $key).frame(width: 180).onSubmit(commit)
            Button("Add", action: commit).disabled(key.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }

    private func commit() {
        let trimmed = key.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        add(trimmed)
        key = ""
    }
}

/// Data sources and the binding picker.
struct BuilderDataPanel: View {
    @EnvironmentObject private var app: AppModel
    @ObservedObject var model: BuilderModel
    let preview: WidgetRuntime?
    @State private var selected: String?

    static let metricFields: [String: [String]] = [
        "cpu": ["usage | percent", "user | percent", "system | percent", "cores", "history"],
        "memory": ["usage | percent", "usedBytes | bytes", "availableBytes | bytes", "totalBytes | bytes", "pressure", "history"],
        "storage": ["usage | percent", "usedBytes | bytes", "freeBytes | bytes", "totalBytes | bytes", "readBytesPerSec | rate", "writeBytesPerSec | rate"],
        "network": ["downBytesPerSec | rate", "upBytesPerSec | rate", "connected | yesno", "primaryInterface", "address", "downHistory", "upHistory"],
        "battery": ["level | percent", "charging | yesno", "source", "minutesRemaining", "present", "history"],
        "system": ["uptimeSeconds | duration", "hostname", "osVersion", "architecture", "processor", "cores"],
    ]

    var body: some View {
        HSplitView {
            VStack(alignment: .leading, spacing: 4) {
                List(selection: $selected) {
                    ForEach(model.document.dataSources) { source in
                        Label("\(source.id)  ·  \(source.kind.title)", systemImage: source.kind.usesNetwork ? "network" : "cylinder").tag(source.id)
                    }
                }
                HStack {
                    Menu("Add Source") {
                        ForEach(SystemMetricsCollector.knownMetrics, id: \.self) { metric in
                            Button("System: \(metric)") { addSource(.metric(metric)) }
                        }
                        Divider()
                        Button("REST JSON API") { addSource(DataSourceConfig(id: unique("api"), kind: .rest, url: "https://", interval: 60)) }
                        Button("WebSocket stream") { addSource(DataSourceConfig(id: unique("stream"), kind: .webSocket, url: "wss://", interval: 0)) }
                        Button("Local HTTP service") { addSource(DataSourceConfig(id: unique("local"), kind: .localHTTP, url: "http://localhost:8080/", interval: 5)) }
                        Button("JSON file") { addSource(DataSourceConfig(id: unique("file"), kind: .jsonFile, interval: 10)) }
                        Button("CSV file") { addSource(DataSourceConfig(id: unique("csv"), kind: .csvFile, interval: 10)) }
                        Button("Calendar events") { addSource(DataSourceConfig(id: unique("events"), kind: .calendar, interval: 300)) }
                        Button("Time & date") { addSource(DataSourceConfig(id: unique("time"), kind: .time, interval: 1)) }
                        Button("User-defined data") { addSource(DataSourceConfig(id: unique("data"), kind: .userData, interval: 0, value: ["items": []])) }
                    }
                    .fixedSize()
                    Button("Remove") {
                        guard let selected else { return }
                        model.mutate { $0.dataSources.removeAll { $0.id == selected } }
                        self.selected = nil
                    }
                    .disabled(selected == nil)
                }
                .controlSize(.small).padding(.horizontal, 6).padding(.bottom, 6)
            }
            .frame(minWidth: 220, idealWidth: 250)

            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    if let index = model.document.dataSources.firstIndex(where: { $0.id == selected }) {
                        sourceEditor(index)
                    } else {
                        Text("Select a source to edit it, or add one. Every network host is added to the widget's permission request.").font(.caption).foregroundStyle(.secondary)
                    }
                    Divider()
                    Text("Bindings (click to use)").font(.caption.weight(.semibold))
                    bindings
                }
                .textFieldStyle(.roundedBorder).controlSize(.small).padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func unique(_ base: String) -> String {
        let existing = Set(model.document.dataSources.map(\.id))
        if !existing.contains(base) { return base }
        var n = 2
        while existing.contains("\(base)\(n)") { n += 1 }
        return "\(base)\(n)"
    }

    private func addSource(_ source: DataSourceConfig) {
        guard !model.document.dataSources.contains(where: { $0.id == source.id }) else { selected = source.id; return }
        model.mutate { $0.dataSources.append(source) }
        selected = source.id
    }

    private func edit(_ index: Int, _ body: @escaping (inout DataSourceConfig) -> Void) {
        model.mutate { doc in
            guard doc.dataSources.indices.contains(index) else { return }
            body(&doc.dataSources[index])
        }
    }

    @ViewBuilder
    private func sourceEditor(_ index: Int) -> some View {
        let source = model.document.dataSources[index]
        HStack {
            Text("Name").frame(width: 70, alignment: .leading)
            TextField("id used in {{placeholders}}", text: Binding(get: { source.id }, set: { new in
                let clean = new.filter { $0.isLetter || $0.isNumber || $0 == "_" }
                guard !clean.isEmpty, !["state", "settings", "sources"].contains(clean) else { return }
                edit(index) { $0.id = clean; $0.name = clean }
                selected = clean
            })).frame(width: 160)
            Text(source.kind.title).foregroundStyle(.secondary)
        }
        if source.kind.usesNetwork {
            HStack {
                Text("URL").frame(width: 70, alignment: .leading)
                TextField("https://…  ({{settings.key}} and {{secret:NAME}} allowed after the host)", text: Binding(get: { source.url }, set: { v in edit(index) { $0.url = v } }))
            }
            if source.kind != .webSocket {
                HStack {
                    Text("Method").frame(width: 70, alignment: .leading)
                    Picker("", selection: Binding(get: { source.method }, set: { v in edit(index) { $0.method = v } })) {
                        ForEach(["GET", "POST", "PUT", "PATCH", "DELETE"], id: \.self) { Text($0).tag($0) }
                    }
                    .labelsHidden().frame(width: 90)
                    Text("Cache (s)")
                    NumberField(value: Binding(get: { source.cacheTTL }, set: { v in edit(index) { $0.cacheTTL = max(0, v) } }), range: 0...86_400).frame(width: 70)
                    Text("Retries")
                    NumberField(value: Binding(get: { Double(source.retry.maxAttempts) }, set: { v in edit(index) { $0.retry.maxAttempts = Int(min(8, max(1, v))) } }), range: 1...8).frame(width: 50)
                }
            }
            HStack(alignment: .top) {
                Text("Headers").frame(width: 70, alignment: .leading)
                TextField("Name: value, one per line. Use {{secret:NAME}} for credentials.", text: Binding(
                    get: { source.headers.sorted { $0.key < $1.key }.map { "\($0.key): \($0.value)" }.joined(separator: "\n") },
                    set: { text in
                        var headers: [String: String] = [:]
                        for line in text.split(whereSeparator: \.isNewline) {
                            let parts = line.split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
                            if parts.count == 2, !parts[0].isEmpty { headers[parts[0]] = parts[1] }
                        }
                        edit(index) { $0.headers = headers }
                    }), axis: .vertical)
                .lineLimit(1...4)
            }
        }
        if source.kind == .systemMetric {
            HStack {
                Text("Metric").frame(width: 70, alignment: .leading)
                Picker("", selection: Binding(get: { source.metric ?? "cpu" }, set: { v in edit(index) { $0.metric = v } })) {
                    ForEach(SystemMetricsCollector.knownMetrics, id: \.self) { Text($0).tag($0) }
                }
                .labelsHidden().frame(width: 140)
            }
        }
        if source.kind == .jsonFile || source.kind == .csvFile {
            HStack {
                Text("File").frame(width: 70, alignment: .leading)
                Picker("", selection: Binding(get: { source.fileID ?? "" }, set: { v in edit(index) { $0.fileID = v.isEmpty ? nil : v } })) {
                    Text("None").tag("")
                    ForEach(app.files) { Text($0.name).tag($0.id) }
                }
                .labelsHidden().frame(width: 220)
                Button("Choose…") { if let entry = app.chooseFile() { edit(index) { $0.fileID = entry.id } } }
            }
        }
        if source.kind == .userData {
            HStack(alignment: .top) {
                Text("JSON").frame(width: 70, alignment: .leading)
                TextField("{\"items\": []}", text: Binding(get: { source.value?.compactJSONString ?? "" }, set: { text in
                    if let parsed = try? JSONValue.parse(text) { edit(index) { $0.value = parsed } }
                }), axis: .vertical).lineLimit(1...5).font(.system(size: 11, design: .monospaced))
            }
        }
        if source.kind != .userData && source.kind != .webSocket {
            HStack {
                Text("Refresh").frame(width: 70, alignment: .leading)
                NumberField(value: Binding(get: { source.interval }, set: { v in edit(index) { $0.interval = max(0, v) } }), range: 0...86_400).frame(width: 70)
                Text("seconds (0 = once). Minimum for this type: \(Int(source.kind.minimumInterval)) s; effective: \(source.effectiveInterval > 0 ? "\(Int(source.effectiveInterval)) s" : "once")")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        if source.kind != .systemMetric && source.kind != .time {
            HStack {
                Text("Transform").frame(width: 70, alignment: .leading)
                TextField("optional JSON path, e.g. data.items", text: Binding(get: { source.transform ?? "" }, set: { v in edit(index) { $0.transform = v.isEmpty ? nil : v } }))
            }
        }
    }

    @ViewBuilder
    private var bindings: some View {
        let sources = WidgetContextBuilder.effectiveSources(for: model.document)
        if sources.isEmpty && model.document.settings.isEmpty { Text("Add a data source to bind components to live values.").font(.caption).foregroundStyle(.secondary) }
        ForEach(sources) { source in
            let fields: [String] = {
                if source.kind == .systemMetric { return BuilderDataPanel.metricFields[source.metric ?? source.id] ?? [] }
                // For other sources, offer the top-level keys of the latest value seen in Live Preview.
                if let object = preview?.context[source.id]?.objectValue { return object.keys.sorted().prefix(12).map { $0 } }
                return []
            }()
            HStack(alignment: .top) {
                Text(source.id).font(.caption.monospaced()).frame(width: 70, alignment: .leading)
                FlowChips(items: [source.id] + fields.map { "\(source.id).\($0)" }) { use("{{\($0)}}") }
            }
        }
        if !model.document.settings.isEmpty {
            HStack(alignment: .top) {
                Text("settings").font(.caption.monospaced()).frame(width: 70, alignment: .leading)
                FlowChips(items: model.document.settings.keys.sorted().map { "settings.\($0)" }) { use("{{\($0)}}") }
            }
        }
    }

    /// Bind the selected component's main prop to the placeholder, or copy it when nothing suitable is selected.
    private func use(_ placeholder: String) {
        if let node = model.inspected {
            let key: String?
            switch node.type {
            case .text, .richText, .progress, .gauge, .apiViewer: key = "value"
            case .chart: key = "values"
            case .list, .table: key = "items"
            case .button: key = "title"
            default: key = nil
            }
            if let key {
                model.setProp(node.id, key, .string(placeholder))
                model.log("Bound \(node.type.displayName).\(key) to \(placeholder)")
                return
            }
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(placeholder, forType: .string)
        model.log("Copied \(placeholder) to the clipboard")
    }
}

struct FlowChips: View {
    let items: [String]
    let action: (String) -> Void
    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 4, alignment: .leading)], alignment: .leading, spacing: 4) {
            ForEach(items, id: \.self) { item in
                Button { action(item) } label: {
                    Text(item).font(.system(size: 10, design: .monospaced)).lineLimit(1)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Color.accentColor.opacity(0.14), in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }
}
