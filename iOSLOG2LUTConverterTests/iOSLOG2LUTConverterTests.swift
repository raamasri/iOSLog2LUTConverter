//
//  iOSLOG2LUTConverterTests.swift
//  iOSLOG2LUTConverterTests
//
//  Created by raama srivatsan on 7/3/25.
//

import XCTest
@testable import iOSLOG2LUTConverter

final class iOSLOG2LUTConverterTests: XCTestCase {

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    func testExample() throws {
        // This is an example of a functional test case.
        // Use XCTAssert and related functions to verify your tests produce the correct results.
        // Any test you write for XCTest can be annotated as throws and async.
        // Mark your test throws to produce an unexpected failure when your test encounters an uncaught error.
        // Mark your test async to allow awaiting for asynchronous code to complete. Check the results with assertions afterwards.
    }

    func testLUTProcessorInitialization() throws {
        // Test that LUTProcessor can be initialized
        let processor = LUTProcessor()
        XCTAssertNotNil(processor, "LUTProcessor should initialize successfully")
    }
    
    func testLUTLoading() throws {
        // Test that LUTs can be loaded from the app bundle
        let manager = LUTManager()
        manager.loadBuiltInLUTs()
        
        // Wait a moment for async loading
        let expectation = XCTestExpectation(description: "LUTs loaded")
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 3.0)
        
        // Check that LUTs were loaded
        XCTAssertGreaterThan(manager.primaryLUTs.count, 0, "Primary LUTs should be loaded")
        XCTAssertGreaterThan(manager.secondaryLUTs.count, 0, "Secondary LUTs should be loaded")
        
        // Test that at least one LUT has valid properties
        if let firstPrimary = manager.primaryLUTs.first {
            XCTAssertFalse(firstPrimary.name.isEmpty, "Primary LUT should have a valid name")
            XCTAssertTrue(firstPrimary.isBuiltIn, "Primary LUT should be built-in")
        }
        
        if let firstSecondary = manager.secondaryLUTs.first {
            XCTAssertFalse(firstSecondary.name.isEmpty, "Secondary LUT should have a valid name")
            XCTAssertTrue(firstSecondary.isBuiltIn, "Secondary LUT should be built-in")
        }
    }
    
    func testIdentityFilterCreation() throws {
        // Test that identity filter can be created
        let processor = LUTProcessor()
        let identityFilter = try processor.createIdentityFilter()
        XCTAssertNotNil(identityFilter, "Identity filter should be created successfully")
        
        // Test that the filter can process a simple image
        let testImage = CIImage(color: CIColor(red: 0.5, green: 0.5, blue: 0.5)).cropped(to: CGRect(x: 0, y: 0, width: 100, height: 100))
        identityFilter.setValue(testImage, forKey: kCIInputImageKey)
        
        let outputImage = identityFilter.outputImage
        XCTAssertNotNil(outputImage, "Identity filter should produce an output image")
    }

    func testPerformanceExample() throws {
        // This is an example of a performance test case.
        self.measure {
            // Put the code you want to measure the time of here.
        }
    }
}
