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
    @Published var automaticUpdateChecks = UserDefaults.standard.object(forKey: "OpenMouseAutomaticUpdateChecks") as? Bool ?? true {
        didSet { UserDefaults.standard.set(automaticUpdateChecks, forKey: "OpenMouseAutomaticUpdateChecks") }
    }
    @Published var includePrereleases = UserDefaults.standard.bool(forKey: "OpenMouseIncludePrereleases") {
        didSet { UserDefaults.standard.set(includePrereleases, forKey: "OpenMouseIncludePrereleases") }
    }
    @Published var updateStatus = "Verifique as versões publicadas no GitHub."
    @Published var availableRelease: URL?
    @Published var checkingUpdates = false
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

    func checkForUpdates(manual: Bool = true) {
        guard !checkingUpdates else { return }
        if !manual {
            guard automaticUpdateChecks else { return }
            let previous = UserDefaults.standard.double(forKey: "OpenMouseLastUpdateCheck")
            guard Date().timeIntervalSince1970 - previous >= 86400 else { return }
        }
        checkingUpdates = true; updateStatus = "Verificando atualizações…"
        let allowPrereleases = includePrereleases
        Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.checkingUpdates = false }
            struct Release: Decodable {
                let tag_name: String
                let html_url: String
                let draft: Bool
                let prerelease: Bool
            }
            do {
                let url = URL(string: "https://api.github.com/repos/MauricioGoulartt/open-mouse/releases?per_page=30")!
                var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
                request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
                request.setValue("OpenMouse/\(AppBrand.version)", forHTTPHeaderField: "User-Agent")
                let (data, response) = try await URLSession.shared.data(for: request)
                guard (response as? HTTPURLResponse)?.statusCode == 200, data.count <= 4_000_000 else {
                    self.updateStatus = "Não foi possível consultar as versões. Tente novamente mais tarde."; return
                }
                let releases = try JSONDecoder().decode([Release].self, from: data)
                let candidates = releases.filter { !$0.draft && (allowPrereleases || !$0.prerelease) }.compactMap { release -> (ReleaseVersion, Release)? in
                    guard let version = ReleaseVersion(release.tag_name) else { return nil }; return (version, release)
                }
                let newest = candidates.max { $0.0 < $1.0 }
                let current = ReleaseVersion(AppBrand.version)!
                self.availableRelease = nil
                if let newest, newest.0 > current,
                   let target = URL(string: newest.1.html_url), target.scheme == "https", target.host == "github.com",
                   target.path.hasPrefix("/MauricioGoulartt/open-mouse/releases/") {
                    self.availableRelease = target; self.updateStatus = "Nova versão disponível: \(newest.1.tag_name)."
                } else {
                    self.updateStatus = candidates.isEmpty ? "Ainda não há versões publicadas. Você está usando a versão de desenvolvimento." : "Você está usando a versão mais recente deste canal."
                }
                UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "OpenMouseLastUpdateCheck")
            } catch { self.updateStatus = "Não foi possível verificar atualizações: \(error.localizedDescription)" }
        }
    }
}
