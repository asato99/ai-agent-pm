// UITests/Debug/DebugSimpleTest.swift
// Minimal test to debug accessibility

import XCTest

final class DebugSimpleTest: XCTestCase {

    func testSimpleLaunch() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-UITesting", "-UITestScenario:Empty"]
        app.launch()
        
        // Just check if the app launched
        XCTAssertEqual(app.state, .runningForeground, "App should be in foreground")
        
        // Try to get window without any element queries
        let window = app.windows.firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: 10), "Window should exist")
        
        // Try clicking at a specific coordinate
        let coordinate = window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        coordinate.click()
        
        print("✅ Simple test completed!")
    }
}
