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
    func dockAccessibility() -> (ids: Set<String>, tree: [[String: String]]) {
        guard let dock = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first else { return ([], []) }
        let root = AXUIElementCreateApplication(dock.processIdentifier)
        var ids = Set<String>(), tree: [[String: String]] = []
        func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
            var value: CFTypeRef?
            return AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success ? value : nil
        }
        func visit(_ element: AXUIElement, depth: Int) {
            guard depth < 7, tree.count < 250 else { return }
            var row: [String: String] = [:]
            for key in ["AXRole", "AXSubrole", "AXIdentifier", "AXTitle", "AXDescription"] {
                if let text = attribute(element, key) as? String { row[key] = text }
            }
            if let identifier = row["AXIdentifier"] { ids.insert(identifier.lowercased()) }
            row["depth"] = String(depth); tree.append(row)
            for child in attribute(element, "AXChildren") as? [AXUIElement] ?? [] { visit(child, depth: depth + 1) }
        }
        visit(root, depth: 0)
        return (ids, tree)
    }
    func fixtureOnScreen() -> Bool {
        let rows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        return rows.contains { ($0[kCGWindowNumber as String] as? Int) == window.windowNumber }
    }
    func fixtureInfo() -> [[String: Any]] {
        let rows = CGWindowListCopyWindowInfo(.optionAll, kCGNullWindowID) as? [[String: Any]] ?? []
        return rows.filter { ($0[kCGWindowNumber as String] as? Int) == window.windowNumber }
    }
    func elementAtFixtureCenter() -> [String: String] {
        let center = CGPoint(x: window.frame.midX,
                             y: CGDisplayBounds(CGMainDisplayID()).maxY - window.frame.midY)
        var element: AXUIElement?
        guard AXUIElementCopyElementAtPosition(AXUIElementCreateSystemWide(), Float(center.x), Float(center.y), &element) == .success,
              let element else { return [:] }
        var pid: pid_t = 0
        AXUIElementGetPid(element, &pid)
        var result = ["bundle": NSRunningApplication(processIdentifier: pid)?.bundleIdentifier ?? ""]
        for key in ["AXRole", "AXIdentifier", "AXTitle", "AXDescription", "AXValue"] {
            var value: CFTypeRef?
            if AXUIElementCopyAttributeValue(element, key as CFString, &value) == .success,
               let value = value as? String { result[key] = value }
        }
        return result
    }
    func capture(_ name: String) {
        // This command is guarded above and runs only on the disposable CI
        // desktop containing this fixture, never on the user's desktop.
        let directory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("dist/system-probe")
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let process = Process(); process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        process.arguments = ["-x", directory.appendingPathComponent("\(name).png").path]
        try? process.run(); process.waitUntilExit()
    }
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
        ("four-finger-pinch-apps", MouseAction(.desktopAndLaunchpad), ScrollVector(y: 18)),
        ("four-finger-pinch-desktop", MouseAction(.desktopAndLaunchpad), ScrollVector(y: -18))
    ]
    var index = 0
    func next() {
        guard index < cases.count else { finish(); return }
        let item = cases[index]; let before = windows(); let beforeAX = dockAccessibility()
        let beforeFixture = fixtureInfo()
        let beforeElement = elementAtFixtureCenter()
        emitter.apply([.begin(item.1)])
        for step in 1...12 {
            after(Double(step) * 0.025) { emitter.apply([.change(item.1, ScrollVector(x: item.2.x / 12, y: item.2.y / 12))]) }
        }
        after(0.35) { emitter.apply([.end(item.1)]) }
        after(1) {
            let afterWindows = windows()
            let afterAX = dockAccessibility()
            let newIDs = afterAX.ids.subtracting(beforeAX.ids)
            let missionControl = afterAX.ids.contains("mc") || newIDs.contains { $0.contains("mission") || $0.hasPrefix("mc.") }
            let launchpad = newIDs.contains { $0.contains("launchpad") || $0 == "lp" || $0.hasPrefix("lp.") }
            let afterElement = elementAtFixtureCenter()
            // Apps on macOS 26 is a nonactivating Spotlight panel. It does not
            // appear in the Dock AX tree or change frontmostApplication.
            let apps = beforeElement["bundle"] != "com.apple.Spotlight" && afterElement["bundle"] == "com.apple.Spotlight"
            let desktop = !fixtureOnScreen() || (beforeElement["bundle"] == Bundle.main.bundleIdentifier && afterElement["bundle"] == "com.apple.finder")
            let changed = item.0 == "vertical-dock" ? missionControl :
                (item.0 == "four-finger-pinch-apps" ? launchpad || apps : desktop)
            capture(item.0)
            results.append(["case": item.0, "before": before, "after": afterWindows,
                            "beforeAX": beforeAX.tree, "afterAX": afterAX.tree,
                            "beforeFixture": beforeFixture, "afterFixture": fixtureInfo(),
                            "beforeElement": beforeElement, "afterElement": afterElement,
                            "frontmostBundle": NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "",
                            "missionControlVisible": missionControl, "launchpadVisible": launchpad, "appsVisible": apps,
                            "fixtureHiddenByShowDesktop": desktop, "semanticTransitionObserved": changed])
            emitter.keyboard(code: 53)
            after(0.6) {
                guard changed else { finish("The \(item.0) gesture did not produce an observable Dock transition"); return }
                index += 1; window.makeKeyAndOrderFront(nil); app.activate(ignoringOtherApps: true)
                after(0.3) { next() }
            }
        }
    }
    // A positive control separates unsupported/misobserved hosted desktops from
    // a failed synthetic gesture. This launches Apple's own Mission Control UI.
    func missionControlControl() {
        let control = URL(fileURLWithPath: "/System/Applications/Mission Control.app")
        guard FileManager.default.fileExists(atPath: control.path) else { finish("Mission Control positive-control application is absent"); return }
        NSWorkspace.shared.openApplication(at: control, configuration: .init())
        after(1) {
            let observed = dockAccessibility()
            let visible = observed.ids.contains("mc") || observed.ids.contains { $0.hasPrefix("mc.") || $0.contains("mission") }
            results.append(["case": "mission-control-positive-control", "missionControlVisible": visible, "afterAX": observed.tree])
            emitter.keyboard(code: 53)
            after(0.7) {
                guard visible else { finish("The hosted desktop/observer did not detect Apple's own Mission Control UI"); return }
                window.makeKeyAndOrderFront(nil); app.activate(ignoringOtherApps: true)
                after(0.3) { next() }
            }
        }
    }
    after(0.5) {
        let beforeFixture = fixtureInfo()
        emitter.perform(MouseAction(.showDesktop))
        after(1) {
            capture("show-desktop-positive-control")
            results.append(["case": "show-desktop-positive-control", "beforeFixture": beforeFixture,
                            "afterFixture": fixtureInfo(), "fixtureHiddenByShowDesktop": !fixtureOnScreen(),
                            "afterAX": dockAccessibility().tree])
            emitter.perform(MouseAction(.showDesktop))
            after(0.8) {
                window.makeKeyAndOrderFront(nil); app.activate(ignoringOtherApps: true)
                after(0.3) { missionControlControl() }
            }
        }
    }
    after(20) { finish("System gesture verification timed out") }
    app.run()
}
