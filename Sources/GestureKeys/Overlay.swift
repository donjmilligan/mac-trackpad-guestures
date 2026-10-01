import AppKit

private func makeOverlayPanel(frame: NSRect) -> NSPanel {
    let panel = NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
    panel.isOpaque = false
    panel.backgroundColor = .clear
    panel.hasShadow = false
    panel.ignoresMouseEvents = true
    panel.level = .screenSaver
    panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
    panel.isReleasedWhenClosed = false
    return panel
}

private func screenUnderMouse() -> NSScreen? {
    let mouse = NSEvent.mouseLocation
    return NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
}

/// Shows the stroke being drawn, mapped from the trackpad onto the middle of the screen.
final class DrawingOverlay {
    private var panel: NSPanel?
    private let strokeView = StrokeView()

    func begin(aspect: CGFloat) {
        guard let screen = screenUnderMouse() else { return }
        let panel = panel ?? makeOverlayPanel(frame: screen.frame)
        panel.contentView = strokeView
        panel.setFrame(screen.frame, display: false)
        strokeView.aspect = aspect
        strokeView.points = []
        strokeView.needsDisplay = true
        panel.orderFrontRegardless()
        self.panel = panel
    }

    func add(_ normalized: CGPoint) {
        strokeView.points.append(normalized)
        strokeView.needsDisplay = true
    }

    func end() {
        panel?.orderOut(nil)
    }
}

private final class StrokeView: NSView {
    var points: [CGPoint] = []
    var aspect: CGFloat = 1.6

    override func draw(_ dirtyRect: NSRect) {
        var height = bounds.height * 0.55
        var width = height * aspect
        if width > bounds.width * 0.9 {
            width = bounds.width * 0.9
            height = width / aspect
        }
        let area = NSRect(x: bounds.midX - width / 2, y: bounds.midY - height / 2, width: width, height: height)

        NSColor.black.withAlphaComponent(0.12).setFill()
        NSBezierPath(roundedRect: area, xRadius: 18, yRadius: 18).fill()

        guard let first = points.first else { return }
        let map = { (p: CGPoint) in NSPoint(x: area.minX + p.x * area.width, y: area.minY + p.y * area.height) }
        let path = NSBezierPath()
        path.move(to: map(first))
        for p in points.dropFirst() { path.line(to: map(p)) }
        path.lineWidth = 7
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        NSColor.controlAccentColor.withAlphaComponent(0.9).setStroke()
        path.stroke()
    }
}

/// Brief bottom-of-screen label confirming what was recognized.
final class HUD {
    private var panel: NSPanel?
    private let label = NSTextField(labelWithString: "")
    private var hideWork: DispatchWorkItem?

    func show(_ text: String) {
        guard let screen = screenUnderMouse() else { return }
        let panel = panel ?? makePanel()
        self.panel = panel

        label.stringValue = text
        label.sizeToFit()
        let size = NSSize(width: label.frame.width + 40, height: label.frame.height + 22)
        let origin = NSPoint(x: screen.visibleFrame.midX - size.width / 2, y: screen.visibleFrame.minY + 80)
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
        label.frame.origin = NSPoint(x: 20, y: 11)

        hideWork?.cancel()
        panel.alphaValue = 1
        panel.orderFrontRegardless()

        let work = DispatchWorkItem { [weak panel] in
            NSAnimationContext.runAnimationGroup({ $0.duration = 0.3; panel?.animator().alphaValue = 0 }) {
                panel?.orderOut(nil)
            }
        }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.1, execute: work)
    }

    private func makePanel() -> NSPanel {
        let panel = makeOverlayPanel(frame: .zero)
        let background = NSVisualEffectView()
        background.material = .hudWindow
        background.state = .active
        background.wantsLayer = true
        background.layer?.cornerRadius = 12
        label.font = .systemFont(ofSize: 16, weight: .medium)
        label.textColor = .labelColor
        background.addSubview(label)
        panel.contentView = background
        return panel
    }
}
