import XCTest

final class UsageFormatTests: XCTestCase {

    // MARK: - Token abbreviation

    /// The regression this guards: a single "%.0fK" rule across the whole thousands
    /// range rendered 1,400 as "1K" — a 29% error on a number shown at 32pt.
    func test_tokens_lowThousands_keepOneDecimal() {
        XCTAssertEqual(UsageFormat.tokens(1_400), "1.4K")
        XCTAssertEqual(UsageFormat.tokens(1_000), "1.0K")
        XCTAssertEqual(UsageFormat.tokens(9_900), "9.9K")
        XCTAssertEqual(UsageFormat.tokens(99_900), "99.9K")
    }

    /// Above 100K a decimal is noise, so it drops.
    func test_tokens_highThousands_dropDecimal() {
        XCTAssertEqual(UsageFormat.tokens(100_000), "100K")
        XCTAssertEqual(UsageFormat.tokens(240_000), "240K")
    }

    /// Must roll over to millions rather than printing "1000K".
    func test_tokens_rollsOverToMillions() {
        XCTAssertEqual(UsageFormat.tokens(999_900), "1.0M")
        XCTAssertEqual(UsageFormat.tokens(1_000_000), "1.0M")
        XCTAssertEqual(UsageFormat.tokens(2_400_000), "2.4M")
        XCTAssertEqual(UsageFormat.tokens(90_800_000), "90.8M")
    }

    func test_tokens_belowThousand_isExact() {
        XCTAssertEqual(UsageFormat.tokens(0), "0")
        XCTAssertEqual(UsageFormat.tokens(950), "950")
        XCTAssertEqual(UsageFormat.tokens(999), "999")
    }

    /// No range may print a stray extra decimal — 99,999 must read "100K", not "100.0K",
    /// and nothing may render as "1000K" instead of rolling over.
    func test_tokens_boundariesRollOverCleanly() {
        XCTAssertEqual(UsageFormat.tokens(99_949), "99.9K")
        XCTAssertEqual(UsageFormat.tokens(99_950), "100K")
        XCTAssertEqual(UsageFormat.tokens(99_999), "100K")
        XCTAssertEqual(UsageFormat.tokens(999_499), "999K")
        XCTAssertEqual(UsageFormat.tokens(999_500), "1.0M")
    }

    /// The rendered value must never go backwards as the input grows. Adjacent inputs may
    /// share a string (both round to "1.0M") — that's abbreviation, not a defect — but a
    /// larger count must never read as a smaller number.
    func test_tokens_neverDecreases() {
        var previous = 0.0
        for n in stride(from: 0, through: 5_000_000, by: 137) {
            let s = UsageFormat.tokens(n)
            let scale: Double = s.hasSuffix("M") ? 1_000_000 : (s.hasSuffix("K") ? 1_000 : 1)
            let magnitude = Double(s.trimmingCharacters(in: CharacterSet(charactersIn: "MK")))! * scale
            XCTAssertGreaterThanOrEqual(magnitude, previous, "\(n) → \(s) went backwards")
            previous = magnitude
        }
    }

    // MARK: - Cost

    func test_cost_keepsCentsBelowHundred() {
        XCTAssertTrue(UsageFormat.cost(24.0).contains("24.00"), UsageFormat.cost(24.0))
        XCTAssertTrue(UsageFormat.cost(0.4).contains("0.40"), UsageFormat.cost(0.4))
    }

    /// Cents are noise at this magnitude, and the grouping separator has to appear —
    /// "$2427.67" was the old output for the app's most-read figure.
    func test_cost_dropsCentsAndGroupsAboveHundred() {
        let s = UsageFormat.cost(2_427.67)
        XCTAssertFalse(s.contains(".67"), s)
        XCTAssertTrue(s.contains("2") && s.contains("428"), s)
    }

    // MARK: - Coarse remaining

    func test_remainingCoarse_daysAndHours() {
        let now = Date()
        XCTAssertEqual(UsageFormat.remainingCoarse(until: now.addingTimeInterval(2 * 86400 + 4 * 3600), from: now), "2d 4h")
        XCTAssertEqual(UsageFormat.remainingCoarse(until: now.addingTimeInterval(18 * 3600), from: now), "18h")
        XCTAssertEqual(UsageFormat.remainingCoarse(until: now.addingTimeInterval(120), from: now), "<1h")
        XCTAssertEqual(UsageFormat.remainingCoarse(until: now.addingTimeInterval(-60), from: now), "now")
    }
}

// MARK: - Design tokens

final class UsageLevelTests: XCTestCase {
    /// One threshold ladder, replacing three hand-copied versions that had begun to drift.
    func test_thresholds() {
        XCTAssertEqual(UsageLevel(0.0), .normal)
        XCTAssertEqual(UsageLevel(0.79), .normal)
        XCTAssertEqual(UsageLevel(0.8), .warning)
        XCTAssertEqual(UsageLevel(0.99), .warning)
        XCTAssertEqual(UsageLevel(1.0), .over)
        XCTAssertEqual(UsageLevel(1.4), .over)
    }

    /// Colour must never be the only carrier of the signal.
    func test_everyLevelHasAWord() {
        XCTAssertEqual(UsageLevel.normal.word, "OK")
        XCTAssertFalse(UsageLevel.warning.word.isEmpty)
        XCTAssertFalse(UsageLevel.over.word.isEmpty)
    }

    /// A healthy app renders no status indicator at all — an always-present dot is one
    /// nobody reads.
    func test_activeStatusRendersNoIndicator() {
        XCTAssertNil(OverallStatus.active.indicator)
        XCTAssertNotNil(OverallStatus.rateLimited.indicator)
        XCTAssertNotNil(OverallStatus.noLocalData.indicator)
    }
}

extension UsageLevel: Equatable {}
