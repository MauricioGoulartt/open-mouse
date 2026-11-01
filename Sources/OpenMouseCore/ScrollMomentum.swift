import Foundation

/// Integrates velocity analytically, so release inertia is independent of FPS.
public struct ScrollMomentum {
    public private(set) var velocity = ScrollVector.zero
    private let timeConstant: Double = 0.18
    public init() {}
    public var isActive: Bool { velocity.magnitude >= 8 }
    public mutating func start(velocity: ScrollVector) {
        guard velocity.x.isFinite, velocity.y.isFinite, velocity.magnitude >= 35 else { cancel(); return }
        self.velocity = ScrollVector(x: max(-6000, min(6000, velocity.x)), y: max(-6000, min(6000, velocity.y)))
    }
    public mutating func cancel() { velocity = .zero }
    public mutating func step(seconds: Double) -> ScrollVector {
        guard isActive, seconds.isFinite, seconds > 0 else { cancel(); return .zero }
        let decay = exp(-min(seconds, 0.1) / timeConstant)
        let result = ScrollVector(x: velocity.x * timeConstant * (1 - decay), y: velocity.y * timeConstant * (1 - decay))
        velocity.x *= decay; velocity.y *= decay
        return result
    }
}
