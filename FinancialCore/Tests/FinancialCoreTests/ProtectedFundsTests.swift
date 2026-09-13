import XCTest
@testable import FinancialCore

final class ProtectedFundsTests: XCTestCase {
    func testMandatoryGoalIsProtectedImmediatelyAndNotDoubleCountedAtDeadline() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let asOf = calendar.date(from: DateComponents(year: 2026, month: 9, day: 12))!
        let deadline = calendar.date(from: DateComponents(year: 2026, month: 12, day: 26))!
        let profile = FinancialProfile(currentCash: 2_350, asOfDate: asOf, goals: [Goal(name: "Tuition", targetAmount: 1_000, deadline: deadline, priority: .mandatory, flexibility: .low)], spendingPolicy: SpendingPolicy(bufferWeeks: 0))

        XCTAssertEqual(FinancialEngine.liquidCashToday(profile: profile), 1_350, accuracy: 0.001)
        let result = try FinancialEngine.forecast(profile: profile, targetDate: deadline, calendar: calendar)
        XCTAssertEqual(result.projectedCash, 1_350, accuracy: 0.001)
        XCTAssertEqual(result.hardFloor, 0, accuracy: 0.001)
    }
}
