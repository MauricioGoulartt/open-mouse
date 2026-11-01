import Foundation

public enum EngineEffect: Equatable {
    case action(MouseAction)
    case begin(MouseAction)
    case change(MouseAction, ScrollVector)
    case end(MouseAction)
    case cancel(MouseAction)
    case replayClick(button: Int, modifiers: Modifiers, count: Int)
}

public struct InputDecision: Equatable {
    public var suppress: Bool = false
    public var effects: [EngineEffect] = []
    public init(suppress: Bool = false, effects: [EngineEffect] = []) {
        self.suppress = suppress; self.effects = effects
    }
}

/// Deterministic recognizer. All time comes from the caller's monotonic clock.
public struct ButtonEngine {
    private struct Press {
        var time: Double
        var modifiers: Modifiers
        var rules: [Trigger: Mapping]
        var distance = ScrollVector.zero
        var active: MouseAction?
        var activeTrigger: Trigger?
        var consumed = false
        var count = 1
    }
    private struct PendingClick {
        var deadline: Double
        var count: Int
        var modifiers: Modifiers
        var rules: [Trigger: Mapping]
    }
    private var presses: [Int: Press] = [:]
    private var pending: [Int: PendingClick] = [:]
    public private(set) var heldButtons = Set<Int>()
    public var configuration: Configuration
    public init(configuration: Configuration) { self.configuration = configuration }

    public mutating func down(button: Int, modifiers: Modifiers, time: Double) -> InputDecision {
        let others = heldButtons
        heldButtons.insert(button)
        guard configuration.enabled, configuration.buttonsEnabled else { return InputDecision() }
        let rules = rulesFor(button: button, modifiers: modifiers, held: others)
        guard !rules.isEmpty else { return InputDecision() }
        var count = 1
        var effects: [EngineEffect] = []
        if let previous = pending.removeValue(forKey: button) {
            if previous.modifiers == modifiers, previous.deadline >= time {
                count = previous.count + 1
            } else { effects += clickEffects(button: button, pending: previous) }
        }
        presses[button] = Press(time: time, modifiers: modifiers, rules: rules, count: count)
        // A button used as a chord modifier must not also fire its own click.
        for modifier in Set(rules.values.flatMap { $0.heldButtons }) {
            if var press = presses[modifier] { press.consumed = true; presses[modifier] = press }
        }
        return InputDecision(suppress: true, effects: effects)
    }

    public mutating func up(button: Int, time: Double) -> InputDecision {
        heldButtons.remove(button)
        guard let press = presses.removeValue(forKey: button) else { return InputDecision() }
        if let active = press.active { return InputDecision(suppress: true, effects: [.end(active)]) }
        if press.consumed { return InputDecision(suppress: true) }
        let maxClicks = press.rules[.tripleClick] != nil ? 3 : (press.rules[.doubleClick] != nil ? 2 : 1)
        let click = PendingClick(deadline: time + configuration.doubleClickInterval,
                                 count: press.count, modifiers: press.modifiers, rules: press.rules)
        if press.count >= maxClicks {
            return InputDecision(suppress: true, effects: clickEffects(button: button, pending: click))
        }
        pending[button] = click
        return InputDecision(suppress: true)
    }

    public mutating func move(_ delta: ScrollVector) -> InputDecision {
        var effects: [EngineEffect] = []
        var suppress = false
        let candidates = presses.keys.filter { presses[$0]?.rules[.drag] != nil }
        guard let button = candidates.max(by: { presses[$0]!.time < presses[$1]!.time }) else { return InputDecision() }
        for button in [button] {
            guard var press = presses[button], !press.consumed || press.active != nil else { continue }
            if let active = press.active, press.activeTrigger == .drag {
                effects.append(.change(active, delta)); suppress = true
            } else if press.active == nil, let rule = press.rules[.drag] {
                press.distance.x += delta.x; press.distance.y += delta.y
                if press.distance.magnitude >= configuration.dragThreshold {
                    for other in presses.keys.sorted() where other != button {
                        if var old = presses[other], let active = old.active {
                            effects.append(.cancel(active)); old.active = nil; old.activeTrigger = nil
                            old.consumed = true; presses[other] = old
                        }
                    }
                    press.active = rule.action; press.activeTrigger = .drag; press.consumed = true
                    effects += [.begin(rule.action), .change(rule.action, press.distance)]
                    suppress = true
                }
            }
            presses[button] = press
        }
        return InputDecision(suppress: suppress, effects: effects)
    }

    public mutating func wheel(_ delta: ScrollVector) -> InputDecision {
        // The most recently pressed eligible button owns the gesture.
        let candidates = presses.keys.filter { presses[$0]?.rules[.scroll] != nil }
        guard let button = candidates.max(by: { presses[$0]!.time < presses[$1]!.time }),
              var press = presses[button], let rule = press.rules[.scroll],
              !press.consumed || (press.active == rule.action && press.activeTrigger == .scroll) else { return InputDecision() }
        var effects: [EngineEffect] = []
        if press.active == nil { effects.append(.begin(rule.action)); press.active = rule.action; press.activeTrigger = .scroll }
        press.consumed = true
        effects.append(.change(rule.action, delta))
        presses[button] = press
        return InputDecision(suppress: true, effects: effects)
    }

    public mutating func tick(time: Double) -> [EngineEffect] {
        var effects: [EngineEffect] = []
        for button in pending.keys.sorted() {
            if let click = pending[button], click.deadline <= time {
                effects += clickEffects(button: button, pending: click)
                pending.removeValue(forKey: button)
            }
        }
        for button in presses.keys.sorted() {
            guard var press = presses[button], !press.consumed,
                  time - press.time >= configuration.holdDelay, let hold = press.rules[.hold] else { continue }
            effects.append(.action(hold.action)); press.consumed = true; presses[button] = press
        }
        return effects
    }

    public mutating func cancel() -> [EngineEffect] {
        let effects = presses.values.compactMap { $0.active }.map(EngineEffect.cancel)
        presses.removeAll(); pending.removeAll(); heldButtons.removeAll()
        return effects
    }

    private func rulesFor(button: Int, modifiers: Modifiers, held: Set<Int>) -> [Trigger: Mapping] {
        let candidates = configuration.mappings.filter {
            $0.button == button && modifiers.isSuperset(of: $0.modifiers) && held.isSuperset(of: $0.heldButtons)
        }
        var rules: [Trigger: Mapping] = [:]
        for candidate in candidates {
            let score = candidate.modifiers.rawValue.nonzeroBitCount + candidate.heldButtons.count * 4
            let oldScore = rules[candidate.trigger].map { $0.modifiers.rawValue.nonzeroBitCount + $0.heldButtons.count * 4 } ?? -1
            if score > oldScore { rules[candidate.trigger] = candidate }
        }
        return rules
    }

    private func clickEffects(button: Int, pending click: PendingClick) -> [EngineEffect] {
        let trigger: Trigger = click.count >= 3 ? .tripleClick : (click.count == 2 ? .doubleClick : .click)
        if let mapping = click.rules[trigger] { return [.action(mapping.action)] }
        if let single = click.rules[.click] { return Array(repeating: .action(single.action), count: click.count) }
        return [.replayClick(button: button, modifiers: click.modifiers, count: click.count)]
    }
}
