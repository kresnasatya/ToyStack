import Testing

@testable import Engine

@Suite
struct PresentUploadBudgetTests {
    @Test func presentStopsBeforeExceedingPixelBudget() {
        var budget: PresentUploadBudget = PresentUploadBudget(pixels: 4_000_000)
        let first: Bool = budget.take(pixels: 1_000_000)
        let second: Bool = budget.take(pixels: 2_000_000)
        let third: Bool = budget.take(pixels: 2_000_000)
        #expect(first)
        #expect(second)
        #expect(!third)
        #expect(budget.usedPixels == 3_000_000)
    }

    @Test func generationBudgetAllowsTwoMegapixels() {
        var budget: PresentUploadBudget = PresentUploadBudget(
            pixels: PresentUploadBudget.generationPixels
        )
        let first: Bool = budget.take(pixels: 1_500_000)
        let second: Bool = budget.take(pixels: 1_000_000)
        #expect(first)
        #expect(!second)
        #expect(budget.usedPixels == 1_500_000)
    }

    @Test func oversizedFirstTileStillMakesProgress() {
        var budget: PresentUploadBudget = PresentUploadBudget(pixels: 4_000_000)
        let oversized: Bool = budget.take(pixels: 6_000_000)
        let after: Bool = budget.take(pixels: 1)
        #expect(oversized)
        #expect(!after)
    }

    // MARK: - Whether one present can upload everything left

    @Test func remainingTilesWithinBudgetFitOnePresent() {
        let budget: PresentUploadBudget = PresentUploadBudget(pixels: 4_000_000)
        #expect(budget.admitsAll(pixels: [1_000_000, 3_000_000]))
    }

    @Test func remainingTilesOverBudgetNeedAnotherPresent() {
        let budget: PresentUploadBudget = PresentUploadBudget(pixels: 4_000_000)
        #expect(!budget.admitsAll(pixels: [3_000_000, 1_000_001]))
    }

    /// `take` lets one oversized tile through when it comes first, so a
    /// single oversized tile still finishes in one present.
    @Test func singleOversizedTileFitsOnePresent() {
        let budget: PresentUploadBudget = PresentUploadBudget(pixels: 4_000_000)
        #expect(budget.admitsAll(pixels: [6_000_000]))
    }

    @Test func nothingLeftFitsOnePresent() {
        let budget: PresentUploadBudget = PresentUploadBudget(pixels: 4_000_000)
        #expect(budget.admitsAll(pixels: []))
    }
}
