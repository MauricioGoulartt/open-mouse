import Foundation

public struct ScrollVector: Equatable {
    public var x: Double
    public var y: Double
    public init(x: Double = 0, y: Double = 0) { self.x = x; self.y = y }
    public var magnitude: Double { hypot(x, y) }
    public static let zero = Self()
}

/// Analytic exponential response: no fixed-rate dependency, no movement after reversal.
public struct ScrollPhysics {
    public private(set) var pending: ScrollVector = .zero
    private var lastInputTime: Double?
    private var lastDirection: ScrollVector = .zero
    public init() {}
    public mutating func cancel() { pending = .zero; lastInputTime = nil; lastDirection = .zero }
    public mutating func add(_ lines: ScrollVector, time: Double, settings: ScrollSettings, precise: Bool = false) {
        guard lines.x.isFinite, lines.y.isFinite, time.isFinite else { return }
        if lines.x * lastDirection.x < 0 { pending.x = 0 }
        if lines.y * lastDirection.y < 0 { pending.y = 0 }
        let interval = lastInputTime.map { max(0.001, time - $0) } ?? 1
        let burst = precise ? 1 : 1 + settings.acceleration * max(0, min(3, 0.07 / interval - 1))
        let factor = 16 * settings.speed * burst * (precise ? 0.25 : 1)
        pending.x += lines.x * factor * (settings.horizontalInverted ? -1 : 1)
        pending.y += lines.y * factor * (settings.inverted ? -1 : 1)
        pending.x = max(-12000, min(12000, pending.x))
        pending.y = max(-12000, min(12000, pending.y))
        lastInputTime = time; lastDirection = lines
    }
    public mutating func step(seconds: Double, smoothing: Smoothing) -> ScrollVector {
        guard seconds.isFinite, seconds > 0 else { return .zero }
        if pending.magnitude < 0.05 { let tail = pending; pending = .zero; return tail }
        let alpha = 1 - exp(-min(seconds, 0.1) / smoothing.response)
        let output = ScrollVector(x: pending.x * alpha, y: pending.y * alpha)
        pending.x -= output.x; pending.y -= output.y
        return output
    }
    public var isActive: Bool { pending != .zero }
}
