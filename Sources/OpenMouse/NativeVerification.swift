import AppKit
import SwiftUI
import OpenMouseCore

/// These checks construct events and inspect their wire representation. They
/// never post to the session and never create an event tap or request permission.
func verifyNativeEvents() throws -> [String] {
    struct Failure: LocalizedError {
        let text: String
        var errorDescription: String? { text }
    }
    func require(_ condition: @autoclosure () -> Bool, _ text: String) throws {
        if !condition() { throw Failure(text: text) }
    }
    var events: [(CGEvent, CGEventTapLocation)] = []
    let emitter = ActionEmitter(eventSink: { event, tap in events.append((event, tap)) })
    func integer(_ index: Int, _ field: UInt32) -> Int64 { events[index].0.getIntegerValueField(CGEventField(rawValue: field)!) }
    emitter.perform(MouseAction(.smartZoom))
    try require(events.count == 1 && integer(0, 110) == 22, "Smart Zoom lost its documented HID subtype")
    try require(NSEvent(cgEvent: events[0].0)?.type == .smartMagnify, "AppKit did not decode Smart Zoom")
    var checks = ["Smart Zoom decodes in AppKit"]
    events.removeAll()
    let zoom = MouseAction(.zoom)
    emitter.apply([.begin(zoom), .change(zoom, ScrollVector(y: -10)), .end(zoom)])
    try require(events.count == 5, "Pinch sequence does not contain its begin/end brackets")
    try require(integer(1, 132) == 1 && integer(2, 132) == 2 && integer(3, 132) == 4, "Pinch CG phases differ from the protocol")
    try require(NSEvent(cgEvent: events[2].0)?.type == .magnify, "AppKit did not decode magnification")
    try require(abs((NSEvent(cgEvent: events[2].0)?.magnification ?? 0) - 0.08) < 0.00001, "Pinch magnitude was lost")
    checks.append("Pinch phases and magnitude decode in AppKit")
    events.removeAll()
    let drag = MouseAction(.spacesAndMissionControl)
    emitter.apply([.begin(drag), .change(drag, ScrollVector(x: 100)), .change(drag, ScrollVector(x: -50)), .cancel(drag)])
    try require(events.count == 4, "DockSwipe sequence is incomplete")
    try require(events.allSatisfy { $0.0.type.rawValue == 30 }, "DockSwipe was not dispatched as a real DockControl CGEvent")
    try require(integer(0, 55) == 30 && integer(0, 110) == 23, "DockSwipe event type/subtype was lost")
    try require(integer(0, 132) == 1 && integer(1, 132) == 2 && integer(3, 132) == 8, "DockSwipe cancellation would commit the gesture")
    try require(events.allSatisfy { $0.1 == .cgSessionEventTap }, "DockSwipe must use the session tap")
    let progress = events[2].0.getDoubleValueField(CGEventField(rawValue: 124)!)
    let bits = Int32(truncatingIfNeeded: integer(2, 135))
    try require(abs(Double(Float(bitPattern: UInt32(bitPattern: bits))) - progress) < 0.00001, "DockSwipe Float32 payload is invalid")
    checks.append("DockSwipe progress, reversal and cancellation preserve wire fields")
    events.removeAll()
    let pinchDock = MouseAction(.desktopAndLaunchpad)
    emitter.apply([.begin(pinchDock), .change(pinchDock, ScrollVector(y: 3)), .end(pinchDock)])
    try require(events.count == 3 && integer(0, 123) == 3, "Four-finger Dock pinch lost its scale motion")
    try require(events.allSatisfy { $0.0.type.rawValue == 30 }, "Four-finger pinch was not dispatched as a real DockControl CGEvent")
    try require(integer(0, 132) == 1 && integer(1, 132) == 2 && integer(2, 132) == 4, "Four-finger Dock pinch phases are incomplete")
    checks.append("Four-finger Dock pinch uses scale motion and complete phases")
    events.removeAll()
    emitter.scroll(ScrollVector(x: 2.5, y: -3.5), phase: 1)
    try require(events.count == 1 && integer(0, 88) == 1 && integer(0, 99) == 1, "Pixel scroll framing is invalid")
    try require(abs(events[0].0.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1) + 3.5) < 0.0001, "Fractional scroll was lost")
    checks.append("Pixel scroll preserves phase and fractional precision")
    return checks
}

func renderPreviews(to directory: URL) {
    let application = NSApplication.shared
    application.setActivationPolicy(.prohibited)
    let scratch = FileManager.default.temporaryDirectory.appendingPathComponent("open-mouse-preview-\(UUID())")
    let store = SettingsStore(directory: scratch)
    let sections = ["Geral", "Rolagem", "Botões", "Permissões", "Sobre"]
    var index = 0
    let window = NSWindow(contentRect: NSRect(x: -10000, y: -10000, width: 900, height: 680),
                          styleMask: [.titled, .resizable], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    func next() {
        guard index < sections.count else {
            store.engine.stop(); try? FileManager.default.removeItem(at: scratch)
            exit(0)
        }
        let section = sections[index]
        let view = NSHostingView(rootView: SettingsView(store: store, initialSection: section))
        window.contentView = view
        view.frame = NSRect(x: 0, y: 0, width: 900, height: 680)
        view.layoutSubtreeIfNeeded()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { exit(1) }
            view.cacheDisplay(in: view.bounds, to: bitmap)
            do {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                let flattened = NSImage(size: view.bounds.size)
                flattened.lockFocus()
                NSColor.windowBackgroundColor.setFill(); view.bounds.fill()
                bitmap.draw(in: view.bounds)
                flattened.unlockFocus()
                guard let tiff = flattened.tiffRepresentation, let output = NSBitmapImageRep(data: tiff),
                      let data = output.representation(using: .png, properties: [:]) else { exit(1) }
                let target = directory.appendingPathComponent("\(index)-\(section).png")
                try data.write(to: target); print(target.path)
            } catch { fputs("\(error)\n", stderr); exit(1) }
            index += 1; next()
        }
    }
    DispatchQueue.main.async { next() }
    application.run()
}
