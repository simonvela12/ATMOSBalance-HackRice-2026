import XCTest
@testable import FinancialCore

final class OverdueGoalTests: XCTestCase {
    private var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        return cal
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    func testOverdueMandatoryGoalRemainsAnImmediateObligation() throws {
        let asOf = date(2026, 9, 12)
        let profile = FinancialProfile(
            currentCash: 1500,
            asOfDate: asOf,
            personalReserveSteps: [
                PersonalReserveStep(effectiveDate: asOf, minimumCash: 500)
            ],
            goals: [
                Goal(
                    name: "Overdue tuition payment",
                    targetAmount: 700,
                    amountAlreadyPaid: 200,
                    deadline: date(2026, 9, 1),
                    priority: .mandatory
                )
            ],
            spendingPolicy: SpendingPolicy(bufferWeeks: 0, manualMinimumBuffer: 100)
        )

        let result = try FinancialEngine.forecast(
            profile: profile,
            targetDate: asOf,
            calendar: calendar
        )

        XCTAssertEqual(result.mandatoryGoalPayments, 500, accuracy: 0.001)
        XCTAssertEqual(result.projectedCash, 1000, accuracy: 0.001)
        XCTAssertEqual(result.recommendedHeadroom, 400, accuracy: 0.001)
    }

    func testOverdueFlexibleGoalIsAssessedAsIfPurchasedNow() throws {
        let asOf = date(2026, 9, 12)
        let goal = Goal(
            name: "Overdue optional trip",
            targetAmount: 300,
            deadline: date(2026, 9, 1),
            priority: .flexible
        )
        let profile = FinancialProfile(
            currentCash: 1000,
            asOfDate: asOf,
            personalReserveSteps: [
                PersonalReserveStep(effectiveDate: asOf, minimumCash: 500)
            ],
            goals: [goal],
            spendingPolicy: SpendingPolicy(bufferWeeks: 0, manualMinimumBuffer: 100)
        )

        let assessment = try FinancialEngine.assessFlexibleGoal(
            profile: profile,
            goal: goal,
            planningHorizon: date(2026, 9, 30),
            calendar: calendar
        )

        XCTAssertEqual(assessment.purchaseAssessment.purchaseDate, asOf)
        XCTAssertEqual(assessment.purchaseAssessment.status, .safe)
        XCTAssertEqual(
            assessment.purchaseAssessment.minimumRecommendedHeadroomAfterPurchase,
            100,
            accuracy: 0.001
        )
    }
}
