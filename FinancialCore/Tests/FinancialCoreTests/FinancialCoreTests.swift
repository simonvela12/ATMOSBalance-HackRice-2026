import XCTest
@testable import FinancialCore

final class FinancialCoreTests: XCTestCase {
    private var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        return cal
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    func testReferenceCheckpointForecastIs1250AtTargetDate() throws {
        let asOf = date(2026, 9, 12)
        let profile = FinancialProfile(
            currentCash: 8000,
            asOfDate: asOf,
            personalReserveSteps: [
                PersonalReserveStep(effectiveDate: asOf, minimumCash: 7000)
            ],
            incomeEvents: [
                IncomeEvent(
                    amount: 1000,
                    date: date(2026, 11, 1),
                    source: "Expected income",
                    type: .recurring
                )
            ],
            expenseEvents: [
                ExpenseEvent(
                    amount: 500,
                    date: date(2026, 11, 15),
                    category: "Essential"
                )
            ],
            spendingPolicy: SpendingPolicy(
                lookbackWeeks: 6,
                bufferWeeks: 0,
                manualMinimumBuffer: 250
            )
        )

        let result = try FinancialEngine.forecast(
            profile: profile,
            targetDate: date(2026, 11, 30),
            calendar: calendar
        )

        XCTAssertEqual(result.projectedCash, 8500, accuracy: 0.001)
        XCTAssertEqual(result.recommendedHeadroom, 1250, accuracy: 0.001)
    }

    func testPathSafeToSpendCanBeLowerThanTargetDateHeadroom() throws {
        let asOf = date(2026, 9, 12)
        let profile = FinancialProfile(
            currentCash: 8000,
            asOfDate: asOf,
            personalReserveSteps: [
                PersonalReserveStep(effectiveDate: asOf, minimumCash: 7000)
            ],
            incomeEvents: [
                IncomeEvent(amount: 1000, date: date(2026, 11, 1), source: "Income", type: .recurring)
            ],
            expenseEvents: [
                ExpenseEvent(amount: 500, date: date(2026, 11, 15), category: "Bill")
            ],
            spendingPolicy: SpendingPolicy(bufferWeeks: 0, manualMinimumBuffer: 250)
        )

        let targetForecast = try FinancialEngine.forecast(
            profile: profile,
            targetDate: date(2026, 11, 30),
            calendar: calendar
        )
        let safeNow = try FinancialEngine.safeToSpend(
            profile: profile,
            from: asOf,
            through: date(2026, 11, 30),
            calendar: calendar
        )

        XCTAssertEqual(targetForecast.recommendedHeadroom, 1250, accuracy: 0.001)
        XCTAssertEqual(safeNow, 750, accuracy: 0.001)
    }

    func testMedianSpendingUsesOnlyLookbackWindowAndExclusions() {
        let asOf = date(2026, 9, 30)
        let recent = [80.0, 95, 87, 92, 410, 90].enumerated().map { index, amount in
            WeeklySpendingSample(
                weekStart: calendar.date(byAdding: .day, value: -(index * 7), to: asOf)!,
                totalVariableSpending: amount
            )
        }
        let old = WeeklySpendingSample(
            weekStart: date(2026, 6, 1),
            totalVariableSpending: 9999
        )
        let excluded = WeeklySpendingSample(
            weekStart: date(2026, 9, 29),
            totalVariableSpending: 5000,
            excludedFromBaseline: true
        )
        let profile = FinancialProfile(
            currentCash: 1000,
            asOfDate: asOf,
            weeklySpendingHistory: recent + [old, excluded],
            spendingPolicy: SpendingPolicy(lookbackWeeks: 6, bufferWeeks: 2)
        )

        XCTAssertEqual(
            FinancialEngine.typicalWeeklySpending(profile: profile, calendar: calendar),
            91,
            accuracy: 0.001
        )
        XCTAssertEqual(
            FinancialEngine.safetyBuffer(profile: profile, calendar: calendar),
            182,
            accuracy: 0.001
        )
    }

    func testManualSafetyBufferActsAsFloor() {
        let profile = FinancialProfile(
            currentCash: 1000,
            asOfDate: date(2026, 9, 1),
            weeklySpendingHistory: [
                WeeklySpendingSample(weekStart: date(2026, 8, 25), totalVariableSpending: 50)
            ],
            spendingPolicy: SpendingPolicy(lookbackWeeks: 6, bufferWeeks: 2, manualMinimumBuffer: 200)
        )

        XCTAssertEqual(
            FinancialEngine.safetyBuffer(profile: profile, calendar: calendar),
            200,
            accuracy: 0.001
        )
    }

    func testReserveReleaseChangesEarliestSafeDate() throws {
        let asOf = date(2027, 1, 1)
        let profile = FinancialProfile(
            currentCash: 9000,
            asOfDate: asOf,
            personalReserveSteps: [
                PersonalReserveStep(effectiveDate: asOf, minimumCash: 8800),
                PersonalReserveStep(effectiveDate: date(2027, 3, 1), minimumCash: 8500)
            ],
            spendingPolicy: SpendingPolicy(bufferWeeks: 0)
        )

        let result = try FinancialEngine.assessPurchase(
            profile: profile,
            amount: 300,
            purchaseDate: date(2027, 2, 1),
            planningHorizon: date(2027, 4, 1),
            calendar: calendar
        )

        XCTAssertEqual(result.status, .notSafe)
        XCTAssertEqual(result.shortfallToHardFloor, 100, accuracy: 0.001)
        XCTAssertEqual(result.recommendedDate, date(2027, 3, 1))
    }

    func testReserveIncreaseCanMakePurchaseUnsafeLater() throws {
        let asOf = date(2026, 9, 1)
        let profile = FinancialProfile(
            currentCash: 2000,
            asOfDate: asOf,
            personalReserveSteps: [
                PersonalReserveStep(effectiveDate: asOf, minimumCash: 500),
                PersonalReserveStep(effectiveDate: date(2026, 10, 1), minimumCash: 1500)
            ],
            spendingPolicy: SpendingPolicy(bufferWeeks: 0)
        )

        let result = try FinancialEngine.assessPurchase(
            profile: profile,
            amount: 600,
            purchaseDate: date(2026, 9, 10),
            planningHorizon: date(2026, 10, 2),
            calendar: calendar
        )

        XCTAssertEqual(result.status, .notSafe)
        XCTAssertEqual(result.shortfallToHardFloor, 100, accuracy: 0.001)
        XCTAssertEqual(result.tightestHardDate, date(2026, 10, 1))
    }

    func testInstitutionalMinimumCreatesTightAndNotSafeZones() throws {
        let asOf = date(2026, 9, 1)
        let profile = FinancialProfile(
            currentCash: 900,
            asOfDate: asOf,
            institutionalMinimums: [
                InstitutionalMinimum(name: "Bank minimum", minimumBalance: 500, startDate: asOf)
            ],
            spendingPolicy: SpendingPolicy(bufferWeeks: 0, manualMinimumBuffer: 200)
        )

        let tight = try FinancialEngine.assessPurchase(
            profile: profile,
            amount: 300,
            purchaseDate: date(2026, 9, 2),
            planningHorizon: date(2026, 9, 30),
            calendar: calendar
        )
        XCTAssertEqual(tight.status, .tight)

        let notSafe = try FinancialEngine.assessPurchase(
            profile: profile,
            amount: 450,
            purchaseDate: date(2026, 9, 2),
            planningHorizon: date(2026, 9, 30),
            calendar: calendar
        )
        XCTAssertEqual(notSafe.status, .notSafe)
        XCTAssertEqual(notSafe.shortfallToHardFloor, 50, accuracy: 0.001)
    }

    func testMultipleInstitutionalMinimumsAreSummed() {
        let asOf = date(2026, 9, 1)
        let profile = FinancialProfile(
            currentCash: 2000,
            asOfDate: asOf,
            institutionalMinimums: [
                InstitutionalMinimum(name: "Checking", minimumBalance: 500, startDate: asOf),
                InstitutionalMinimum(name: "Card relationship", minimumBalance: 250, startDate: asOf)
            ]
        )

        XCTAssertEqual(
            FinancialEngine.institutionalMinimum(profile: profile, on: asOf),
            750,
            accuracy: 0.001
        )
    }

    func testHardFloorUsesMaxRatherThanDoubleCountingPersonalReserve() {
        let asOf = date(2026, 9, 1)
        let profile = FinancialProfile(
            currentCash: 2000,
            asOfDate: asOf,
            personalReserveSteps: [
                PersonalReserveStep(effectiveDate: asOf, minimumCash: 1200)
            ],
            institutionalMinimums: [
                InstitutionalMinimum(name: "Checking", minimumBalance: 500, startDate: asOf)
            ]
        )

        XCTAssertEqual(
            FinancialEngine.hardFloor(profile: profile, on: asOf),
            1200,
            accuracy: 0.001
        )
    }

    func testReimbursementDoesNotHideTemporaryLiquidityDip() throws {
        let asOf = date(2026, 9, 1)
        let profile = FinancialProfile(
            currentCash: 1000,
            asOfDate: asOf,
            personalReserveSteps: [
                PersonalReserveStep(effectiveDate: asOf, minimumCash: 500)
            ],
            incomeEvents: [
                IncomeEvent(amount: 300, date: date(2026, 9, 20), source: "Family reimbursement", type: .oneTime)
            ],
            expenseEvents: [
                ExpenseEvent(
                    amount: 300,
                    date: date(2026, 9, 10),
                    category: "Reimbursable",
                    reimbursable: true,
                    extraordinary: true
                )
            ],
            spendingPolicy: SpendingPolicy(bufferWeeks: 0, manualMinimumBuffer: 100)
        )

        let horizon = try FinancialEngine.minimumHeadroom(
            profile: profile,
            from: asOf,
            through: date(2026, 10, 1),
            calendar: calendar
        )

        XCTAssertEqual(horizon.minimumRecommendedHeadroom, 100, accuracy: 0.001)
        XCTAssertEqual(horizon.tightestRecommendedDate, date(2026, 9, 10))

        let after = try FinancialEngine.forecast(
            profile: profile,
            targetDate: date(2026, 10, 1),
            calendar: calendar
        )
        XCTAssertEqual(after.projectedCash, 1000, accuracy: 0.001)
    }

    func testMandatoryGoalIsBaselineOutflowWhileFlexibleGoalIsScenario() throws {
        let asOf = date(2026, 9, 1)
        let mandatory = Goal(
            name: "Tuition",
            targetAmount: 900,
            deadline: date(2026, 10, 1),
            priority: .mandatory
        )
        let flexible = Goal(
            name: "Trip",
            targetAmount: 500,
            deadline: date(2026, 10, 1),
            priority: .flexible
        )
        let profile = FinancialProfile(
            currentCash: 2000,
            asOfDate: asOf,
            personalReserveSteps: [
                PersonalReserveStep(effectiveDate: asOf, minimumCash: 500)
            ],
            goals: [mandatory, flexible],
            spendingPolicy: SpendingPolicy(bufferWeeks: 0, manualMinimumBuffer: 200)
        )

        let baseline = try FinancialEngine.forecast(
            profile: profile,
            targetDate: date(2026, 10, 2),
            calendar: calendar
        )
        XCTAssertEqual(baseline.projectedCash, 1100, accuracy: 0.001)

        let flexibleAssessment = try FinancialEngine.assessFlexibleGoal(
            profile: profile,
            goal: flexible,
            planningHorizon: date(2026, 10, 2),
            calendar: calendar
        )
        XCTAssertEqual(flexibleAssessment.purchaseAssessment.status, .tight)
    }

    func testIrregularIncomeUsesConfidenceAndPastOneTimeIsNotReused() throws {
        let asOf = date(2026, 9, 12)
        let profile = FinancialProfile(
            currentCash: 1000,
            asOfDate: asOf,
            incomeEvents: [
                IncomeEvent(amount: 1500, date: date(2026, 8, 20), source: "Past transfer", type: .oneTime),
                IncomeEvent(amount: 1000, date: date(2026, 10, 1), source: "Tutoring", type: .irregular, confidence: 0.6)
            ],
            spendingPolicy: SpendingPolicy(bufferWeeks: 0)
        )

        let result = try FinancialEngine.forecast(
            profile: profile,
            targetDate: date(2026, 10, 2),
            calendar: calendar
        )

        XCTAssertEqual(result.expectedIncome, 600, accuracy: 0.001)
        XCTAssertEqual(result.projectedCash, 1600, accuracy: 0.001)
    }

    func testLaterIncomeCannotRescueEarlierHardFloorViolation() throws {
        let asOf = date(2026, 9, 1)
        let profile = FinancialProfile(
            currentCash: 700,
            asOfDate: asOf,
            personalReserveSteps: [
                PersonalReserveStep(effectiveDate: asOf, minimumCash: 500)
            ],
            incomeEvents: [
                IncomeEvent(amount: 1000, date: date(2026, 9, 20), source: "Later income", type: .oneTime)
            ],
            expenseEvents: [
                ExpenseEvent(amount: 250, date: date(2026, 9, 10), category: "Early bill")
            ],
            spendingPolicy: SpendingPolicy(bufferWeeks: 0)
        )

        let final = try FinancialEngine.forecast(
            profile: profile,
            targetDate: date(2026, 9, 30),
            calendar: calendar
        )
        XCTAssertEqual(final.hardHeadroom, 950, accuracy: 0.001)

        let path = try FinancialEngine.minimumHeadroom(
            profile: profile,
            from: asOf,
            through: date(2026, 9, 30),
            calendar: calendar
        )
        XCTAssertEqual(path.minimumHardHeadroom, -50, accuracy: 0.001)
        XCTAssertEqual(path.tightestHardDate, date(2026, 9, 10))
    }

    func testScenarioLayerCanProduceDifferentPurchaseStatuses() throws {
        let asOf = date(2026, 9, 1)
        let spending = [50.0, 50, 50, 50, 50, 50].enumerated().map { index, amount in
            WeeklySpendingSample(
                weekStart: calendar.date(byAdding: .day, value: -(index * 7), to: asOf)!,
                totalVariableSpending: amount
            )
        }
        let profile = FinancialProfile(
            currentCash: 1000,
            asOfDate: asOf,
            personalReserveSteps: [
                PersonalReserveStep(effectiveDate: asOf, minimumCash: 500)
            ],
            incomeEvents: [
                IncomeEvent(
                    amount: 300,
                    date: date(2026, 9, 2),
                    source: "Irregular job",
                    type: .irregular,
                    confidence: 0.3
                )
            ],
            weeklySpendingHistory: spending,
            spendingPolicy: SpendingPolicy(lookbackWeeks: 6, bufferWeeks: 0, manualMinimumBuffer: 100)
        )

        let conservative = try FinancialScenarioEngine.assessPurchase(
            profile: profile,
            amount: 500,
            purchaseDate: date(2026, 9, 3),
            planningHorizon: date(2026, 9, 3),
            scenario: .conservative,
            calendar: calendar
        )
        let expected = try FinancialScenarioEngine.assessPurchase(
            profile: profile,
            amount: 500,
            purchaseDate: date(2026, 9, 3),
            planningHorizon: date(2026, 9, 3),
            scenario: .expected,
            calendar: calendar
        )
        let optimistic = try FinancialScenarioEngine.assessPurchase(
            profile: profile,
            amount: 500,
            purchaseDate: date(2026, 9, 3),
            planningHorizon: date(2026, 9, 3),
            scenario: .optimistic,
            calendar: calendar
        )

        XCTAssertEqual(conservative.assessment.status, .notSafe)
        XCTAssertEqual(expected.assessment.status, .tight)
        XCTAssertEqual(optimistic.assessment.status, .safe)
    }

    func testNegativePurchaseIsRejected() {
        let asOf = date(2026, 9, 1)
        let profile = FinancialProfile(currentCash: 1000, asOfDate: asOf)

        XCTAssertThrowsError(
            try FinancialEngine.assessPurchase(
                profile: profile,
                amount: -1,
                purchaseDate: asOf,
                planningHorizon: date(2026, 9, 2),
                calendar: calendar
            )
        ) { error in
            XCTAssertEqual(error as? FinancialEngineError, .negativeAmount)
        }
    }
}
