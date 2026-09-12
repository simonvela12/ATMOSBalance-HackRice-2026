from dataclasses import dataclass
from datetime import date, timedelta
from enum import Enum
from typing import List, Optional


class IncomeType(str, Enum):
    RECURRING = "recurring"
    IRREGULAR = "irregular"
    ONE_TIME = "oneTime"


class GoalPriority(str, Enum):
    MANDATORY = "mandatory"
    FLEXIBLE = "flexible"


@dataclass
class IncomeEvent:
    amount: float
    event_date: date
    source: str
    income_type: IncomeType
    confidence: float = 1.0

    def adjusted_amount(self) -> float:
        if not 0 <= self.confidence <= 1:
            raise ValueError("confidence must be between 0 and 1")
        if self.income_type == IncomeType.IRREGULAR:
            return self.amount * self.confidence
        return self.amount


@dataclass
class ExpenseEvent:
    amount: float
    event_date: date
    category: str
    essential: bool = True
    committed: bool = True


@dataclass
class Goal:
    name: str
    target_amount: float
    current_funded_amount: float
    deadline: date
    priority: GoalPriority
    already_protected: bool = False

    @property
    def remaining_funding(self) -> float:
        return max(0.0, self.target_amount - self.current_funded_amount)


@dataclass
class FinancialProfile:
    current_cash: float
    protected_cash: float
    safety_buffer: float
    as_of_date: date
    income_events: List[IncomeEvent]
    expense_events: List[ExpenseEvent]
    goals: List[Goal]


@dataclass
class ForecastResult:
    target_date: date
    expected_income: float
    committed_expenses: float
    mandatory_goal_reserve: float
    projected_balance: float
    protected_cash: float
    safety_buffer: float
    safe_to_spend: float


@dataclass
class PurchaseAssessment:
    status: str
    purchase_amount: float
    purchase_date: date
    safe_to_spend_before_purchase: float
    remaining_after_purchase: float
    shortfall: float
    recommended_date: Optional[date] = None


def expected_income(profile: FinancialProfile, target_date: date) -> float:
    total = 0.0
    for income in profile.income_events:
        # Past income is assumed to already be reflected in current_cash.
        if profile.as_of_date < income.event_date <= target_date:
            total += income.adjusted_amount()
    return total


def committed_expenses(profile: FinancialProfile, target_date: date) -> float:
    return sum(
        expense.amount
        for expense in profile.expense_events
        if expense.committed and profile.as_of_date < expense.event_date <= target_date
    )


def mandatory_goal_reserve(profile: FinancialProfile, target_date: date) -> float:
    total = 0.0
    for goal in profile.goals:
        if (
            goal.priority == GoalPriority.MANDATORY
            and not goal.already_protected
            and goal.deadline <= target_date
        ):
            total += goal.remaining_funding
    return total


def forecast(profile: FinancialProfile, target_date: date) -> ForecastResult:
    if target_date < profile.as_of_date:
        raise ValueError("target_date cannot be before as_of_date")

    income = expected_income(profile, target_date)
    expenses = committed_expenses(profile, target_date)
    goal_reserve = mandatory_goal_reserve(profile, target_date)
    projected_balance = profile.current_cash + income - expenses
    safe = (
        projected_balance
        - profile.protected_cash
        - profile.safety_buffer
        - goal_reserve
    )

    return ForecastResult(
        target_date=target_date,
        expected_income=income,
        committed_expenses=expenses,
        mandatory_goal_reserve=goal_reserve,
        projected_balance=projected_balance,
        protected_cash=profile.protected_cash,
        safety_buffer=profile.safety_buffer,
        safe_to_spend=safe,
    )


def assess_purchase(
    profile: FinancialProfile,
    amount: float,
    purchase_date: date,
    search_until: Optional[date] = None,
) -> PurchaseAssessment:
    if amount < 0:
        raise ValueError("purchase amount cannot be negative")

    result = forecast(profile, purchase_date)
    remaining = result.safe_to_spend - amount
    status = "SAFE" if remaining >= 0 else "WAIT"
    shortfall = max(0.0, -remaining)

    recommended_date = None
    if status == "WAIT" and search_until is not None:
        recommended_date = earliest_safe_purchase_date(
            profile, amount, purchase_date, search_until
        )

    return PurchaseAssessment(
        status=status,
        purchase_amount=amount,
        purchase_date=purchase_date,
        safe_to_spend_before_purchase=result.safe_to_spend,
        remaining_after_purchase=remaining,
        shortfall=shortfall,
        recommended_date=recommended_date,
    )


def earliest_safe_purchase_date(
    profile: FinancialProfile,
    amount: float,
    start_date: date,
    end_date: date,
) -> Optional[date]:
    if end_date < start_date:
        raise ValueError("end_date cannot be before start_date")

    current = start_date
    while current <= end_date:
        if forecast(profile, current).safe_to_spend >= amount:
            return current
        current += timedelta(days=1)
    return None


if __name__ == "__main__":
    # Reference scenario from financial_model.md
    profile = FinancialProfile(
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

    target = date(2026, 11, 30)
    result = forecast(profile, target)
    assert round(result.projected_balance, 2) == 8500.00
    assert round(result.safe_to_spend, 2) == 1250.00

    purchase = assess_purchase(profile, 450, target)
    assert purchase.status == "SAFE"
    assert round(purchase.remaining_after_purchase, 2) == 800.00

    print("Reference scenario passed")
