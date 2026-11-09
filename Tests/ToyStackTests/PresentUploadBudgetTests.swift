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

    // MARK: - Budget for a staged generation

    /// While the width moves, a heavier present would delay the next
    /// preview, so the budget stays small.
    @Test func movingResizeKeepsTheSmallBudget() {
        let budget: PresentUploadBudget = PresentUploadBudget.generation(resizeSettled: false)
        #expect(budget.pixels == PresentUploadBudget.generationPixels)
    }

    /// A 1440-wide window holds 132 tiles of 256 x 256. Once settled they
    /// must go up in 3 presents, not 5.
    @Test func settledWideWindowUploadsInThreePresents() {
        var left: Int = 132
        var presents: Int = 0
        while left > 0 {
            var budget: PresentUploadBudget = PresentUploadBudget.generation(resizeSettled: true)
            while left > 0, budget.take(pixels: 256 * 256) {
                left -= 1
            }
            presents += 1
        }
        #expect(presents == 3)
    }

    /// After a drag, an older upload with 50 tiles left waits in front of the
    /// final frame. The skip check and the upload use this same budget, so it
    /// must see that those 50 tiles finish in one settled present and keep the
    /// nearly done image instead of dropping it.
    @Test func settledBudgetFinishesFiftyTilesInOnePresent() {
        let budget: PresentUploadBudget = PresentUploadBudget.generation(resizeSettled: true)
        let left: [Int] = Array(repeating: 256 * 256, count: 50)
        #expect(budget.admitsAll(pixels: left))
    }
}
