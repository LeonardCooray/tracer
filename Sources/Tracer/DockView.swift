import AppKit
import SwiftUI
import TracerCore

@MainActor
final class DockState: ObservableObject {
    @Published var tool: Tool = .pen
    @Published var color = InkPalette.presets[0]
    @Published var mode: AppMode = .drawing
    @Published var canOutput = false
    var onCommand: (SessionCommand) -> Void = { _ in }
    var onColor: (RGBA) -> Void = { _ in }
    var onWidth: (Double) -> Void = { _ in }
    var onMoreColors: () -> Void = {}
}

extension Tool {
    var symbol: String {
        switch self {
        case .pen: "pencil.tip"
        case .highlighter: "highlighter"
        case .arrow: "arrow.up.right"
        case .rectangle: "rectangle"
        case .spotlight: "light.max"
        case .text: "textformat"
        }
    }
}

extension RGBA {
    var swiftUI: Color { Color(.sRGB, red: r, green: g, blue: b, opacity: a) }
}

struct DockView: View {
    @ObservedObject var state: DockState

    private var tools: [Tool] { Tool.allCases.filter { state.mode != .capturing || $0.availableInCapture } }

    var body: some View {
        VStack(spacing: 4) {
            ForEach(tools, id: \.self) { tool in
                button(tool.symbol, help: "\(tool.displayName) (\(tool.rawValue))", selected: state.tool == tool) {
                    state.onCommand(.selectTool(tool))
                }
            }
            divider
            ForEach(Array(InkPalette.presets.enumerated()), id: \.offset) { _, c in
                Circle()
                    .fill(c.swiftUI)
                    .frame(width: 14, height: 14)
                    .overlay(Circle().stroke(Color.white.opacity(state.color == c ? 1 : 0.25), lineWidth: 2))
                    .frame(width: 26, height: 22)
                    .contentShape(Rectangle())
                    .onTapGesture { state.onColor(c) }
            }
            if state.mode == .capturing {
                divider
                button("doc.on.doc", help: "Copy (↩ or ⌘C)", selected: false, accent: true) { state.onCommand(.copy) }
                    .disabled(!state.canOutput)
                button("square.and.arrow.down", help: "Save (⌘S)", selected: false) { state.onCommand(.save) }
                    .disabled(!state.canOutput)
            }
        }
        .padding(6)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color(white: 0.12, opacity: 0.78)))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.14), lineWidth: 1))
        .contextMenu {
            Button("More Colours…") { state.onMoreColors() }
            Divider()
            ForEach([("Thin", 2.0), ("Medium", 4.0), ("Thick", 8.0), ("Extra thick", 14.0), ("Marker", 24.0)], id: \.0) { name, w in
                Button(name) { state.onWidth(w) }
            }
        }
        .fixedSize()
    }

    private var divider: some View {
        Rectangle().fill(Color.white.opacity(0.18)).frame(width: 18, height: 1).padding(.vertical, 2)
    }

    private func button(_ symbol: String, help: String, selected: Bool, accent: Bool = false,
                        action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: 26, height: 26)
                .background(RoundedRectangle(cornerRadius: 7).fill(
                    accent ? Color.accentColor : Color.white.opacity(selected ? 0.18 : 0)))
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

@MainActor
final class DockPanel: NSPanel {
    let state: DockState
    private let host: NSHostingView<DockView>

    init(state: DockState) {
        self.state = state
        host = NSHostingView(rootView: DockView(state: state))
        super.init(contentRect: NSRect(x: 0, y: 0, width: 40, height: 300), styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 1)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        hidesOnDeactivate = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        contentView = host
    }

    override var canBecomeKey: Bool { false }

    private var slideToken = 0

    var fittingSize: NSSize {
        host.layoutSubtreeIfNeeded()
        return host.fittingSize
    }

    func slideIn(onRightEdgeOf screen: NSScreen) {
        slideToken += 1
        let size = fittingSize
        let f = screen.visibleFrame
        let target = NSRect(x: f.maxX - 10 - size.width, y: f.midY - size.height / 2, width: size.width, height: size.height)
        setFrame(target.offsetBy(dx: size.width + 20, dy: 0), display: false)
        orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.18
            animator().setFrame(target, display: true)
        }
    }

    func place(at origin: NSPoint) {
        slideToken += 1
        setFrame(NSRect(origin: origin, size: fittingSize), display: true)
        orderFrontRegardless()
    }

    func slideOut() {
        guard isVisible else { return }
        slideToken += 1
        let token = slideToken
        let f = frame
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.18
            animator().setFrame(f.offsetBy(dx: f.width + 20, dy: 0), display: true)
        }, completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.slideToken == token else { return }
                self.orderOut(nil)
            }
        })
    }
}
