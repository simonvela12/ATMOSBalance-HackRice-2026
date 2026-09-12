import XCTest
@testable import FinancialCore

final class QualitativeMetadataTests: XCTestCase {
    func testMerchantSuggestionsRemainDeterministicAndExplainable() {
        XCTAssertEqual(QualitativeMetadataSuggester.category(for: "H-E-B Buffalo Speedway"), .food)
        XCTAssertEqual(QualitativeMetadataSuggester.category(for: "Uber"), .transportation)
        XCTAssertEqual(QualitativeMetadataSuggester.category(for: "Spotify"), .subscriptions)
        XCTAssertEqual(QualitativeMetadataSuggester.category(for: "Formula 1 ticket"), .entertainment)
        XCTAssertEqual(QualitativeMetadataSuggester.category(for: "Unknown merchant"), .other)
    }

    func testEmergencyExpenseIsNeverSuggestedAsSavingsCandidate() {
        let metadata = ExpenseQualitativeMetadata(
            category: .health,
            needLevel: .optional,
            flexibility: .flexible,
            planningStatus: .emergency,
            frequency: .oneTime
        )
        XCTAssertFalse(metadata.isExplicitSavingsCandidate)
    }

    func testSavingsCandidateRequiresExplicitOptionalAndFlexibleTags() {
        let candidate = ExpenseQualitativeMetadata(
            category: .entertainment,
            needLevel: .optional,
            flexibility: .flexible,
            planningStatus: .planned,
            frequency: .oneTime
        )
        let important = ExpenseQualitativeMetadata(
            category: .food,
            needLevel: .important,
            flexibility: .flexible,
            planningStatus: .planned,
            frequency: .occasional
        )
        XCTAssertTrue(candidate.isExplicitSavingsCandidate)
        XCTAssertFalse(important.isExplicitSavingsCandidate)
    }

    func testIncomeConfidenceBandsMapToExplicitWeights() {
        XCTAssertEqual(IncomeConfidenceBand.confirmed.confidence, 1.0)
        XCTAssertEqual(IncomeConfidenceBand.likely.confidence, 0.7)
        XCTAssertEqual(IncomeConfidenceBand.possible.confidence, 0.3)
    }
}
