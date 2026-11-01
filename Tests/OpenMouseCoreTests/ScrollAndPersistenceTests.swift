import XCTest
@testable import OpenMouseCore

final class ScrollAndPersistenceTests: XCTestCase {
    private func drain(_ physics: inout ScrollPhysics, smoothing: Smoothing, hz: Double) -> ScrollVector {
        var sum = ScrollVector.zero
        for _ in 0..<Int(hz * 5) {
            let delta = physics.step(seconds: 1 / hz, smoothing: smoothing)
            sum.x += delta.x; sum.y += delta.y
        }
        return sum
    }
    func testSmoothScrollConservesInputAt60And120Hz() {
        for hz in [60.0, 120.0] {
            var physics = ScrollPhysics()
            physics.add(ScrollVector(x: 2, y: -3), time: 0, settings: ScrollSettings())
            let sum = drain(&physics, smoothing: .regular, hz: hz)
            XCTAssertEqual(sum.x, 32, accuracy: 0.000001)
            XCTAssertEqual(sum.y, -48, accuracy: 0.000001)
            XCTAssertFalse(physics.isActive)
        }
    }
    func testReversalDoesNotContinueInOldDirection() {
        var physics = ScrollPhysics()
        physics.add(ScrollVector(y: 20), time: 0, settings: ScrollSettings())
        physics.add(ScrollVector(y: -1), time: 0.02, settings: ScrollSettings())
        XCTAssertLessThan(physics.step(seconds: 1 / 120, smoothing: .high).y, 0)
    }
    func testPreciseScrollingBypassesBurstAcceleration() {
        var physics = ScrollPhysics()
        for i in 0..<10 { physics.add(ScrollVector(y: 1), time: Double(i) * 0.001, settings: ScrollSettings(), precise: true) }
        XCTAssertEqual(drain(&physics, smoothing: .high, hz: 120).y, 40, accuracy: 0.00001)
    }
    func testCancellationAndNonFiniteInputDoNotEmitMotion() {
        var physics = ScrollPhysics()
        physics.add(ScrollVector(y: .infinity), time: 0, settings: ScrollSettings())
        XCTAssertFalse(physics.isActive)
        physics.add(ScrollVector(y: 3), time: 0, settings: ScrollSettings())
        physics.cancel()
        XCTAssertEqual(physics.step(seconds: 0.1, smoothing: .regular), .zero)
    }
    func testIntensiveWheelBurstIsBoundedAndStops() {
        var physics = ScrollPhysics()
        for i in 0..<100_000 { physics.add(ScrollVector(x: 120, y: 120), time: Double(i) / 10000, settings: ScrollSettings()) }
        XCTAssertLessThanOrEqual(physics.pending.x, 12000)
        let sum = drain(&physics, smoothing: .high, hz: 120)
        XCTAssertTrue(sum.x.isFinite); XCTAssertFalse(physics.isActive)
    }
    func testConfigurationRoundTripPreservesMappingsAndShortcuts() throws {
        var config = Configuration()
        config.mappings.append(Mapping(button: 6, trigger: .click,
            action: MouseAction(.keyboardShortcut, keyCode: 1, modifiers: [.command, .shift]), modifiers: [.option], heldButtons: [1]))
        XCTAssertEqual(try ConfigurationFile.decode(ConfigurationFile.encode(config)), config)
    }
    func testRejectsDuplicateMappingsInvalidVersionAndPrimaryButtonInterception() throws {
        var config = Configuration(); config.mappings.append(config.mappings[0])
        XCTAssertThrowsError(try config.validated())
        config = Configuration(); config.schemaVersion = 999
        XCTAssertThrowsError(try config.validated())
        config = Configuration(); config.mappings = [Mapping(button: 1, trigger: .click, action: MouseAction(.none))]
        XCTAssertThrowsError(try config.validated())
    }
    func testInvalidConfigurationDoesNotOverwriteExistingFile() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("open-mouse-test-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let path = root.appendingPathComponent("settings.json")
        let original = Configuration(); try ConfigurationFile.save(original, to: path)
        let before = try Data(contentsOf: path)
        var invalid = original; invalid.scroll.speed = 100
        XCTAssertThrowsError(try ConfigurationFile.save(invalid, to: path))
        XCTAssertEqual(try Data(contentsOf: path), before)
        XCTAssertEqual((try FileManager.default.attributesOfItem(atPath: path.path)[.posixPermissions] as? NSNumber)?.intValue, 0o600)
    }
}
