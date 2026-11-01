import AppKit
import ApplicationServices
import OpenMouseCore

final class MouseEngine {
    var onStatus: ((String) -> Void)?
    var onButton: ((Int, Modifiers, Set<Int>) -> Void)?
    var captureNextButton = false
    var isRunning: Bool { tap != nil }
    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var timer: Timer?
    private var physics = ScrollPhysics()
    private var buttons = ButtonEngine(configuration: Configuration())
    private let emitter = ActionEmitter()
    private var lastFrame = ProcessInfo.processInfo.systemUptime
    private var smoothStarted = false
    private var frontmostObserver: NSObjectProtocol?
    private var configuration = Configuration()
    private var scrollZoomActive = false
    private var lastZoomTime: Double = 0

    init() {
        emitter.onNotice = { [weak self] in self?.onStatus?($0) }
        frontmostObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.cancelGestures() }
    }

    deinit {
        stop()
        if let observer = frontmostObserver { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
    }

    func configure(_ value: Configuration) {
        cancelGestures(); configuration = value; buttons.configuration = value
        if value.enabled { start() } else { stop() }
    }

    func requestAccessibility() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    func start() {
        guard tap == nil else { return }
        guard AXIsProcessTrusted() else { onStatus?("Autorize o Open Mouse em Acessibilidade para ativar."); return }
        let types: [CGEventType] = [.scrollWheel, .leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp,
            .otherMouseDown, .otherMouseUp, .mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged]
        let mask = types.reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << $1.rawValue) }
        let callback: CGEventTapCallBack = { _, type, event, context in
            guard let context else { return Unmanaged.passUnretained(event) }
            let engine = Unmanaged<MouseEngine>.fromOpaque(context).takeUnretainedValue()
            return engine.handle(type: type, event: event)
        }
        guard let port = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
            eventsOfInterest: mask, callback: callback, userInfo: Unmanaged.passUnretained(self).toOpaque()) else {
            onStatus?("O macOS recusou a captura. Verifique Acessibilidade e reative o Open Mouse."); return
        }
        tap = port
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)
        lastFrame = ProcessInfo.processInfo.systemUptime
        timer = Timer(timeInterval: 1.0 / 120, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(timer!, forMode: .common)
        onStatus?("Ativo")
    }

    func stop() {
        cancelGestures(); timer?.invalidate(); timer = nil
        if let port = tap { CGEvent.tapEnable(tap: port, enable: false); CFMachPortInvalidate(port) }
        if let source = runLoopSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        tap = nil; runLoopSource = nil; onStatus?("Desativado")
    }

    private func cancelGestures() {
        emitter.apply(buttons.cancel()); physics.cancel()
        if smoothStarted { emitter.scroll(.zero, phase: 4); smoothStarted = false }
        if scrollZoomActive { emitter.apply([.end(MouseAction(.zoom))]); scrollZoomActive = false }
        emitter.reset()
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            cancelGestures()
            if let tap, AXIsProcessTrusted() { CGEvent.tapEnable(tap: tap, enable: true) }
            else { onStatus?("A captura foi interrompida pelo macOS. Reative após conferir a permissão.") }
            return Unmanaged.passUnretained(event)
        }
        guard event.getIntegerValueField(.eventSourceUserData) != ActionEmitter.marker else { return Unmanaged.passUnretained(event) }
        let time = ProcessInfo.processInfo.systemUptime
        let modifiers = Modifiers(rawValue: event.flags.rawValue).intersection(.supported)
        switch type {
        case .leftMouseDown, .rightMouseDown, .otherMouseDown:
            let button = Int(event.getIntegerValueField(.mouseEventButtonNumber)) + 1
            if captureNextButton, button >= 3 {
                captureNextButton = false
                onButton?(button, modifiers, buttons.heldButtons)
                // Capture observes a real click without swallowing its release.
                return Unmanaged.passUnretained(event)
            }
            let result = buttons.down(button: button, modifiers: modifiers, time: time)
            emitter.apply(result.effects)
            return result.suppress ? nil : Unmanaged.passUnretained(event)
        case .leftMouseUp, .rightMouseUp, .otherMouseUp:
            let result = buttons.up(button: Int(event.getIntegerValueField(.mouseEventButtonNumber)) + 1, time: time)
            emitter.apply(result.effects)
            return result.suppress ? nil : Unmanaged.passUnretained(event)
        case .mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged:
            let delta = ScrollVector(x: event.getDoubleValueField(.mouseEventDeltaX), y: event.getDoubleValueField(.mouseEventDeltaY))
            let result = buttons.move(delta); emitter.apply(result.effects)
            return result.suppress ? nil : Unmanaged.passUnretained(event)
        case .scrollWheel:
            // Continuous hardware events belong to trackpads/high-resolution devices.
            // Pass through untouched rather than accidentally changing trackpad behavior.
            guard event.getIntegerValueField(.scrollWheelEventIsContinuous) == 0 else { return Unmanaged.passUnretained(event) }
            var delta = ScrollVector(x: event.getDoubleValueField(.scrollWheelEventDeltaAxis2), y: event.getDoubleValueField(.scrollWheelEventDeltaAxis1))
            let result = buttons.wheel(delta); emitter.apply(result.effects)
            if result.suppress { return nil }
            guard configuration.scrollEnabled else { return Unmanaged.passUnretained(event) }
            let settings = configuration.scroll
            if settings.controlZoom && modifiers.contains(.control) {
                if !scrollZoomActive { emitter.apply([.begin(MouseAction(.zoom))]); scrollZoomActive = true }
                emitter.apply([.change(MouseAction(.zoom), delta)]); lastZoomTime = time; return nil
            }
            if settings.shiftHorizontal && modifiers.contains(.shift) { delta = ScrollVector(x: delta.y, y: delta.x) }
            let precise = settings.optionPrecise && modifiers.contains(.option)
            if settings.smoothing == .off {
                event.setDoubleValueField(.scrollWheelEventDeltaAxis1, value: delta.y * settings.speed * (settings.inverted ? -1 : 1) * (precise ? 0.25 : 1))
                event.setDoubleValueField(.scrollWheelEventDeltaAxis2, value: delta.x * settings.speed * (settings.horizontalInverted ? -1 : 1) * (precise ? 0.25 : 1))
                // Update all representations, including apps reading fixed-point/pixel fields.
                let signY: Double = settings.inverted ? -1 : 1, signX: Double = settings.horizontalInverted ? -1 : 1
                let factor = settings.speed * (precise ? 0.25 : 1)
                let originalY = event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1)
                let originalX = event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2)
                event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1, value: (settings.shiftHorizontal && modifiers.contains(.shift) ? originalX : originalY) * factor * signY)
                event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2, value: (settings.shiftHorizontal && modifiers.contains(.shift) ? originalY : originalX) * factor * signX)
                if settings.shiftHorizontal && modifiers.contains(.shift) { event.flags.remove(.maskShift) }
                return Unmanaged.passUnretained(event)
            }
            physics.add(delta, time: time, settings: settings, precise: precise)
            return nil
        default: return Unmanaged.passUnretained(event)
        }
    }

    private func tick() {
        let now = ProcessInfo.processInfo.systemUptime
        emitter.apply(buttons.tick(time: now))
        if physics.isActive {
            let delta = physics.step(seconds: now - lastFrame, smoothing: configuration.scroll.smoothing)
            emitter.scroll(delta, phase: smoothStarted ? 2 : 1); smoothStarted = true
        } else if smoothStarted { emitter.scroll(.zero, phase: 4); smoothStarted = false }
        if scrollZoomActive && now - lastZoomTime > 0.15 {
            emitter.apply([.end(MouseAction(.zoom))]); scrollZoomActive = false
        }
        lastFrame = now
    }
}
