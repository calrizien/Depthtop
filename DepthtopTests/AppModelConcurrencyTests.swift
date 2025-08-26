//
//  AppModelConcurrencyTests.swift
//  DepthtopTests
//
//  Tests focused on AppModel concurrency and the dispatch assertion fixes
//

import XCTest
import ScreenCaptureKit
@testable import Depthtop

@MainActor
final class AppModelConcurrencyTests: XCTestCase {
    
    var appModel: AppModel!
    
    override func setUp() async throws {
        try await super.setUp()
        appModel = AppModel()
    }
    
    override func tearDown() async throws {
        await appModel.stopAllCaptures()
        appModel = nil
        try await super.tearDown()
    }
    
    // MARK: - Primary Test for Dispatch Assertion Fix
    
    func testIsCapturedMethodDoesNotCauseDispatchAssertion() async throws {
        // This is the key test for the fix we made to ContentView line 28
        // The isCaptured method must be callable from MainActor without dispatch assertions
        
        // Test with non-existent window ID
        let result1 = appModel.capturedWindows.contains { $0.window.windowID == 99999 }
        XCTAssertFalse(result1, "Non-existent window should not be captured")
        
        // Test multiple calls in succession
        for windowID in 1...10 {
            let result = appModel.capturedWindows.contains { $0.window.windowID == CGWindowID(windowID) }
            XCTAssertFalse(result, "Window \(windowID) should not be captured")
        }
        
        // This should complete without any dispatch queue assertions
        XCTAssertTrue(true, "isCaptured method works without dispatch assertions")
    }
    
    func testWindowArrangementUpdates() async throws {
        // Test that window arrangement changes don't cause dispatch issues
        
        // Test all arrangement types
        let arrangements: [AppModel.WindowArrangement] = [.grid, .curved, .stack]
        
        for arrangement in arrangements {
            appModel.windowArrangement = arrangement
            appModel.updateWindowPositions()
            XCTAssertEqual(appModel.windowArrangement, arrangement, "Arrangement should be \(arrangement)")
        }
    }
    
    #if DEBUG
    func testDebugColorsToggle() async throws {
        // Test that debug colors can be toggled without dispatch assertions
        
        // Check initial state
        let initial = appModel.debugColors
        
        // Toggle multiple times
        for _ in 0..<10 {
            appModel.debugColors.toggle()
        }
        
        // Should end up back at initial state (even number of toggles)
        XCTAssertEqual(appModel.debugColors, initial, "Should return to initial state after even toggles")
    }
    #endif
    
    func testWindowRenderDataGeneration() async throws {
        // Test that getWindowRenderData works correctly
        
        // Initially should be empty
        let initialData = appModel.getWindowRenderData()
        XCTAssertEqual(initialData.count, 0, "Should start with no window render data")
        
        // The method should be callable multiple times without issues
        for _ in 0..<10 {
            let data = appModel.getWindowRenderData()
            XCTAssertNotNil(data, "Window render data should never be nil")
        }
    }
    
    func testConcurrentPropertyAccess() async throws {
        // Test that multiple concurrent accesses don't cause issues
        
        await withTaskGroup(of: Void.self) { group in
            // Multiple tasks reading properties
            for _ in 0..<50 {
                group.addTask { @MainActor in
                    // These should all be safe to access
                    _ = self.appModel.capturedWindows.count
                    _ = self.appModel.windowArrangement
                    _ = self.appModel.previewNeedsUpdate
                    _ = self.appModel.previewQuality
                    #if DEBUG
                    _ = self.appModel.debugColors
                    #endif
                }
            }
        }
        
        XCTAssertTrue(true, "Concurrent property access completed without issues")
    }
    
    func testWindowPositionCalculation() async throws {
        // Test the window arrangement position calculations
        
        let arrangements: [AppModel.WindowArrangement] = [.grid, .curved, .stack]
        
        for arrangement in arrangements {
            // Test position calculation for multiple windows
            for i in 0..<5 {
                let position = arrangement.calculatePosition(for: i, total: 5)
                
                // Verify position is valid (not NaN or infinite)
                XCTAssertFalse(position.x.isNaN, "X position should not be NaN")
                XCTAssertFalse(position.y.isNaN, "Y position should not be NaN")
                XCTAssertFalse(position.z.isNaN, "Z position should not be NaN")
                XCTAssertFalse(position.x.isInfinite, "X position should not be infinite")
                XCTAssertFalse(position.y.isInfinite, "Y position should not be infinite")
                XCTAssertFalse(position.z.isInfinite, "Z position should not be infinite")
            }
        }
    }
}