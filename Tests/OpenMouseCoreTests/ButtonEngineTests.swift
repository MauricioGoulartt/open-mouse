import XCTest
@testable import OpenMouseCore

final class ButtonEngineTests: XCTestCase {
    private func engine(_ mappings: [Mapping]) -> ButtonEngine {
        var config = Configuration(); config.enabled = true; config.mappings = mappings
        return ButtonEngine(configuration: config)
    }
    func testUnmappedPrimaryButtonPassesThrough() {
        var value = engine(Configuration.fiveButtonMappings())
        XCTAssertFalse(value.down(button: 1, modifiers: [], time: 0).suppress)
        XCTAssertFalse(value.up(button: 1, time: 0.1).suppress)
    }
    func testSingleClickHasNoDoubleClickDelayWithoutMultiClickMapping() {
        var value = engine([Mapping(button: 4, trigger: .click, action: MouseAction(.back))])
        XCTAssertTrue(value.down(button: 4, modifiers: [], time: 0).suppress)
        XCTAssertEqual(value.up(button: 4, time: 0.05).effects, [.action(MouseAction(.back))])
        XCTAssertTrue(value.tick(time: 1).isEmpty)
    }
    func testDoubleClickDoesNotAlsoFireSingleClick() {
        var value = engine([Mapping(button: 3, trigger: .click, action: MouseAction(.middleClick)),
                            Mapping(button: 3, trigger: .doubleClick, action: MouseAction(.smartZoom))])
        _ = value.down(button: 3, modifiers: [], time: 0)
        XCTAssertTrue(value.up(button: 3, time: 0.02).effects.isEmpty)
        _ = value.down(button: 3, modifiers: [], time: 0.1)
        XCTAssertEqual(value.up(button: 3, time: 0.12).effects, [.action(MouseAction(.smartZoom))])
        XCTAssertTrue(value.tick(time: 1).isEmpty)
    }
    func testPendingSingleClickFiresOnDeadline() {
        var value = engine([Mapping(button: 3, trigger: .click, action: MouseAction(.middleClick)),
                            Mapping(button: 3, trigger: .doubleClick, action: MouseAction(.smartZoom))])
        _ = value.down(button: 3, modifiers: [], time: 0)
        _ = value.up(button: 3, time: 0.02)
        XCTAssertTrue(value.tick(time: 0.2).isEmpty)
        XCTAssertEqual(value.tick(time: 0.4), [.action(MouseAction(.middleClick))])
    }
    func testHoldSuppressesClickAndRunsOnlyOnce() {
        var value = engine([Mapping(button: 3, trigger: .click, action: MouseAction(.middleClick)),
                            Mapping(button: 3, trigger: .hold, action: MouseAction(.lookup))])
        _ = value.down(button: 3, modifiers: [], time: 0)
        XCTAssertEqual(value.tick(time: 0.4), [.action(MouseAction(.lookup))])
        XCTAssertTrue(value.tick(time: 0.6).isEmpty)
        XCTAssertTrue(value.up(button: 3, time: 0.7).effects.isEmpty)
    }
    func testDragBracketsGestureAndDoesNotFireClick() {
        let action = MouseAction(.scrollAndNavigate)
        var value = engine([Mapping(button: 5, trigger: .click, action: MouseAction(.forward)),
                            Mapping(button: 5, trigger: .drag, action: action)])
        _ = value.down(button: 5, modifiers: [], time: 0)
        XCTAssertFalse(value.move(ScrollVector(x: 3, y: 0)).suppress)
        XCTAssertEqual(value.move(ScrollVector(x: 7, y: 0)).effects, [.begin(action), .change(action, ScrollVector(x: 10))])
        XCTAssertEqual(value.up(button: 5, time: 0.2).effects, [.end(action)])
    }
    func testCancellationCancelsInsteadOfCommittingDockGesture() {
        let action = MouseAction(.spacesAndMissionControl)
        var value = engine([Mapping(button: 4, trigger: .drag, action: action)])
        _ = value.down(button: 4, modifiers: [], time: 0)
        _ = value.move(ScrollVector(x: 20))
        XCTAssertEqual(value.cancel(), [.cancel(action)])
        XCTAssertTrue(value.up(button: 4, time: 1).effects.isEmpty)
        XCTAssertTrue(value.heldButtons.isEmpty)
    }
    func testWheelGestureDoesNotReactToCursorMotionOrAlsoClick() {
        let action = MouseAction(.zoom)
        var value = engine([Mapping(button: 5, trigger: .click, action: MouseAction(.forward)),
                            Mapping(button: 5, trigger: .scroll, action: action),
                            Mapping(button: 5, trigger: .drag, action: MouseAction(.scrollAndNavigate))])
        _ = value.down(button: 5, modifiers: [], time: 0)
        XCTAssertEqual(value.wheel(ScrollVector(y: 1)).effects, [.begin(action), .change(action, ScrollVector(y: 1))])
        XCTAssertFalse(value.move(ScrollVector(x: 30)).suppress)
        XCTAssertEqual(value.up(button: 5, time: 0.3).effects, [.end(action)])
    }
    func testModifiersAndHeldButtonChooseMoreSpecificMapping() {
        var value = engine([Mapping(button: 4, trigger: .click, action: MouseAction(.back)),
                            Mapping(button: 4, trigger: .click, action: MouseAction(.forward), modifiers: [.command], heldButtons: [1])])
        _ = value.down(button: 1, modifiers: [], time: 0)
        _ = value.down(button: 4, modifiers: [.command], time: 0.1)
        XCTAssertEqual(value.up(button: 4, time: 0.2).effects, [.action(MouseAction(.forward))])
        XCTAssertFalse(value.up(button: 1, time: 0.3).suppress)
    }
    func testDragOnlyMappingReplaysNormalClickBelowThreshold() {
        var value = engine([Mapping(button: 3, trigger: .drag, action: MouseAction(.scrollAndNavigate))])
        _ = value.down(button: 3, modifiers: [.shift], time: 0)
        _ = value.move(ScrollVector(x: 2))
        XCTAssertEqual(value.up(button: 3, time: 0.1).effects, [.replayClick(button: 3, modifiers: [.shift], count: 1)])
    }
    func testDisabledButtonsDoNotIntercept() {
        var value = engine(Configuration.fiveButtonMappings()); value.configuration.buttonsEnabled = false
        XCTAssertFalse(value.down(button: 4, modifiers: [], time: 0).suppress)
        XCTAssertFalse(value.up(button: 4, time: 0.1).suppress)
    }
    func testTripleClickDoesNotAlsoFireDoubleClick() {
        var value = engine([Mapping(button: 3, trigger: .click, action: MouseAction(.middleClick)),
                            Mapping(button: 3, trigger: .doubleClick, action: MouseAction(.smartZoom)),
                            Mapping(button: 3, trigger: .tripleClick, action: MouseAction(.lookup))])
        var effects: [EngineEffect] = []
        for i in 0..<3 {
            _ = value.down(button: 3, modifiers: [], time: Double(i) * 0.08)
            effects += value.up(button: 3, time: Double(i) * 0.08 + 0.02).effects
        }
        XCTAssertEqual(effects, [.action(MouseAction(.lookup))])
        XCTAssertTrue(value.tick(time: 2).isEmpty)
    }
    func testChordModifierDoesNotAlsoFireItsOwnClick() {
        var value = engine([Mapping(button: 4, trigger: .click, action: MouseAction(.lookup)),
                            Mapping(button: 5, trigger: .click, action: MouseAction(.forward), heldButtons: [4])])
        _ = value.down(button: 4, modifiers: [], time: 0)
        _ = value.down(button: 5, modifiers: [], time: 0.1)
        XCTAssertEqual(value.up(button: 5, time: 0.2).effects, [.action(MouseAction(.forward))])
        XCTAssertTrue(value.up(button: 4, time: 0.3).effects.isEmpty)
    }
    func testMostRecentDragCancelsOldGestureInsteadOfDrivingBoth() {
        let first = MouseAction(.spacesAndMissionControl), second = MouseAction(.scrollAndNavigate)
        var value = engine([Mapping(button: 4, trigger: .drag, action: first), Mapping(button: 5, trigger: .drag, action: second)])
        _ = value.down(button: 4, modifiers: [], time: 0)
        _ = value.move(ScrollVector(x: 10))
        _ = value.down(button: 5, modifiers: [], time: 0.1)
        XCTAssertEqual(value.move(ScrollVector(y: 10)).effects,
                       [.cancel(first), .begin(second), .change(second, ScrollVector(y: 10))])
        XCTAssertTrue(value.up(button: 4, time: 0.2).effects.isEmpty)
    }
}
