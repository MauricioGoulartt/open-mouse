import AppKit
import ApplicationServices
import OpenMouseCore

/// Separate, explicitly requested CI lane: posts gestures only on an ephemeral
/// hosted desktop, records the Dock's visible windows, and dismisses its UI.
func runSystemGestureProbe() {
    guard ProcessInfo.processInfo.environment["GITHUB_ACTIONS"] == "true",
          ProcessInfo.processInfo.environment["OPEN_MOUSE_ISOLATED_TEST"] == "1",
          AXIsProcessTrusted() else {
        fputs("System gesture checks require an isolated, authorized hosted desktop.\n", stderr); exit(1)
    }
    let app = NSApplication.shared; app.setActivationPolicy(.regular)
    let window = NSWindow(contentRect: NSRect(x: 180, y: 180, width: 500, height: 300),
                          styleMask: [.titled, .closable], backing: .buffered, defer: false)
    window.title = "Open Mouse system gesture fixture"; window.isReleasedWhenClosed = false
    let label = NSTextField(labelWithString: "Open Mouse · isolated native gesture verification")
    label.frame = NSRect(x: 24, y: 130, width: 460, height: 40); window.contentView?.addSubview(label)
    window.makeKeyAndOrderFront(nil); app.activate(ignoringOtherApps: true)
    let emitter = ActionEmitter()
    var finished = false
    var results: [[String: Any]] = []
    func windows() -> [[String: Any]] {
        let rows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        return rows.filter { $0[kCGWindowOwnerName as String] as? String == "Dock" }.map {
            ["name": $0[kCGWindowName as String] as? String ?? "", "layer": $0[kCGWindowLayer as String] ?? 0,
             "number": $0[kCGWindowNumber as String] ?? 0, "bounds": $0[kCGWindowBounds as String] ?? [:]]
        }
    }
    func finish(_ error: String? = nil) {
        guard !finished else { return }; finished = true
        emitter.keyboard(code: 53); window.orderOut(nil)
        if let data = try? JSONSerialization.data(withJSONObject: results, options: [.prettyPrinted, .sortedKeys]) {
            print(String(decoding: data, as: UTF8.self))
        }
        if let error { fputs("FAIL: \(error)\n", stderr); exit(1) }; exit(0)
    }
    func after(_ seconds: Double, _ action: @escaping () -> Void) { DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: action) }
    let cases: [(String, MouseAction, ScrollVector)] = [
        ("vertical-dock", MouseAction(.spacesAndMissionControl), ScrollVector(y: -200)),
        ("four-finger-pinch", MouseAction(.desktopAndLaunchpad), ScrollVector(y: 18))
    ]
    var index = 0
    func next() {
        guard index < cases.count else { finish(); return }
        let item = cases[index]; let before = windows()
        emitter.apply([.begin(item.1)])
        for step in 1...12 {
            after(Double(step) * 0.025) { emitter.apply([.change(item.1, ScrollVector(x: item.2.x / 12, y: item.2.y / 12))]) }
        }
        after(0.35) { emitter.apply([.end(item.1)]) }
        after(1) {
            let afterWindows = windows()
            let changed = Set(before.compactMap { $0["number"] as? Int }) != Set(afterWindows.compactMap { $0["number"] as? Int })
            results.append(["case": item.0, "before": before, "after": afterWindows, "visibleDockWindowsChanged": changed])
            emitter.keyboard(code: 53)
            after(0.6) {
                guard changed else { finish("The \(item.0) gesture did not produce an observable Dock transition"); return }
                index += 1; window.makeKeyAndOrderFront(nil); app.activate(ignoringOtherApps: true)
                after(0.3) { next() }
            }
        }
    }
    after(0.5) { next() }; after(15) { finish("System gesture verification timed out") }
    app.run()
}
