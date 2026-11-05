import AppKit
import ObjectiveC.runtime
import VisaCore

/// Observes the existing parent scroll view; never replaces a view, changes an
/// argument/result, or sends a second copy of a native scrolling operation.
@MainActor
enum ParentScrollHooks {
    // Native wrappers can be entered outside the main thread. Their factory is
    // nonisolated so its block does not assert actor isolation before checking
    // Thread.isMainThread. State is otherwise accessed only on the main thread.
    nonisolated private static let state = State()
    private static var installed: Set<MethodKey> = []
    private static var wrapperAddresses: Set<UInt> = []
    private static let installationLimit = 96
    /// Build 78: OFF unless `ParentScrollStackHooks=true` in the app's defaults domain.
    /// Read once per launch; when off, no AppKit method is ever added or replaced.
    static let isEnabled = ParentScrollOptions.stackHooksEnabled()
    private static var reportedDisabled = false

    static var path: String { state.calls.joined(separator: " > ") }

    static func attach(clip: NSClipView, scroll: NSScrollView,
                       onBoundary: @escaping (String) -> Void,
                       onScrollerTracking: @escaping (Bool) -> Void) {
        detach()
        guard isEnabled else {
            if !reportedDisabled {
                reportedDisabled = true
                ParentScrollLog.write("HOOK disabled domain=\(ParentScrollOptions.defaultsDomain) key=\(ParentScrollOptions.stackHooksKey) (observe-only log stays on)")
            }
            return
        }
        state.matches = { [weak clip, weak scroll] receiver, role in
            switch role {
            case .clip: return receiver === clip
            case .scroll: return receiver === scroll
            case .scroller:
                // Query the current controls: AppKit can replace overlay scrollers.
                return receiver === scroll?.verticalScroller
            }
        }
        state.boundary = onBoundary
        state.scrollerTracking = onScrollerTracking

        // Add inherited methods on these AppKit classes, never on NSView or
        // NSResponder. Concrete overrides get their own wrapper; a concrete
        // class merely inheriting an installed wrapper needs no second one.
        for cls in [NSClipView.self, object_getClass(clip)].compactMap({ $0 }) {
            install(cls, "setBoundsOrigin:", role: .clip, signature: .point)
            install(cls, "scrollToPoint:", role: .clip, signature: .point)
            install(cls, "setBounds:", role: .clip, signature: .rect)
            install(cls, "constrainBoundsRect:", role: .clip, signature: .rectResult)
        }
        for cls in [NSScrollView.self, object_getClass(scroll)].compactMap({ $0 }) {
            install(cls, "reflectScrolledClipView:", role: .scroll, signature: .object)
        }
        refreshScroller(in: scroll)
    }

    /// Called before dispatching a local mouse-down in the vertical scroller, so
    /// a replacement control's concrete override is covered before tracking starts.
    static func refreshScroller(in scroll: NSScrollView) {
        guard state.matches?(scroll, .scroll) == true else { return }
        for cls in [NSScroller.self, scroll.verticalScroller.flatMap({ object_getClass($0) })].compactMap({ $0 }) {
            install(cls, "mouseDown:", role: .scroller, signature: .object)
        }
    }

    static func detach() {
        state.generation &+= 1
        state.matches = nil
        state.boundary = nil
        state.scrollerTracking = nil
        state.calls.removeAll(keepingCapacity: true)
        state.trackingDepth = 0
        // Keep wrappers installed for process lifetime. Restoring an IMP could
        // invalidate another wrapper's saved superclass implementation. When
        // detached their identity gate does no observation or stack collection.
    }

    private enum Role { case clip, scroll, scroller }
    private enum Signature { case point, rect, rectResult, object }
    private struct MethodKey: Hashable {
        let owner: ObjectIdentifier
        let selector: String
    }

    private static func install(_ cls: AnyClass, _ name: String, role: Role, signature: Signature) {
        let key = MethodKey(owner: ObjectIdentifier(cls), selector: name)
        guard !installed.contains(key), installed.count < installationLimit else { return }
        let selector = NSSelectorFromString(name)
        guard let method = class_getInstanceMethod(cls, selector),
              let types = method_getTypeEncoding(method) else { return }
        let original = method_getImplementation(method)
        if wrapperAddresses.contains(unsafeBitCast(original, to: UInt.self)) {
            return // The method is inherited from an already observed superclass.
        }
        let label = "\(NSStringFromClass(cls)).\(name)"
        let replacement: IMP
        switch signature {
        case .point: replacement = pointWrapper(original, selector, role, label)
        case .rect: replacement = rectWrapper(original, selector, role, label)
        case .rectResult: replacement = rectResultWrapper(original, selector, role, label)
        case .object: replacement = objectWrapper(original, selector, role, label)
        }
        // class_addMethod creates a local override for an inherited method. Only
        // replace after that fails, so a superclass's Method is never overwritten.
        if !class_addMethod(cls, selector, replacement, types) {
            _ = class_replaceMethod(cls, selector, replacement, types)
        }
        installed.insert(key)
        wrapperAddresses.insert(unsafeBitCast(replacement, to: UInt.self))
        ParentScrollLog.write("HOOK installed class=\(NSStringFromClass(cls)) selector=\(name)")
    }

    private typealias PointImplementation = @convention(c) (AnyObject, Selector, NSPoint) -> Void
    private typealias RectImplementation = @convention(c) (AnyObject, Selector, NSRect) -> Void
    private typealias RectResultImplementation = @convention(c) (AnyObject, Selector, NSRect) -> NSRect
    // Optional: Objective-C callers may pass nil; a non-optional Swift reference would trap.
    private typealias ObjectImplementation = @convention(c) (AnyObject, Selector, AnyObject?) -> Void

    nonisolated private static func pointWrapper(_ original: IMP, _ selector: Selector,
                                                 _ role: Role, _ label: String) -> IMP {
        let invoke = unsafeBitCast(original, to: PointImplementation.self)
        let block: @convention(block) (AnyObject, NSPoint) -> Void = { receiver, point in
            let token = state.begin(receiver, role: role, label: label)
            defer { state.end(token, label: label) }
            invoke(receiver, selector, point)
        }
        return imp_implementationWithBlock(block)
    }

    nonisolated private static func rectWrapper(_ original: IMP, _ selector: Selector,
                                                _ role: Role, _ label: String) -> IMP {
        let invoke = unsafeBitCast(original, to: RectImplementation.self)
        let block: @convention(block) (AnyObject, NSRect) -> Void = { receiver, rect in
            let token = state.begin(receiver, role: role, label: label)
            defer { state.end(token, label: label) }
            invoke(receiver, selector, rect)
        }
        return imp_implementationWithBlock(block)
    }

    nonisolated private static func rectResultWrapper(_ original: IMP, _ selector: Selector,
                                                      _ role: Role, _ label: String) -> IMP {
        let invoke = unsafeBitCast(original, to: RectResultImplementation.self)
        let block: @convention(block) (AnyObject, NSRect) -> NSRect = { receiver, rect in
            let token = state.begin(receiver, role: role, label: label)
            defer { state.end(token, label: label) }
            return invoke(receiver, selector, rect)
        }
        return imp_implementationWithBlock(block)
    }

    nonisolated private static func objectWrapper(_ original: IMP, _ selector: Selector,
                                                  _ role: Role, _ label: String) -> IMP {
        let invoke = unsafeBitCast(original, to: ObjectImplementation.self)
        let block: @convention(block) (AnyObject, AnyObject?) -> Void = { receiver, argument in
            let token = state.begin(receiver, role: role, label: label)
            defer { state.end(token, label: label) }
            invoke(receiver, selector, argument)
        }
        return imp_implementationWithBlock(block)
    }

    /// Native IMP blocks do a thread check before any mutable access. This holder
    /// and its ordinary (non-Sendable) callbacks are manually main-thread-confined;
    /// the unchecked conformance only permits the native wrapper to reference it.
    private final class State: @unchecked Sendable {
        var matches: ((AnyObject, Role) -> Bool)?
        var boundary: ((String) -> Void)?
        var scrollerTracking: ((Bool) -> Void)?
        var calls: [String] = []
        var trackingDepth = 0
        var generation: UInt64 = 0
        private var notifying = false

        struct Token {
            let generation: UInt64
            let tracking: Bool
        }

        func begin(_ receiver: AnyObject, role: Role, label: String) -> Token? {
            guard Thread.isMainThread, !notifying, calls.count < 16,
                  matches?(receiver, role) == true else { return nil }
            let tracking = role == .scroller
            let token = Token(generation: generation, tracking: tracking)
            calls.append(label)
            if tracking {
                trackingDepth += 1
                if trackingDepth == 1 { notify { scrollerTracking?(true) } }
            }
            guard token.generation == generation else { return nil }
            notify { boundary?("enter \(label)") }
            return token
        }

        func end(_ token: Token?, label: String) {
            guard let token, Thread.isMainThread, token.generation == generation else { return }
            notify { boundary?("exit \(label)") }
            guard token.generation == generation else { return }
            if token.tracking {
                trackingDepth -= 1
                if trackingDepth == 0 { notify { scrollerTracking?(false) } }
            }
            guard token.generation == generation else { return }
            if !calls.isEmpty { calls.removeLast() }
        }

        private func notify(_ callback: () -> Void) {
            guard !notifying else { return }
            notifying = true
            defer { notifying = false }
            callback()
        }
    }
}
