import AppKit
import Combine
import ServiceManagement
import UniformTypeIdentifiers
import OpenMouseCore

final class SettingsStore: ObservableObject {
    @Published private(set) var configuration: Configuration
    @Published var status = "Desativado"
    @Published var error: String?
    @Published var accessibilityGranted = AXIsProcessTrusted()
    @Published var loginEnabled = SMAppService.mainApp.status == .enabled
    @Published var capturedButton: Int?
    let engine = MouseEngine()
    let fileURL: URL
    private var unreadableConfiguration = false
    private var permissionTimer: Timer?

    init(directory: URL? = nil) {
        let root = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("OpenMouse", isDirectory: true)
        fileURL = root.appendingPathComponent("settings.json")
        var initial = Configuration()
        var loadError: String?
        if FileManager.default.fileExists(atPath: fileURL.path) {
            do { initial = try ConfigurationFile.decode(Data(contentsOf: fileURL)) }
            catch {
                unreadableConfiguration = true
                loadError = "Os ajustes não puderam ser lidos. O arquivo foi preservado. Importe um arquivo válido ou restaure os padrões. \(error.localizedDescription)"
            }
        }
        configuration = initial
        self.error = loadError
        engine.onStatus = { [weak self] text in self?.status = text }
        engine.onButton = { [weak self] button, _, _ in self?.capturedButton = button }
        engine.configure(initial)
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            guard let self else { return }
            let trusted = AXIsProcessTrusted()
            if trusted != self.accessibilityGranted {
                self.accessibilityGranted = trusted
                self.engine.configure(self.configuration)
            }
        }
    }

    deinit { permissionTimer?.invalidate() }

    func update(_ change: (inout Configuration) -> Void) {
        guard !unreadableConfiguration else {
            error = "O arquivo de ajustes atual está preservado. Importe ajustes válidos ou restaure os padrões antes de editar."; return
        }
        var candidate = configuration; change(&candidate)
        do {
            try ConfigurationFile.save(candidate, to: fileURL)
            configuration = candidate; engine.configure(candidate)
        } catch { self.error = error.localizedDescription }
    }

    func restoreDefaults() {
        do {
            if FileManager.default.fileExists(atPath: fileURL.path) {
                let backup = fileURL.deletingLastPathComponent().appendingPathComponent("settings-backup-\(UUID().uuidString).json")
                try FileManager.default.copyItem(at: fileURL, to: backup)
            }
            let defaults = Configuration()
            try ConfigurationFile.save(defaults, to: fileURL)
            unreadableConfiguration = false; configuration = defaults; engine.configure(defaults)
        } catch { self.error = error.localizedDescription }
    }

    func importSettings() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.json]; panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            var candidate = try ConfigurationFile.decode(Data(contentsOf: url))
            // Importing a preset never silently starts intercepting input.
            candidate.enabled = false
            if FileManager.default.fileExists(atPath: fileURL.path) {
                try FileManager.default.copyItem(at: fileURL,
                    to: fileURL.deletingLastPathComponent().appendingPathComponent("settings-backup-\(UUID().uuidString).json"))
            }
            try ConfigurationFile.save(candidate, to: fileURL)
            unreadableConfiguration = false; configuration = candidate; engine.configure(candidate)
        } catch { self.error = error.localizedDescription }
    }

    func exportSettings() {
        let panel = NSSavePanel(); panel.allowedContentTypes = [.json]; panel.nameFieldStringValue = "open-mouse-settings.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try ConfigurationFile.encode(configuration).write(to: url, options: .atomic) }
        catch { self.error = error.localizedDescription }
    }

    func setLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            loginEnabled = SMAppService.mainApp.status == .enabled
            if SMAppService.mainApp.status == .requiresApproval {
                error = "Autorize o Open Mouse em Geral → Itens de Início nos Ajustes do Sistema."
            }
        } catch { self.error = error.localizedDescription }
    }

    func openAccessibilitySettings() {
        engine.requestAccessibility()
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}
