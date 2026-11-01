import Foundation

public enum Smoothing: String, Codable, CaseIterable, Identifiable {
    case off, regular, high
    public var id: Self { self }
    public var title: String {
        switch self { case .off: return "Desligada"; case .regular: return "Normal"; case .high: return "Alta" }
    }
    public var response: Double { self == .high ? 0.105 : 0.055 }
}

public struct Modifiers: OptionSet, Codable, Hashable {
    public let rawValue: UInt64
    public init(rawValue: UInt64) { self.rawValue = rawValue }
    public static let shift = Self(rawValue: 1 << 17)
    public static let control = Self(rawValue: 1 << 18)
    public static let option = Self(rawValue: 1 << 19)
    public static let command = Self(rawValue: 1 << 20)
    public static let supported: Self = [.shift, .control, .option, .command]
    public var title: String {
        var value = ""
        if contains(.control) { value += "⌃" }
        if contains(.option) { value += "⌥" }
        if contains(.shift) { value += "⇧" }
        if contains(.command) { value += "⌘" }
        return value
    }
}

public enum Trigger: String, Codable, CaseIterable, Identifiable {
    case click, doubleClick, tripleClick, hold, drag, scroll
    public var id: Self { self }
    public var title: String {
        switch self {
        case .click: return "Clique"
        case .doubleClick: return "Clique duplo"
        case .tripleClick: return "Clique triplo"
        case .hold: return "Segurar"
        case .drag: return "Clicar e arrastar"
        case .scroll: return "Segurar e rolar"
        }
    }
}

public enum ActionKind: String, Codable, CaseIterable, Identifiable {
    case none, primaryClick, secondaryClick, middleClick, back, forward
    case lookup, quickLook, smartZoom, missionControl, appExpose, showDesktop, launchpad
    case spaceLeft, spaceRight, keyboardShortcut
    case playPause, nextTrack, previousTrack, volumeUp, volumeDown, mute
    case brightnessUp, brightnessDown, keyboardBrightnessUp, keyboardBrightnessDown
    case spacesAndMissionControl, scrollAndNavigate, zoom, rotate, horizontalScroll, fastScroll, preciseScroll, desktopAndLaunchpad
    public var id: Self { self }
    public var title: String {
        switch self {
        case .none: return "Nenhuma ação"
        case .primaryClick: return "Clique principal"
        case .secondaryClick: return "Clique secundário"
        case .middleClick: return "Clique do meio"
        case .back: return "Voltar"
        case .forward: return "Avançar"
        case .lookup: return "Consultar"
        case .quickLook: return "Visualização Rápida"
        case .smartZoom: return "Zoom inteligente"
        case .missionControl: return "Mission Control"
        case .appExpose: return "Janelas do aplicativo"
        case .showDesktop: return "Mostrar mesa"
        case .launchpad: return "Launchpad / Aplicativos"
        case .spaceLeft: return "Mesa à esquerda"
        case .spaceRight: return "Mesa à direita"
        case .keyboardShortcut: return "Atalho de teclado"
        case .playPause: return "Reproduzir / pausar"
        case .nextTrack: return "Próxima faixa"
        case .previousTrack: return "Faixa anterior"
        case .volumeUp: return "Aumentar volume"
        case .volumeDown: return "Diminuir volume"
        case .mute: return "Silenciar"
        case .brightnessUp: return "Aumentar brilho"
        case .brightnessDown: return "Diminuir brilho"
        case .keyboardBrightnessUp: return "Aumentar luz do teclado"
        case .keyboardBrightnessDown: return "Diminuir luz do teclado"
        case .spacesAndMissionControl: return "Mesas e Mission Control"
        case .scrollAndNavigate: return "Rolar e navegar"
        case .zoom: return "Zoom contínuo"
        case .rotate: return "Girar"
        case .horizontalScroll: return "Rolagem horizontal"
        case .fastScroll: return "Rolagem rápida"
        case .preciseScroll: return "Rolagem precisa"
        case .desktopAndLaunchpad: return "Mesa e Launchpad"
        }
    }
    public var isContinuous: Bool {
        [.spacesAndMissionControl, .scrollAndNavigate, .zoom, .rotate, .horizontalScroll,
         .fastScroll, .preciseScroll, .desktopAndLaunchpad].contains(self)
    }
    public static func available(for trigger: Trigger) -> [Self] {
        if trigger == .drag { return [.spacesAndMissionControl, .scrollAndNavigate, .zoom, .rotate, .horizontalScroll] }
        if trigger == .scroll { return [.desktopAndLaunchpad, .spacesAndMissionControl, .zoom, .rotate, .horizontalScroll, .fastScroll, .preciseScroll] }
        return allCases.filter { !$0.isContinuous }
    }
}

public struct MouseAction: Codable, Equatable {
    public var kind: ActionKind
    public var keyCode: UInt16?
    public var modifiers: Modifiers
    public init(_ kind: ActionKind, keyCode: UInt16? = nil, modifiers: Modifiers = []) {
        self.kind = kind; self.keyCode = keyCode; self.modifiers = modifiers
    }
}

public struct Mapping: Codable, Equatable, Identifiable {
    public var id: UUID
    /// One-based button numbers, matching the labels printed on conventional mice.
    public var button: Int
    public var trigger: Trigger
    public var modifiers: Modifiers
    public var heldButtons: Set<Int>
    public var action: MouseAction
    public init(button: Int, trigger: Trigger, action: MouseAction, modifiers: Modifiers = [], heldButtons: Set<Int> = []) {
        self.id = UUID(); self.button = button; self.trigger = trigger
        self.modifiers = modifiers; self.heldButtons = heldButtons; self.action = action
    }
    public var title: String { "\(modifiers.title)Botão \(button) · \(trigger.title)" }
}

public struct ScrollSettings: Codable, Equatable {
    public var smoothing: Smoothing = .regular
    public var speed: Double = 1
    public var inverted: Bool = false
    public var horizontalInverted: Bool = false
    public var shiftHorizontal: Bool = true
    public var optionPrecise: Bool = true
    public var controlZoom: Bool = false
    public var acceleration: Double = 0.35
    public init() {}
}

public struct Configuration: Codable, Equatable {
    public var schemaVersion: Int = 1
    /// A fresh installation never intercepts input before the user enables it.
    public var enabled: Bool = false
    public var scrollEnabled: Bool = true
    public var buttonsEnabled: Bool = true
    public var showMenuBarIcon: Bool = true
    public var scroll = ScrollSettings()
    public var mappings: [Mapping] = []
    public var holdDelay: Double = 0.35
    public var doubleClickInterval: Double = 0.28
    public var dragThreshold: Double = 8
    public init() { mappings = Self.fiveButtonMappings() }
    public static func fiveButtonMappings() -> [Mapping] {
        [Mapping(button: 4, trigger: .click, action: MouseAction(.lookup)),
         Mapping(button: 4, trigger: .drag, action: MouseAction(.spacesAndMissionControl)),
         Mapping(button: 4, trigger: .scroll, action: MouseAction(.desktopAndLaunchpad)),
         Mapping(button: 5, trigger: .click, action: MouseAction(.smartZoom)),
         Mapping(button: 5, trigger: .drag, action: MouseAction(.scrollAndNavigate)),
         Mapping(button: 5, trigger: .scroll, action: MouseAction(.zoom))]
    }
    public static func threeButtonMappings() -> [Mapping] {
        [Mapping(button: 3, trigger: .click, action: MouseAction(.middleClick)),
         Mapping(button: 3, trigger: .doubleClick, action: MouseAction(.smartZoom)),
         Mapping(button: 3, trigger: .hold, action: MouseAction(.lookup)),
         Mapping(button: 3, trigger: .drag, action: MouseAction(.spacesAndMissionControl)),
         Mapping(button: 3, trigger: .scroll, action: MouseAction(.zoom))]
    }
    public func validated() throws -> Self {
        guard schemaVersion == 1 else { throw ConfigurationError.unsupportedVersion }
        guard scroll.speed.isFinite, (0.1...5).contains(scroll.speed),
              scroll.acceleration.isFinite, (0...2).contains(scroll.acceleration),
              (0.15...2).contains(holdDelay), (0.1...1).contains(doubleClickInterval),
              (2...100).contains(dragThreshold), mappings.count <= 256 else { throw ConfigurationError.invalidValue }
        var ids = Set<UUID>()
        var triggers = Set<String>()
        for m in mappings {
            guard (3...32).contains(m.button), m.heldButtons.allSatisfy({ (1...32).contains($0) && $0 != m.button }),
                  m.modifiers.subtracting(.supported).isEmpty,
                  m.action.modifiers.subtracting(.supported).isEmpty,
                  ActionKind.available(for: m.trigger).contains(m.action.kind), ids.insert(m.id).inserted,
                  m.action.kind != .keyboardShortcut || (m.action.keyCode.map { $0 < 128 } ?? false)
            else { throw ConfigurationError.invalidMapping }
            let identity = "\(m.button):\(m.trigger.rawValue):\(m.modifiers.rawValue):\(m.heldButtons.sorted())"
            guard triggers.insert(identity).inserted else { throw ConfigurationError.duplicateTrigger }
        }
        return self
    }
}

public enum ConfigurationError: Error, LocalizedError {
    case unsupportedVersion, invalidValue, invalidMapping, duplicateTrigger
    public var errorDescription: String? {
        switch self {
        case .unsupportedVersion: return "Esta versão do arquivo de ajustes não é suportada."
        case .invalidValue: return "Há um valor fora do intervalo permitido."
        case .invalidMapping: return "Um mapeamento contém uma entrada ou ação inválida."
        case .duplicateTrigger: return "Já existe uma ação para esta combinação."
        }
    }
}
