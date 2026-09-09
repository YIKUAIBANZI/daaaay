import DayCore

enum DaylightThemeChecks {
    static func run() {
        assertApprovedPalette()
        assertInteractiveDimensions()
    }

    private static func assertApprovedPalette() {
        XCTAssertEqual(DaylightTokens.canvasHex, "#F7F7F4")
        XCTAssertEqual(DaylightTokens.surfaceHex, "#FFFFFF")
        XCTAssertEqual(DaylightTokens.inkHex, "#151515")
        XCTAssertEqual(DaylightTokens.slateHex, "#747474")
        XCTAssertEqual(DaylightTokens.hairlineHex, "#E8E8E3")
        XCTAssertEqual(DaylightTokens.actionHex, "#0A6CFF")
        XCTAssertEqual(DaylightTokens.livingHex, "#00BFC9")
        XCTAssertEqual(DaylightTokens.sunHex, "#F2B84B")
    }

    private static func assertInteractiveDimensions() {
        XCTAssertEqual(DaylightTokens.primaryHeight, 40)
        XCTAssertEqual(DaylightTokens.minimumTarget, 32)
        precondition(DaylightTokens.primaryHeight >= 40, "Primary actions must remain at least 40pt tall")
        precondition(DaylightTokens.minimumTarget >= 32, "Interactive targets must remain at least 32pt")
    }
}
