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
}
