import XCTest
@testable import BrumaCore

final class EffectPolicyTests: XCTestCase {
    func testLaunchDoesNotCoverAlreadyHalfClosedScreen() {
        var p = EffectPolicy()
        XCTAssertEqual(p.update(angle: 55,time: 0,eligible: true),0)
        XCTAssertEqual(p.update(angle: 55,time: 2,eligible: true),0)
    }

    func testClosingBlursAndOpeningClears() {
        var p = EffectPolicy()
        _ = p.update(angle: 120,time: 0,eligible: true)
        let half = p.update(angle: 65,time: 0.1,eligible: true)
        let shut = p.update(angle: 20,time: 0.2,eligible: true)
        let reopening = p.update(angle: 65,time: 0.3,eligible: true)
        XCTAssertGreaterThan(shut,half)
        XCTAssertEqual(half,reopening,accuracy: 0.0001)
        XCTAssertEqual(p.update(angle: 115,time: 0.4,eligible: true),0)
    }

    func testStationaryLidClearsAndTinyJitterDoesNotRearm() {
        var p = EffectPolicy()
        _ = p.update(angle: 100,time: 0,eligible: true)
        XCTAssertGreaterThan(p.update(angle: 70,time: 0.1,eligible: true),0)
        XCTAssertEqual(p.update(angle: 70.1,time: 1.4,eligible: true),0)
        XCTAssertEqual(p.update(angle: 69.9,time: 1.5,eligible: true),0)
    }

    func testSlowCumulativeMovementCrossesDeadband() {
        var p = EffectPolicy()
        _ = p.update(angle: 80,time: 0,eligible: true)
        XCTAssertEqual(p.update(angle: 79.9,time: 0.1,eligible: true),0)
        XCTAssertEqual(p.update(angle: 79.8,time: 0.2,eligible: true),0)
        XCTAssertGreaterThan(p.update(angle: 79.6,time: 0.3,eligible: true),0)
    }

    func testSensorLossAndExternalOnlyDisplayClear() {
        for invalid in [Optional<Double>.none,.some(.nan),.some(250)] {
            var p = EffectPolicy()
            _ = p.update(angle: 100,time: 0,eligible: true)
            _ = p.update(angle: 60,time: 0.1,eligible: true)
            XCTAssertEqual(p.update(angle: invalid,time: 0.2,eligible: true),0)
            XCTAssertEqual(p.update(angle: 60,time: 0.3,eligible: true),0)
        }
        var p = EffectPolicy()
        _ = p.update(angle: 100,time: 0,eligible: true)
        XCTAssertEqual(p.update(angle: 60,time: 0.1,eligible: false),0)
    }

    func testGradientProtectsHingeAndIsMonotonic() {
        for protection in [0.0,0.5,1] {
            let weights = (0...100).map { EffectPolicy.blurWeight(height: Double($0)/100,dockProtection: protection) }
            XCTAssertLessThan(weights[0],weights[100]*0.2)
            XCTAssertTrue(zip(weights,weights.dropFirst()).allSatisfy { $0 <= $1 })
            XCTAssertEqual(weights[100],1,accuracy: 1e-10)
        }
    }

    func testSmoothRecoveryDoesNotOvershootAcrossFrameRates() {
        for dt in [1.0/120,1.0/60,1.0/30,1.0] {
            let value = EffectPolicy.smooth(current: 0.8,target: 0,dt: dt)
            XCTAssertGreaterThanOrEqual(value,0)
            XCTAssertLessThan(value,0.8)
        }
    }
}
