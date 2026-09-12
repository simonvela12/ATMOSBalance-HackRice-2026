import XCTest
@testable import Hackathon2026

final class FinancialEngineV2Tests: XCTestCase {
    private let calendar = Calendar(identifier: .gregorian)

    private func makeDate(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    private func emptyProfile(
        currentCash: Double,
        asOfDate: Date,
        reserveSteps: [PersonalReserveStep] = [],
        institutionalMinimums: [InstitutionalMinimum] = [],
        incomeEvents: [V2IncomeEvent] = [],
        expenseEvents: [V2ExpenseEvent] = [],
        goals: [V2Goal] = [],
        weeklySpendingHistory: [WeeklySpendingSample] = [],
        safetyBufferPolicy: SafetyBufferPolicy = SafetyBufferPolicy()
    ) -> FinancialProfileV2 {
        FinancialProfileV2(
            currentCash: currentCash,
            asOfDate: asOfDate,
            personalReserveSteps: reserveSteps,
            institutionalMinimums: institutionalMinimums,
            incomeEvents: incomeEvents,
            expenseEvents: expenseEvents,
            goals: goals,
            weeklySpendingHistory: weeklySpendingHistory,
            safetyBufferPolicy: safetyBufferPolicy
        )
    }

    func testReferenceCheckpointReturns1250RecommendedHeadroom() throws {
        let asOf = makeDate(2026, 9, 12)
        let profile = emptyProfile(
            currentCash: 8000,
            asOfDate: asOf,
            reserveSteps: [
                PersonalReserveStep(effectiveDate: asOf, minimumCash: 7000)
            ],
            incomeEvents: [
                V2IncomeEvent(
                    amount: 1000,
                    date: makeDate(2026, 11, 1),
                    source: "Expected income",
                    type: .recurring
                )
            ],
            expenseEvents: [
                V2ExpenseEvent(
                    amount: 500,
                    date: makeDate(2026, 11, 15),
                    category: "Essential expenses"
                )
            ],
            safetyBufferPolicy: SafetyBufferPolicy(
                weeksOfCoverage: 2,
                manualMinimum: 250
            )
        )

        let result = try FinancialEngineV2.forecast(
            profile: profile,
            targetDate: makeDate(2026, 11, 30),
            calendar: calendar
        )

        XCTAssertEqual(result.projectedCash, 8500, accuracy: 0.001)
        XCTAssertEqual(result.hardFloor, 7000, accuracy: 0.001)
        XCTAssertEqual(result.safetyBuffer, 250, accuracy: 0.001)
        XCTAssertEqual(result.recommendedHeadroom, 1250, accuracy: 0.001)
    }

    func testTypicalWeeklySpendingUsesMedianNotMean() {
        let asOf = makeDate(2026, 9, 1)
        let amounts: [Double] = [80, 95, 87, 92, 410, 90]
        let samples = amounts.enumerated().map { index, amount in
            WeeklySpendingSample(
                weekStart: calendar.date(byAdding: .day, value: -(index * 7), to: asOf)!,
                totalVariableSpending: amount
            )
        }

        let profile = emptyProfile(
            currentCash: 1000,
            asOfDate: asOf,
            weeklySpendingHistory: samples,
            safetyBufferPolicy: SafetyBufferPolicy(weeksOfCoverage: 2)
        )

        XCTAssertEqual(
            FinancialEngineV2.typicalWeeklySpending(profile: profile),
            91,
            accuracy: 0.001
        )
        XCTAssertEqual(
            FinancialEngineV2.safetyBuffer(profile: profile),
            182,
            accuracy: 0.001
        )
    }

    func testReserveCanReleaseOverTimeAndChangesEarliestSafeDate() throws {
        let asOf = makeDate(2027, 1, 1)
        let profile = emptyProfile(
            currentCash: 9000,
            asOfDate: asOf,
            reserveSteps: [
                PersonalReserveStep(
                    effectiveDate: asOf,
                    minimumCash: 8800,
                    note: "Need this runway through February"
                ),
                PersonalReserveStep(
                    effectiveDate: makeDate(2027, 3, 1),
                    minimumCash: 8500,
                    note: "Can release $300 from March"
                )
            ],
            safetyBufferPolicy: SafetyBufferPolicy(weeksOfCoverage: 0)
        )

        let assessment = try FinancialEngineV2.assessPurchase(
            profile: profile,
            amount: 300,
            purchaseDate: makeDate(2027, 2, 1),
            planningHorizon: makeDate(2027, 4, 1),
            calendar: calendar
        )

        XCTAssertEqual(assessment.status, .notSafe)
        XCTAssertEqual(assessment.shortfallToHardFloor, 100, accuracy: 0.001)
        XCTAssertEqual(assessment.recommendedDate, makeDate(2027, 3, 1))
    }

    func testInstitutionalMinimumCreatesTightZoneBeforeHardFailure() throws {
        let asOf = makeDate(2026, 9, 1)
        let profile = emptyProfile(
            currentCash: 900,
            asOfDate: asOf,
            institutionalMinimums: [
                InstitutionalMinimum(
                    name: "Bank account status",
                    minimumBalance: 500,
                    startDate: asOf
                )
            ],
            safetyBufferPolicy: SafetyBufferPolicy(
                weeksOfCoverage: 0,
                manualMinimum: 200
            )
        )

        let tight = try FinancialEngineV2.assessPurchase(
            profile: profile,
            amount: 300,
            purchaseDate: makeDate(2026, 9, 2),
            planningHorizon: makeDate(2026, 9, 30),
            calendar: calendar
        )
        XCTAssertEqual(tight.status, .tight)
        XCTAssertEqual(tight.minimumHardHeadroomAfterPurchase, 100, accuracy: 0.001)
        XCTAssertEqual(tight.minimumRecommendedHeadroomAfterPurchase, -100, accuracy: 0.001)

        let unsafe = try FinancialEngineV2.assessPurchase(
            profile: profile,
            amount: 450,
            purchaseDate: makeDate(2026, 9, 2),
            planningHorizon: makeDate(2026, 9, 30),
            calendar: calendar
        )
        XCTAssertEqual(unsafe.status, .notSafe)
        XCTAssertEqual(unsafe.shortfallToHardFloor, 50, accuracy: 0.001)
    }

    func testReimbursementStillCreatesTemporaryLiquidityDip() throws {
        let asOf = makeDate(2026, 9, 1)
        let profile = emptyProfile(
            currentCash: 1000,
            asOfDate: asOf,
            reserveSteps: [
                PersonalReserveStep(effectiveDate: asOf, minimumCash: 500)
            ],
            incomeEvents: [
                V2IncomeEvent(
                    amount: 300,
                    date: makeDate(2026, 9, 20),
                    source: "Family reimbursement",
                    type: .oneTime
                )
            ],
            expenseEvents: [
                V2ExpenseEvent(
                    amount: 300,
                    date: makeDate(2026, 9, 10),
                    category: "Reimbursable purchase",
                    reimbursable: true,
                    extraordinary: true
                )
            ],
            safetyBufferPolicy: SafetyBufferPolicy(
                weeksOfCoverage: 0,
                manualMinimum: 100
            )
        )

        let duringDip = try FinancialEngineV2.forecast(
            profile: profile,
            targetDate: makeDate(2026, 9, 15),
            calendar: calendar
        )
        XCTAssertEqual(duringDip.projectedCash, 700, accuracy: 0.001)
        XCTAssertEqual(duringDip.recommendedHeadroom, 100, accuracy: 0.001)

        let afterReimbursement = try FinancialEngineV2.forecast(
            profile: profile,
            targetDate: makeDate(2026, 10, 1),
            calendar: calendar
        )
        XCTAssertEqual(afterReimbursement.projectedCash, 1000, accuracy: 0.001)
        XCTAssertEqual(afterReimbursement.recommendedHeadroom, 400, accuracy: 0.001)
    }

    func testMandatoryGoalIsRealFutureCashOutflow() throws {
        let asOf = makeDate(2026, 9, 1)
        let profile = emptyProfile(
            currentCash: 2000,
            asOfDate: asOf,
            reserveSteps: [
                PersonalReserveStep(effectiveDate: asOf, minimumCash: 500)
            ],
            goals: [
                V2Goal(
                    name: "Must happen trip",
                    targetAmount: 900,
                    deadline: makeDate(2026, 10, 1),
                    priority: .mandatory
                )
            ],
            safetyBufferPolicy: SafetyBufferPolicy(
                weeksOfCoverage: 0,
                manualMinimum: 200
            )
        )

        let result = try FinancialEngineV2.forecast(
            profile: profile,
            targetDate: makeDate(2026, 10, 2),
            calendar: calendar
        )
        XCTAssertEqual(result.projectedCash, 1100, accuracy: 0.001)
        XCTAssertEqual(result.hardHeadroom, 600, accuracy: 0.001)
        XCTAssertEqual(result.recommendedHeadroom, 400, accuracy: 0.001)

        let tightPurchase = try FinancialEngineV2.assessPurchase(
            profile: profile,
            amount: 500,
            purchaseDate: makeDate(2026, 9, 10),
            planningHorizon: makeDate(2026, 10, 2),
            calendar: calendar
        )
        XCTAssertEqual(tightPurchase.status, .tight)

        let unsafePurchase = try FinancialEngineV2.assessPurchase(
            profile: profile,
            amount: 700,
            purchaseDate: makeDate(2026, 9, 10),
            planningHorizon: makeDate(2026, 10, 2),
            calendar: calendar
        )
        XCTAssertEqual(unsafePurchase.status, .notSafe)
    }

    func testFlexibleGoalDoesNotPolluteBaselineButCanBeAssessed() throws {
        let asOf = makeDate(2026, 9, 1)
        let goal = V2Goal(
            name: "Nice-to-have trip",
            targetAmount: 900,
            deadline: makeDate(2026, 10, 1),
            priority: .flexible
        )
        let profile = emptyProfile(
            currentCash: 2000,
            asOfDate: asOf,
            reserveSteps: [
                PersonalReserveStep(effectiveDate: asOf, minimumCash: 500)
            ],
            goals: [goal],
            safetyBufferPolicy: SafetyBufferPolicy(
                weeksOfCoverage: 0,
                manualMinimum: 200
            )
        )

        let baseline = try FinancialEngineV2.forecast(
            profile: profile,
            targetDate: makeDate(2026, 10, 2),
            calendar: calendar
        )
        XCTAssertEqual(baseline.projectedCash, 2000, accuracy: 0.001)

        let goalAssessment = try FinancialEngineV2.assessFlexibleGoal(
            profile: profile,
            goal: goal,
            planningHorizon: makeDate(2026, 10, 2),
            calendar: calendar
        )
        XCTAssertEqual(goalAssessment.purchaseAssessment.status, .safe)
    }

    func testIrregularIncomeUsesConfidence() throws {
        let asOf = makeDate(2026, 9, 12)
        let profile = emptyProfile(
            currentCash: 1000,
            asOfDate: asOf,
            incomeEvents: [
                V2IncomeEvent(
                    amount: 1000,
                    date: makeDate(2026, 10, 1),
                    source: "Tutoring",
                    type: .irregular,
                    confidence: 0.6
                )
            ],
            safetyBufferPolicy: SafetyBufferPolicy(weeksOfCoverage: 0)
        )

        let result = try FinancialEngineV2.forecast(
            profile: profile,
            targetDate: makeDate(2026, 10, 2),
            calendar: calendar
        )
        XCTAssertEqual(result.expectedIncome, 600, accuracy: 0.001)
    }

    func testPastOneTimeIncomeIsNotCountedAgain() throws {
        let asOf = makeDate(2026, 9, 12)
        let profile = emptyProfile(
            currentCash: 3000,
            asOfDate: asOf,
            incomeEvents: [
                V2IncomeEvent(
                    amount: 1500,
                    date: makeDate(2026, 8, 20),
                    source: "Past transfer",
                    type: .oneTime
                )
            ],
            safetyBufferPolicy: SafetyBufferPolicy(weeksOfCoverage: 0)
        )

        let result = try FinancialEngineV2.forecast(
            profile: profile,
            targetDate: makeDate(2026, 10, 1),
            calendar: calendar
        )
        XCTAssertEqual(result.expectedIncome, 0, accuracy: 0.001)
    }

    func testVariableSpendingIsProjectedAcrossTime() throws {
        let asOf = makeDate(2026, 9, 1)
        let samples = (0..<6).map { index in
            WeeklySpendingSample(
                weekStart: calendar.date(byAdding: .day, value: -(index * 7), to: asOf)!,
                totalVariableSpending: 70
            )
        }
        let profile = emptyProfile(
            currentCash: 2000,
            asOfDate: asOf,
            weeklySpendingHistory: samples,
            safetyBufferPolicy: SafetyBufferPolicy(weeksOfCoverage: 2)
        )

        let result = try FinancialEngineV2.forecast(
            profile: profile,
            targetDate: makeDate(2026, 9, 15),
            calendar: calendar
        )

        XCTAssertEqual(result.projectedVariableSpending, 140, accuracy: 0.001)
        XCTAssertEqual(result.safetyBuffer, 140, accuracy: 0.001)
        XCTAssertEqual(result.projectedCash, 1860, accuracy: 0.001)
        XCTAssertEqual(result.recommendedHeadroom, 1720, accuracy: 0.001)
    }

    func testHardFloorUsesMaxOfPersonalReserveAndInstitutionalMinimums() throws {
        let asOf = makeDate(2026, 9, 1)
        let profile = emptyProfile(
            currentCash: 2000,
            asOfDate: asOf,
            reserveSteps: [
                PersonalReserveStep(effectiveDate: asOf, minimumCash: 1200)
            ],
            institutionalMinimums: [
                InstitutionalMinimum(
                    name: "Checking minimum",
                    minimumBalance: 500,
                    startDate: asOf
                )
            ],
            safetyBufferPolicy: SafetyBufferPolicy(weeksOfCoverage: 0)
        )

        let result = try FinancialEngineV2.forecast(
            profile: profile,
            targetDate: makeDate(2026, 9, 2),
            calendar: calendar
        )
        XCTAssertEqual(result.hardFloor, 1200, accuracy: 0.001)
    }
}
