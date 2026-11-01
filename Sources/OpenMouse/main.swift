import AppKit
import SwiftUI
import ApplicationServices
import OpenMouseCore

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var store: SettingsStore!
    private var statusItem: NSStatusItem!
    private var window: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "io.github.mauriciogoulartt.open-mouse")
            .filter({ $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }).isEmpty else {
            NSApplication.shared.terminate(nil); return
        }
        store = SettingsStore()
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "computermouse", accessibilityDescription: "Open Mouse")
        let menu = NSMenu()
        menu.addItem(withTitle: "Open Mouse…", action: #selector(openSettings), keyEquivalent: ",").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Ativar / desativar", action: #selector(toggleEnabled), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Pausar rolagem", action: #selector(toggleScroll), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Pausar botões", action: #selector(toggleButtons), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Encerrar Open Mouse", action: #selector(quit), keyEquivalent: "q").target = self
        statusItem.menu = menu
        if !CommandLine.arguments.contains("--background") { openSettings() }
    }

    @objc func openSettings() {
        if window == nil {
            let value = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 850, height: 640),
                styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
            value.title = "Open Mouse"; value.isReleasedWhenClosed = false; value.delegate = self
            value.contentView = NSHostingView(rootView: SettingsView(store: store))
            value.center(); window = value
        }
        NSApplication.shared.activate(ignoringOtherApps: true); window?.makeKeyAndOrderFront(nil)
    }
    @objc private func toggleEnabled() { store.update { $0.enabled.toggle() } }
    @objc private func toggleScroll() { store.update { $0.scrollEnabled.toggle() } }
    @objc private func toggleButtons() { store.update { $0.buttonsEnabled.toggle() } }
    @objc private func quit() { store.engine.stop(); NSApplication.shared.terminate(nil) }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationWillTerminate(_ notification: Notification) { store?.engine.stop() }
}

if let index = CommandLine.arguments.firstIndex(of: "--render-preview"), CommandLine.arguments.count > index + 1 {
    renderPreviews(to: URL(fileURLWithPath: CommandLine.arguments[index + 1], isDirectory: true))
} else if CommandLine.arguments.contains("--check-native-events") {
    do { for check in try verifyNativeEvents() { print("PASS: \(check)") } }
    catch { fputs("FAIL: \(error.localizedDescription)\n", stderr); exit(1) }
} else if CommandLine.arguments.contains("--diagnose") {
    let info: [String: Any] = [
        "name": "Open Mouse", "version": "0.1.0", "accessibility": AXIsProcessTrusted(),
        "inputMonitoring": CGPreflightListenEventAccess(), "macOS": ProcessInfo.processInfo.operatingSystemVersionString,
        "interceptionStarted": false
    ]
    if let data = try? JSONSerialization.data(withJSONObject: info, options: [.prettyPrinted, .sortedKeys]) {
        print(String(decoding: data, as: UTF8.self))
    }
} else {
    let application = NSApplication.shared
    let delegate = AppDelegate()
    application.delegate = delegate
    application.setActivationPolicy(.accessory)
    application.run()
}
