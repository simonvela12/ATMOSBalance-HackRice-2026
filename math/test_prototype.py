import unittest
from datetime import date

from prototype import (
    ExpenseEvent,
    FinancialProfile,
    Goal,
    GoalPriority,
    IncomeEvent,
    IncomeType,
    assess_purchase,
    earliest_safe_purchase_date,
    forecast,
)


class FinancialEngineTests(unittest.TestCase):
    def base_profile(self):
        return FinancialProfile(
            current_cash=8000,
            protected_cash=7000,
            safety_buffer=250,
            as_of_date=date(2026, 9, 12),
            income_events=[
                IncomeEvent(1000, date(2026, 11, 1), "Expected income", IncomeType.RECURRING),
            ],
            expense_events=[
                ExpenseEvent(500, date(2026, 11, 15), "Essential living expenses"),
            ],
            goals=[],
        )

    def test_reference_safe_to_spend(self):
        result = forecast(self.base_profile(), date(2026, 11, 30))
        self.assertEqual(result.projected_balance, 8500)
        self.assertEqual(result.safe_to_spend, 1250)

    def test_f1_purchase_is_safe(self):
        result = assess_purchase(self.base_profile(), 450, date(2026, 11, 30))
        self.assertEqual(result.status, "SAFE")
        self.assertEqual(result.remaining_after_purchase, 800)

    def test_purchase_too_large_should_wait(self):
        result = assess_purchase(self.base_profile(), 1300, date(2026, 11, 30))
        self.assertEqual(result.status, "WAIT")
        self.assertEqual(result.shortfall, 50)

    def test_irregular_income_uses_confidence(self):
        profile = self.base_profile()
        profile.income_events = [
            IncomeEvent(1000, date(2026, 11, 1), "Tutoring", IncomeType.IRREGULAR, confidence=0.60),
        ]
        result = forecast(profile, date(2026, 11, 30))
        self.assertEqual(result.expected_income, 600)
        self.assertEqual(result.safe_to_spend, 850)

    def test_past_one_time_income_is_not_counted_again(self):
        profile = self.base_profile()
        profile.income_events.append(
            IncomeEvent(1500, date(2026, 8, 20), "Family transfer", IncomeType.ONE_TIME)
        )
        result = forecast(profile, date(2026, 11, 30))
        self.assertEqual(result.expected_income, 1000)
        self.assertEqual(result.safe_to_spend, 1250)

    def test_mandatory_goal_not_already_protected_is_reserved(self):
        profile = self.base_profile()
        profile.goals = [
            Goal(
                name="Miami",
                target_amount=900,
                current_funded_amount=0,
                deadline=date(2026, 11, 20),
                priority=GoalPriority.MANDATORY,
                already_protected=False,
            )
        ]
        result = forecast(profile, date(2026, 11, 30))
        self.assertEqual(result.mandatory_goal_reserve, 900)
        self.assertEqual(result.safe_to_spend, 350)

    def test_goal_already_inside_protected_cash_is_not_double_counted(self):
        profile = self.base_profile()
        profile.goals = [
            Goal(
                name="Miami",
                target_amount=900,
                current_funded_amount=0,
                deadline=date(2026, 11, 20),
                priority=GoalPriority.MANDATORY,
                already_protected=True,
            )
        ]
        result = forecast(profile, date(2026, 11, 30))
        self.assertEqual(result.mandatory_goal_reserve, 0)
        self.assertEqual(result.safe_to_spend, 1250)

    def test_earliest_safe_date_waits_for_income(self):
        profile = FinancialProfile(
            current_cash=1000,
            protected_cash=800,
            safety_buffer=100,
            as_of_date=date(2026, 9, 12),
            income_events=[
                IncomeEvent(500, date(2026, 10, 1), "Campus job", IncomeType.RECURRING),
            ],
            expense_events=[],
            goals=[],
        )
        recommended = earliest_safe_purchase_date(
            profile,
            amount=400,
            start_date=date(2026, 9, 12),
            end_date=date(2026, 10, 10),
        )
        self.assertEqual(recommended, date(2026, 10, 1))


if __name__ == "__main__":
    unittest.main()
