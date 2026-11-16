import Foundation

public struct EffectPolicy {
    public var triggerAngle: Double = 110
    public var settleDelay: Double = 1.2
    private var previous: Double?
    private var lastMotion: Double = 0
    private var armed = false

    public init() {}

    public mutating func reset() {
        previous = nil
        armed = false
    }

    /// A stationary lid always clears, even below the trigger angle. Cumulative
    /// motion crosses the deadband, so slow opening still works.
    public mutating func update(angle: Double?, time: Double, eligible: Bool) -> Double {
        guard eligible, let angle, angle.isFinite, (0...180).contains(angle) else {
            reset()
            return 0
        }
        guard let previous else {
            self.previous = angle
            return 0
        }
        if abs(angle - previous) >= 0.3 {
            self.previous = angle
            lastMotion = time
            armed = true
        }
        guard armed, time - lastMotion < settleDelay else { return 0 }
        return Self.amount(angle: angle, trigger: triggerAngle)
    }

    public static func amount(angle: Double, trigger: Double) -> Double {
        guard angle.isFinite, trigger.isFinite else { return 0 }
        let x = min(1, max(0, (trigger - angle) / max(1, trigger - 12)))
        return x * x * (3 - 2 * x)
    }

    /// Normalized radius from Dock (height 0) to top edge (height 1).
    public static func blurWeight(height: Double, dockProtection: Double) -> Double {
        let h = min(1, max(0, height))
        let p = min(1, max(0, dockProtection))
        return (1 - p) * 0.16 + (0.84 + 0.16 * p) * pow(h, 1.5)
    }

    public static func smooth(current: Double, target: Double, dt: Double) -> Double {
        current + (target - current) * (1 - exp(-min(0.1, max(0, dt)) / 0.065))
    }
}
