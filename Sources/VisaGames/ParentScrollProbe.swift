import AppKit
import SwiftUI
import VisaCore

/// No @Published properties: observing a body must never invalidate that body.
@MainActor
final class ParentScrollViewTrace: ObservableObject {
    let id = UUID()
    private let name: String
    private var lastBody: TimeInterval = -.infinity
    private var bodies = 0

    init(_ name: String) { self.name = name }

    func body(_ detail: @autoclosure () -> String) {
        bodies += 1
        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastBody >= 0.1 else { return }
        lastBody = now
        event("body count=\(bodies) \(detail())")
    }

    func event(_ detail: String) {
        ParentScrollDiagnostics.record("VIEW name=\(name) instance=\(id) \(detail)")
    }
}

@MainActor
enum ParentScrollDiagnostics {
    fileprivate static weak var active: ParentScrollProbeView?
    static var isActive: Bool { active != nil }

    static func record(_ message: String) {
        active?.remember(message)
        ParentScrollLog.write(message)
    }

    static func responder(_ responder: NSResponder?) -> String {
        guard let responder else { return "nil" }
        // Class/identity/geometry only; never description, text, titles or field contents.
        let identity = "\(type(of: responder))@\(ObjectIdentifier(responder))"
        guard let view = responder as? NSView else { return identity }
        return "\(identity) windowRect=\(NSStringFromRect(view.convert(view.bounds, to: nil)))"
    }
}

/// A non-interactive background of the scroll CONTENT, so enclosingScrollView resolves
/// the existing SwiftUI scroll view. Never creates/replaces a scroll view or sets its bounds.
struct ParentScrollProbe: NSViewRepresentable {
    let parentID: UUID
    let tab: String

    func makeNSView(context: Context) -> ParentScrollProbeView {
        let view = ParentScrollProbeView()
        view.parentID = parentID
        view.tab = tab
        return view
    }

    func updateNSView(_ view: ParentScrollProbeView, context: Context) {
        view.parentID = parentID
        view.tab = tab
        view.scheduleAttach()
    }

    static func dismantleNSView(_ view: ParentScrollProbeView, coordinator: ()) {
        view.stop()
    }
}

@MainActor
final class ParentScrollProbeView: NSView {
    var parentID = UUID()
    var tab = "unknown"
    private weak var scroll: NSScrollView?
    private weak var clip: NSClipView?
    private weak var document: NSView?
    private weak var observedWindow: NSWindow?
    private var scrollIdentity: ObjectIdentifier?
    private var monitor: Any?
    private var attachPending = false
    private var stopped = false
    private var reportedMissing = false
    private var detector = ParentScrollJumpDetector()
    private var lastOffset: Double?
    private var lastGeometry: String?
    private var lastResponderID: ObjectIdentifier?
    private var hasSampledResponder = false
    private var lastOffsetLog: TimeInterval = -.infinity
    private var lastEventLog: [UInt: TimeInterval] = [:]

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override var acceptsFirstResponder: Bool { false }

    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        scheduleAttach()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil { detach() } else { scheduleAttach() }
    }

    func scheduleAttach() {
        guard !stopped, !attachPending else { return }
        attachPending = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.attachPending = false
            if !self.stopped { self.attach() }
        }
    }

    private func attach() {
        guard let window else { return }
        guard let next = enclosingScrollView else {
            if !reportedMissing {
                reportedMissing = true
                ParentScrollLog.write("PROBE awaiting enclosingScrollView parent=\(parentID) tab=\(tab)")
            }
            return
        }
        if scroll === next, clip === next.contentView, document === next.documentView,
           observedWindow === window {
            sample(reason: "update")
            return
        }
        detach()
        reportedMissing = false
        scroll = next
        scrollIdentity = ObjectIdentifier(next)
        clip = next.contentView
        document = next.documentView
        observedWindow = window
        ParentScrollDiagnostics.active = self
        let center = NotificationCenter.default
        next.contentView.postsBoundsChangedNotifications = true
        center.addObserver(self, selector: #selector(boundsChanged), name: NSView.boundsDidChangeNotification,
                           object: next.contentView)
        if let document = next.documentView {
            document.postsFrameChangedNotifications = true
            document.postsBoundsChangedNotifications = true
            center.addObserver(self, selector: #selector(documentChanged), name: NSView.frameDidChangeNotification,
                               object: document)
            center.addObserver(self, selector: #selector(documentChanged), name: NSView.boundsDidChangeNotification,
                               object: document)
        }
        for name in [NSWindow.didBecomeKeyNotification, NSWindow.didResignKeyNotification,
                     NSWindow.didResizeNotification, NSWindow.didMoveNotification] {
            center.addObserver(self, selector: #selector(windowChanged), name: name, object: window)
        }
        ParentScrollDiagnostics.record("ATTACH \(label) clip=\(ObjectIdentifier(next.contentView)) document=\(identity(next.documentView)) window=\(ObjectIdentifier(window)) host=\(identity(window.contentView))")
        sample(reason: "attach")
        monitor = NSEvent.addLocalMonitorForEvents(matching: [
            .scrollWheel, .tabletPoint, .tabletProximity, .leftMouseDown, .leftMouseUp,
            .rightMouseDown, .rightMouseUp, .otherMouseDown, .otherMouseUp,
            .leftMouseDragged, .rightMouseDragged, .otherMouseDragged, .keyDown
        ]) { [weak self] event in
            self?.input(event)
            return event // Observe only: exactly the original event, for mouse AND pen.
        }
    }

    func stop() {
        stopped = true
        detach()
    }

    private func detach() {
        if scrollIdentity != nil {
            ParentScrollDiagnostics.record("DETACH \(label) lastOffset=\(lastOffset.map { String($0) } ?? "nil")")
        }
        NotificationCenter.default.removeObserver(self)
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        // Don't disable notifications: other observers may still need them. These flags
        // only enable notifications and never control layout, event delivery or focus.
        if ParentScrollDiagnostics.active === self { ParentScrollDiagnostics.active = nil }
        scroll = nil
        scrollIdentity = nil
        clip = nil
        document = nil
        observedWindow = nil
        detector = ParentScrollJumpDetector()
        lastOffset = nil
        lastGeometry = nil
        lastResponderID = nil
        hasSampledResponder = false
        lastOffsetLog = -.infinity
        lastEventLog.removeAll(keepingCapacity: true)
    }

    private var label: String {
        "parent=\(parentID) tab=\(tab) scroll=\(scrollIdentity.map { String(describing: $0) } ?? "nil")"
    }

    private func identity(_ view: NSView?) -> String {
        view.map { "\(type(of: $0))@\(ObjectIdentifier($0))" } ?? "nil"
    }

    func remember(_ message: String) {
        detector.recordEvent(message, at: ProcessInfo.processInfo.systemUptime)
    }

    @objc private func boundsChanged(_ notification: Notification) { sample(reason: "bounds") }
    @objc private func documentChanged(_ notification: Notification) { sample(reason: "document") }
    @objc private func windowChanged(_ notification: Notification) {
        ParentScrollDiagnostics.record("WINDOW \(label) event=\(notification.name.rawValue) key=\(observedWindow?.isKeyWindow == true)")
        sample(reason: "window")
    }

    private func sample(reason: String) {
        guard let scroll, let document = scroll.documentView else { return }
        // Reconnect if SwiftUI replaced the document or clip within the same NSScrollView.
        guard self.document === document, clip === scroll.contentView else { scheduleAttach(); return }
        let clip = scroll.contentView
        let now = ProcessInfo.processInfo.systemUptime
        sampleResponder()
        let geometry = "documentHeight=\(document.frame.height) documentFrame=\(NSStringFromRect(document.frame)) documentBounds=\(NSStringFromRect(document.bounds)) viewport=\(NSStringFromSize(clip.bounds.size)) flipped=\(document.isFlipped)"
        if geometry != lastGeometry {
            lastGeometry = geometry
            ParentScrollDiagnostics.record("GEOMETRY \(label) reason=\(reason) \(geometry)")
        }
        // Top-relative points, including on a nonflipped AppKit document.
        let offset = Double(document.isFlipped
            ? clip.bounds.minY - document.frame.minY : document.frame.maxY - clip.bounds.maxY)
        let previous = lastOffset
        let context = detector.observe(offset: offset, at: now)
        lastOffset = offset
        if let context {
            ParentScrollLog.write("JUMP \(label) from=\(previous ?? offset) to=\(offset) delta=\(offset - (previous ?? offset)) reason=\(reason) \(geometry) responder=\(ParentScrollDiagnostics.responder(observedWindow?.firstResponder)) context=[\(context.joined(separator: " | "))]")
        }
        let bigChange = previous.map { abs(offset - $0) > 200 } ?? true
        if bigChange || (offset != previous && now - lastOffsetLog >= 0.1) {
            lastOffsetLog = now
            ParentScrollLog.write("OFFSET \(label) y=\(offset) rawY=\(clip.bounds.origin.y) previous=\(previous ?? offset) reason=\(reason)")
        }
    }

    private func sampleResponder() {
        let responder = observedWindow?.firstResponder
        let identity = responder.map { ObjectIdentifier($0) }
        guard !hasSampledResponder || identity != lastResponderID else { return }
        hasSampledResponder = true
        lastResponderID = identity
        ParentScrollDiagnostics.record("FOCUS \(label) responder=\(ParentScrollDiagnostics.responder(responder))")
    }

    private func input(_ event: NSEvent) {
        guard let observedWindow,
              event.window === observedWindow || (event.type == .tabletProximity && NSApp.keyWindow === observedWindow)
        else { return }
        let now = ProcessInfo.processInfo.systemUptime
        var wheel = ""
        var subtype = ""
        switch event.type {
        case .leftMouseDown, .leftMouseUp, .leftMouseDragged, .rightMouseDown,
             .rightMouseUp, .rightMouseDragged, .otherMouseDown, .otherMouseUp, .otherMouseDragged:
            // Pen contacts may arrive as mouse events with tabletPoint subtype.
            subtype = " subtype=\(event.subtype.rawValue)"
        default: break
        }
        if event.type == .scrollWheel {
            // AppKit's delivered delta is already in scroll direction; don't invert natural scrolling again.
            let delta = Double(event.scrollingDeltaY)
            let point = convert(event.locationInWindow, from: nil)
            // A wheel over a pinned sibling bar must not excuse a jump here. Overlays
            // can share this rectangle; TICK logs their browser/playtest state separately.
            if visibleRect.contains(point) {
                detector.recordScrollWheel(deltaY: delta, at: now)
            }
            wheel = " deltaY=\(delta) phase=\(event.phase.rawValue) momentum=\(event.momentumPhase.rawValue)"
        }
        let key = event.type.rawValue
        if now - (lastEventLog[key] ?? -.infinity) >= 0.1 {
            lastEventLog[key] = now
            ParentScrollDiagnostics.record("INPUT \(label) type=\(event.type)\(subtype) location=\(NSStringFromPoint(event.locationInWindow))\(wheel)")
        }
        sampleResponder()
    }
}
