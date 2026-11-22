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

    @Test func singleOversizedTileFitsOnePresent() {
        let budget: PresentUploadBudget = PresentUploadBudget(pixels: 4_000_000)
        #expect(budget.admitsAll(pixels: [6_000_000]))
    }

    @Test func nothingLeftFitsOnePresent() {
        let budget: PresentUploadBudget = PresentUploadBudget(pixels: 4_000_000)
        #expect(budget.admitsAll(pixels: []))
    }

    // MARK: - Budget for a staged generation

    @Test func movingResizeKeepsTheSmallBudget() {
        let budget: PresentUploadBudget = PresentUploadBudget.generation(resizeSettled: false)
        #expect(budget.pixels == PresentUploadBudget.generationPixels)
    }

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

    @Test func settledBudgetFinishesFiftyTilesInOnePresent() {
        let budget: PresentUploadBudget = PresentUploadBudget.generation(resizeSettled: true)
        let left: [Int] = Array(repeating: 256 * 256, count: 50)
        #expect(budget.admitsAll(pixels: left))
    }
}
