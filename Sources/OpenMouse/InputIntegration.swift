import AppKit
import ApplicationServices
import OpenMouseCore

private final class InputProbe: NSView {
    var keys: [UInt16] = []
    var scrollTotal: Double = 0
    var scrollCount = 0
    var smartZoomCount = 0
    var magnifyCount = 0
    var recognizedMagnifyCount = 0
    override var acceptsFirstResponder: Bool { true }
    override init(frame: NSRect) {
        super.init(frame: frame)
        addGestureRecognizer(NSMagnificationGestureRecognizer(target: self, action: #selector(recognizedMagnify)))
    }
    required init?(coder: NSCoder) { nil }
    override func draw(_ dirtyRect: NSRect) { NSColor.windowBackgroundColor.setFill(); dirtyRect.fill() }
    override func keyDown(with event: NSEvent) { keys.append(event.keyCode) }
    override func scrollWheel(with event: NSEvent) { scrollTotal += event.scrollingDeltaY; scrollCount += 1 }
    override func smartMagnify(with event: NSEvent) { smartZoomCount += 1 }
    override func magnify(with event: NSEvent) { magnifyCount += 1 }
    @objc private func recognizedMagnify(_ recognizer: NSMagnificationGestureRecognizer) { recognizedMagnifyCount += 1 }
}

/// A hosted runner owns the whole temporary desktop. This mode is deliberately
/// unavailable during normal local use: it posts input only into its fixture.
func runInputIntegration() {
    guard ProcessInfo.processInfo.environment["GITHUB_ACTIONS"] == "true",
          ProcessInfo.processInfo.environment["OPEN_MOUSE_ISOLATED_TEST"] == "1" else {
        fputs("This check requires an explicitly isolated GitHub runner.\n", stderr); exit(1)
    }
    guard AXIsProcessTrusted() else { fputs("The isolated runner lacks Accessibility permission.\n", stderr); exit(1) }
    let app = NSApplication.shared
    app.setActivationPolicy(.regular)
    let window = NSWindow(contentRect: NSRect(x: 150, y: 150, width: 460, height: 300),
                          styleMask: [.titled], backing: .buffered, defer: false)
    window.title = "Open Mouse — isolated input fixture"
    window.isReleasedWhenClosed = false
    let probe = InputProbe(frame: NSRect(x: 0, y: 0, width: 460, height: 300))
    window.contentView = probe
    window.makeKeyAndOrderFront(nil); app.activate(ignoringOtherApps: true); window.makeFirstResponder(probe)
    let source = CGEventSource(stateID: .combinedSessionState)
    let previousCursor = CGEvent(source: nil)?.location ?? .zero
    let screenHeight = NSScreen.screens.first?.frame.height ?? 900
    let point = CGPoint(x: window.frame.midX, y: screenHeight - window.frame.midY)
    let engine = MouseEngine()
    var config = Configuration(); config.enabled = true; config.doubleClickInterval = 0.12; config.holdDelay = 0.15
    config.mappings = [
        Mapping(button: 3, trigger: .click, action: MouseAction(.keyboardShortcut, keyCode: 0)),
        Mapping(button: 3, trigger: .doubleClick, action: MouseAction(.keyboardShortcut, keyCode: 8)),
        Mapping(button: 3, trigger: .hold, action: MouseAction(.keyboardShortcut, keyCode: 11))
    ]
    let emitter = ActionEmitter()
    var passed: [String] = []
    var finished = false
    func finish(_ error: String? = nil) {
        guard !finished else { return }; finished = true
        engine.stop(); window.orderOut(nil)
        CGWarpMouseCursorPosition(previousCursor)
        if let error { fputs("FAIL: \(error)\n", stderr); exit(1) }
        passed.forEach { print("PASS: \($0)") }
        print("Magnify recognizer callbacks: \(probe.recognizedMagnifyCount)")
        exit(0)
    }
    func button(_ down: Bool) {
        let event = CGEvent(mouseEventSource: source, mouseType: down ? .otherMouseDown : .otherMouseUp,
                            mouseCursorPosition: point, mouseButton: .center)
        event?.setIntegerValueField(.eventSourceUserData, value: 0x4F4D54455354)
        event?.post(tap: .cghidEventTap)
    }
    func wheel(_ value: Int32, pixel: Bool = false) {
        let event = CGEvent(scrollWheelEvent2Source: source, units: pixel ? .pixel : .line,
                            wheelCount: 1, wheel1: value, wheel2: 0, wheel3: 0)
        event?.location = point
        event?.setIntegerValueField(.eventSourceUserData, value: 0x4F4D54455354)
        event?.post(tap: .cghidEventTap)
    }
    func after(_ seconds: Double, _ action: @escaping () -> Void) { DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: action) }
    after(0.3) {
        CGWarpMouseCursorPosition(point); window.makeFirstResponder(probe); engine.configure(config)
        guard engine.isRunning else { finish("Real event tap failed to start"); return }
        button(true); after(0.02) { button(false) }
        after(0.3) {
            guard probe.keys == [0] else { finish("Single click did not reach the real responder exactly once: \(probe.keys)"); return }
            passed.append("Mouse event tap → single-click mapping → real key responder")
            button(true); after(0.02) { button(false) }; after(0.06) { button(true) }; after(0.08) { button(false) }
            after(0.3) {
                guard probe.keys == [0, 8] else { finish("Double click leaked a single click: \(probe.keys)"); return }
                passed.append("Double click reaches real responder without leaking a single click")
                button(true); after(0.22) { button(false) }
                after(0.4) {
                    guard probe.keys == [0, 8, 11] else { finish("Hold did not reach the real responder exactly once: \(probe.keys)"); return }
                    passed.append("Hold reaches real responder and suppresses click")
                    wheel(3)
                    after(0.7) {
                        guard probe.scrollTotal > 45 && probe.scrollTotal < 51 && probe.scrollCount > 2 else {
                            finish("Smooth wheel did not reach fixture with conserved displacement: \(probe.scrollTotal), \(probe.scrollCount)"); return
                        }
                        passed.append("Physical-style wheel → real tap → phased smooth pixel events → responder")
                        let before = probe.scrollTotal
                        config.scroll.inverted = true; engine.configure(config); wheel(3)
                        after(0.7) {
                            let inverted = probe.scrollTotal - before
                            guard inverted < -45 && inverted > -51 else { finish("Inverted wheel displacement was \(inverted)"); return }
                            passed.append("Direction inversion reaches the real responder")
                            let trackpadBefore = probe.scrollTotal; wheel(5, pixel: true)
                            after(0.15) {
                                guard abs(probe.scrollTotal - trackpadBefore - 5) < 0.1 else { finish("Unknown continuous/trackpad event was modified"); return }
                                passed.append("Unknown continuous/trackpad input passes through unchanged")
                                engine.stop()
                                emitter.perform(MouseAction(.smartZoom))
                                let zoom = MouseAction(.zoom)
                                after(0.1) { emitter.apply([.begin(zoom)]) }
                                after(0.15) { emitter.apply([.change(zoom, ScrollVector(y: -10))]) }
                                after(0.2) { emitter.apply([.end(zoom)]) }
                                after(0.5) {
                                    guard probe.smartZoomCount > 0 else { finish("Smart Zoom was not delivered globally to the fixture"); return }
                                    guard probe.magnifyCount > 0 || probe.recognizedMagnifyCount > 0 else { finish("Pinch was not delivered globally to the fixture"); return }
                                    passed.append("Smart Zoom and pinch are delivered through the session to the owned native view")
                                    finish()
                                }
                            }
                        }
                    }
                }
            }
        }
    }
    after(15) { finish("Isolated native input verification timed out") }
    app.run()
}
