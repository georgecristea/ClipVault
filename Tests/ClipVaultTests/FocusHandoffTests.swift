import XCTest
@testable import ClipVault

final class FocusHandoffTests: XCTestCase {
    /// Activation can only be handed over by the active app, so ClipVault activates itself
    /// first when it isn't active (its panel is non-activating), then yields to the target.
    func testHandsActivationToTheTarget() {
        XCTAssertEqual(BarController.focusHandoff(clipVaultIsActive: false, hasTarget: true),
                       [.activateSelf, .yieldToTarget, .activateTarget])
        XCTAssertEqual(BarController.focusHandoff(clipVaultIsActive: true, hasTarget: true),
                       [.yieldToTarget, .activateTarget])
    }

    func testWithoutATargetLetsMacOSPickTheNextApp() {
        XCTAssertEqual(BarController.focusHandoff(clipVaultIsActive: false, hasTarget: false), [.activateSelf, .hideSelf])
        XCTAssertEqual(BarController.focusHandoff(clipVaultIsActive: true, hasTarget: false), [.hideSelf])
    }
}
