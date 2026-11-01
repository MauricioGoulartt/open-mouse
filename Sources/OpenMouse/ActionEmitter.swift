import AppKit
import CoreGraphics
import OpenMouseCore

/// Protocol fields independently documented by WebKit's test SPI.
/// See docs/research/macos-native-gesture-protocol.md; no MMF source is included.
final class ActionEmitter {
    static let marker: Int64 = 0x4F50454E4D4F5553
    var onNotice: ((String) -> Void)?
    private let source = CGEventSource(stateID: .combinedSessionState)
    private var continuous = ScrollVector.zero
    private var scrollFraction = ScrollVector.zero
    private var scrollStarted = false
    private var dockAxis: Int64?
    private var dockProgress: Double = 0
    private var dockVelocity: Double = 0
    private var lastGestureTime: Double = 0
    private var dragVelocity = ScrollVector.zero
    private var momentum = ScrollMomentum()
    private var momentumStarted = false
    private let eventSink: ((CGEvent, CGEventTapLocation) -> Void)?

    init(eventSink: ((CGEvent, CGEventTapLocation) -> Void)? = nil) { self.eventSink = eventSink }

    func apply(_ effects: [EngineEffect]) {
        for effect in effects {
            switch effect {
            case .action(let action): perform(action)
            case .replayClick(let button, let modifiers, let count): click(button: button, modifiers: modifiers, count: count)
            case .begin(let action): begin(action)
            case .change(let action, let delta): change(action, delta: delta)
            case .end(let action): end(action)
            case .cancel(let action): end(action, cancelled: true)
            }
        }
    }

    func perform(_ action: MouseAction) {
        switch action.kind {
        case .none: break
        case .primaryClick: click(button: 1)
        case .secondaryClick: click(button: 2)
        case .middleClick: click(button: 3)
        case .back, .forward:
            let forward = action.kind == .forward
            let app = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? ""
            if app == "com.microsoft.VSCode" || app == "com.todesktop.230313mzl4w4u92" {
                keyboard(code: 27, modifiers: forward ? [.control, .shift] : [.control])
            } else { keyboard(code: forward ? 30 : 33, modifiers: [.command]) }
        case .lookup: keyboard(code: 2, modifiers: [.control, .command])
        case .quickLook: keyboard(code: 49)
        case .smartZoom: gesture(hidType: 22, phase: 0)
        case .missionControl: symbolicHotkey("32", fallback: (126, [.control]))
        case .appExpose: symbolicHotkey("33", fallback: (125, [.control]))
        case .showDesktop: symbolicHotkey("36", fallback: (103, []))
        case .spaceLeft: symbolicHotkey("79", fallback: (123, [.control]))
        case .spaceRight: symbolicHotkey("81", fallback: (124, [.control]))
        case .launchpad:
            let paths = ["/System/Applications/Launchpad.app", "/System/Applications/Apps.app"]
            if let path = paths.first(where: { FileManager.default.fileExists(atPath: $0) }) {
                NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: path), configuration: .init())
            } else { onNotice?("Este macOS não oferece o aplicativo Launchpad neste caminho.") }
        case .keyboardShortcut:
            if let code = action.keyCode { keyboard(code: code, modifiers: action.modifiers) }
        case .playPause: media(16)
        case .nextTrack: media(17)
        case .previousTrack: media(18)
        case .volumeUp: media(0)
        case .volumeDown: media(1)
        case .mute: media(7)
        case .brightnessUp: media(2)
        case .brightnessDown: media(3)
        case .keyboardBrightnessUp: media(21)
        case .keyboardBrightnessDown: media(22)
        default: break
        }
    }

    func keyboard(code: UInt16, modifiers: Modifiers = []) {
        for down in [true, false] {
            if let event = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: down) {
                event.flags = CGEventFlags(rawValue: modifiers.rawValue); post(event)
            }
        }
    }

    func click(button: Int, modifiers: Modifiers = [], count: Int = 1) {
        guard (1...32).contains(button) else { return }
        let point = CGEvent(source: nil)?.location ?? .zero
        let number = CGMouseButton(rawValue: UInt32(button - 1))!
        for index in 1...max(1, min(3, count)) {
            let types: [CGEventType] = button == 1 ? [.leftMouseDown, .leftMouseUp] :
                (button == 2 ? [.rightMouseDown, .rightMouseUp] : [.otherMouseDown, .otherMouseUp])
            for type in types {
                if let event = CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: point, mouseButton: number) {
                    event.flags = CGEventFlags(rawValue: modifiers.rawValue)
                    event.setIntegerValueField(.mouseEventClickState, value: Int64(index)); post(event)
                }
            }
        }
    }

    func scroll(_ delta: ScrollVector, phase: Int64 = 0, momentum: Int64 = 0) {
        scrollFraction.x += delta.x; scrollFraction.y += delta.y
        let x = scrollFraction.x.rounded(.towardZero), y = scrollFraction.y.rounded(.towardZero)
        scrollFraction.x -= x; scrollFraction.y -= y
        guard x != 0 || y != 0 || phase != 0 || momentum != 0 else { return }
        guard let event = CGEvent(scrollWheelEvent2Source: source, units: .pixel, wheelCount: 2,
                                  wheel1: Int32(clamping: Int64(y)), wheel2: Int32(clamping: Int64(x)), wheel3: 0) else { return }
        event.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
        event.setIntegerValueField(.scrollWheelEventScrollPhase, value: phase)
        event.setIntegerValueField(.scrollWheelEventMomentumPhase, value: momentum)
        event.flags = []
        event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1, value: delta.y)
        event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2, value: delta.x)
        post(event, tap: .cgSessionEventTap)
    }

    func reset() {
        cancelMomentum()
        if scrollStarted { scroll(.zero, phase: 4) }
        continuous = .zero; scrollFraction = .zero; scrollStarted = false
    }

    private func begin(_ action: MouseAction) {
        cancelMomentum()
        continuous = .zero; dockAxis = nil; dockProgress = 0; dockVelocity = 0
        dragVelocity = .zero
        lastGestureTime = ProcessInfo.processInfo.systemUptime
        switch action.kind {
        case .zoom: gesture(hidType: 61, phase: 0); gesture(hidType: 8, phase: 1, valueField: 113)
        case .rotate: gesture(hidType: 61, phase: 0); gesture(hidType: 5, phase: 1, valueField: 114)
        case .scrollAndNavigate, .horizontalScroll, .fastScroll, .preciseScroll:
            scrollStarted = true; scroll(.zero, phase: 1)
        case .desktopAndLaunchpad:
            dockAxis = 3; dockSwipe(phase: 1)
        default: break
        }
    }

    private func change(_ action: MouseAction, delta: ScrollVector) {
        continuous.x += delta.x; continuous.y += delta.y
        switch action.kind {
        case .zoom: gesture(hidType: 8, phase: 2, valueField: 113, value: -delta.y * 0.008)
        case .rotate: gesture(hidType: 5, phase: 2, valueField: 114, value: delta.y * 0.8)
        case .scrollAndNavigate:
            let now = ProcessInfo.processInfo.systemUptime
            let dt = max(0.001, now - lastGestureTime)
            dragVelocity.x = dragVelocity.x * 0.65 - delta.x / dt * 0.35
            dragVelocity.y = dragVelocity.y * 0.65 - delta.y / dt * 0.35
            lastGestureTime = now
            scroll(ScrollVector(x: -delta.x, y: -delta.y), phase: 2)
        case .horizontalScroll: scroll(ScrollVector(x: delta.y != 0 ? delta.y * 16 : delta.x), phase: 2)
        case .fastScroll: scroll(ScrollVector(x: delta.x * 60, y: delta.y * 60), phase: 2)
        case .preciseScroll: scroll(ScrollVector(x: delta.x * 4, y: delta.y * 4), phase: 2)
        case .spacesAndMissionControl:
            if dockAxis == nil {
                dockAxis = abs(continuous.x) > abs(continuous.y) ? 1 : 2
                dockSwipe(phase: 1)
            }
            let previous = dockProgress
            dockProgress = -(dockAxis == 1 ? continuous.x : continuous.y) / 350
            let now = ProcessInfo.processInfo.systemUptime
            dockVelocity = (dockProgress - previous) / max(0.001, now - lastGestureTime)
            lastGestureTime = now
            dockSwipe(phase: 2)
        case .desktopAndLaunchpad:
            let previous = dockProgress
            dockProgress = -(continuous.x + continuous.y) / 25
            let now = ProcessInfo.processInfo.systemUptime
            dockVelocity = (dockProgress - previous) / max(0.001, now - lastGestureTime)
            lastGestureTime = now
            dockSwipe(phase: 2)
        default: break
        }
    }

    private func end(_ action: MouseAction, cancelled: Bool = false) {
        let phase: Int64 = cancelled ? 8 : 4
        switch action.kind {
        case .zoom: gesture(hidType: 8, phase: phase, valueField: 113); gesture(hidType: 62, phase: 0)
        case .rotate: gesture(hidType: 5, phase: phase, valueField: 114); gesture(hidType: 62, phase: 0)
        case .scrollAndNavigate, .horizontalScroll, .fastScroll, .preciseScroll:
            scroll(.zero, phase: phase); scrollStarted = false
            if action.kind == .scrollAndNavigate && !cancelled && ProcessInfo.processInfo.systemUptime - lastGestureTime < 0.12 {
                momentum.start(velocity: dragVelocity)
            }
        case .spacesAndMissionControl, .desktopAndLaunchpad:
            if dockAxis != nil { dockSwipe(phase: phase) }; dockAxis = nil
        default: break
        }
        continuous = .zero
    }

    func tick(seconds: Double) {
        if momentum.isActive {
            scroll(momentum.step(seconds: seconds), momentum: momentumStarted ? 2 : 1)
            momentumStarted = true
        } else if momentumStarted { scroll(.zero, momentum: 3); momentumStarted = false }
    }

    func cancelMomentum() {
        momentum.cancel()
        if momentumStarted { scroll(.zero, momentum: 3); momentumStarted = false }
    }

    private func gesture(hidType: Int64, phase: Int64, valueField: UInt32? = nil, value: Double = 0) {
        guard let event = CGEvent(source: source), let type = CGEventType(rawValue: 29) else { return }
        event.type = type
        event.flags = CGEventFlags(rawValue: 0x100)
        event.location = CGEvent(source: nil)?.location ?? .zero
        event.setIntegerValueField(CGEventField(rawValue: 110)!, value: hidType)
        event.setIntegerValueField(CGEventField(rawValue: 132)!, value: phase)
        if let field = valueField { event.setDoubleValueField(CGEventField(rawValue: field)!, value: value) }
        post(event)
    }

    /// Adapted from Scott Lamb's macos-trackpad-companion (MIT), output.rs.
    /// Typed field 135 carries the signed Float32 bit pattern, not an integer
    /// conversion of the progress. See THIRD_PARTY_NOTICES.md.
    private func dockSwipe(phase: Int64) {
        guard let axis = dockAxis, let event = CGEvent(source: source), let type = CGEventType(rawValue: 30) else { return }
        // The public type setter writes the dispatch header. Merely creating an
        // integer payload at private field 55 leaves this a null CGEvent.
        event.type = type
        event.setIntegerValueField(CGEventField(rawValue: 110)!, value: 23)
        event.setIntegerValueField(CGEventField(rawValue: 132)!, value: phase)
        event.setIntegerValueField(CGEventField(rawValue: 123)!, value: axis)
        // GestureMotionScale=3 is the four-finger Dock pinch protocol.
        // The primary-source header mapping is recorded in the research notes.
        event.setDoubleValueField(CGEventField(rawValue: 124)!, value: dockProgress)
        event.setIntegerValueField(CGEventField(rawValue: 135)!, value: Int64(Int32(bitPattern: Float(dockProgress).bitPattern)))
        if phase == 4 || phase == 8 {
            let velocity = phase == 8 ? 0 : max(-8, min(8, dockVelocity))
            event.setDoubleValueField(CGEventField(rawValue: 129)!, value: velocity)
            event.setDoubleValueField(CGEventField(rawValue: 130)!, value: velocity)
        }
        guard let complete = DockEventPacket.augment(event, motion: axis, phase: phase, progress: dockProgress,
            velocity: phase == 4 || phase == 8 ? (phase == 8 ? 0 : max(-8, min(8, dockVelocity))) : nil) else {
            onNotice?("O formato de gesto deste macOS não pôde ser preparado com segurança."); return
        }
        post(complete, tap: .cgSessionEventTap)
    }

    private func media(_ key: Int) {
        for down in [true, false] {
            let flags: NSEvent.ModifierFlags = down ? .init(rawValue: 0xA00) : .init(rawValue: 0xB00)
            if let event = NSEvent.otherEvent(with: .systemDefined, location: .zero, modifierFlags: flags,
                timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: 0, context: nil, subtype: 8,
                data1: (key << 16) | ((down ? 0xA : 0xB) << 8), data2: -1)?.cgEvent { post(event) }
        }
    }

    private func symbolicHotkey(_ id: String, fallback: (UInt16, Modifiers)) {
        let table = UserDefaults(suiteName: "com.apple.symbolichotkeys")?.dictionary(forKey: "AppleSymbolicHotKeys")
        if let setting = table?[id] as? [String: Any] {
            guard setting["enabled"] as? Bool != false else {
                onNotice?("Este atalho está desativado nos Ajustes do Sistema."); return
            }
            if let value = setting["value"] as? [String: Any], let values = value["parameters"] as? [NSNumber], values.count >= 3 {
                let code = values[1].uint16Value
                guard code < 128 else { onNotice?("Configure um atalho de teclado para esta ação nos Ajustes do Sistema."); return }
                keyboard(code: code, modifiers: Modifiers(rawValue: values[2].uint64Value)); return
            }
        }
        keyboard(code: fallback.0, modifiers: fallback.1)
    }

    private func post(_ event: CGEvent, tap: CGEventTapLocation = .cghidEventTap) {
        event.setIntegerValueField(.eventSourceUserData, value: Self.marker)
        if let eventSink { eventSink(event, tap) } else { event.post(tap: tap) }
    }
}
