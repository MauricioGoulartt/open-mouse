import AppKit

enum AppBrand {
    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.1"
    }

    static var build: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "local"
    }

    static let icon: NSImage = {
        if let url = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
           let image = NSImage(contentsOf: url) { return image }
        return NSImage(systemSymbolName: "computermouse.fill", accessibilityDescription: "Open Mouse") ?? NSImage()
    }()
}
