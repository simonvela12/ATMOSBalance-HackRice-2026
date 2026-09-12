import json
from datetime import date

from prototype import (
    ExpenseEvent,
    FinancialProfile,
    Goal,
    GoalPriority,
    IncomeEvent,
    IncomeType,
    assess_purchase,
    forecast,
)


def parse_date(value: str) -> date:
    return date.fromisoformat(value)


def load_profile(config: dict) -> FinancialProfile:
    incomes = [
        IncomeEvent(
            amount=item["amount"],
            event_date=parse_date(item["date"]),
            source=item["source"],
            income_type=IncomeType(item["type"]),
            confidence=item.get("confidence", 1.0),
        )
        for item in config.get("income_events", [])
    ]

    expenses = [
        ExpenseEvent(
            amount=item["amount"],
            event_date=parse_date(item["date"]),
            category=item["category"],
            essential=item.get("essential", True),
            committed=item.get("committed", True),
        )
        for item in config.get("expense_events", [])
    ]

    goals = [
        Goal(
            name=item["name"],
            target_amount=item["target_amount"],
            current_funded_amount=item.get("current_funded_amount", 0),
            deadline=parse_date(item["deadline"]),
            priority=GoalPriority(item["priority"]),
            already_protected=item.get("already_protected", False),
        )
        for item in config.get("goals", [])
    ]

    return FinancialProfile(
        current_cash=config["current_cash"],
        protected_cash=config["protected_cash"],
        safety_buffer=config["safety_buffer"],
        as_of_date=parse_date(config["as_of_date"]),
        income_events=incomes,
        expense_events=expenses,
        goals=goals,
    )


def money(value: float) -> str:
    sign = "-" if value < 0 else ""
    return f"{sign}${abs(value):,.2f}"


def main():
    with open("demo_config.json", "r", encoding="utf-8") as file:
        config = json.load(file)

    profile = load_profile(config)
    target_date = parse_date(config["target_date"])
    result = forecast(profile, target_date)

    print("\n==============================")
    print(" FINANCIAL ENGINE DEMO")
    print("==============================")
    print(f"As of: {profile.as_of_date}")
    print(f"Target date: {target_date}\n")

    print("INPUT SUMMARY")
    print(f"Current cash:          {money(profile.current_cash)}")
    print(f"Protected cash:        {money(profile.protected_cash)}")
    print(f"Safety buffer:         {money(profile.safety_buffer)}")

    print("\nFORECAST")
    print(f"Expected income:       {money(result.expected_income)}")
    print(f"Committed expenses:   -{money(result.committed_expenses)}")
    print(f"Mandatory goals:      -{money(result.mandatory_goal_reserve)}")
    print(f"Projected balance:     {money(result.projected_balance)}")
    print(f"SAFE TO SPEND:         {money(result.safe_to_spend)}")

    purchase = config.get("purchase_to_test")
    if purchase:
        assessment = assess_purchase(
            profile=profile,
            amount=purchase["amount"],
            purchase_date=parse_date(purchase["date"]),
            search_until=parse_date(purchase["search_until"])
            if purchase.get("search_until")
            else None,
        )

        print("\nPURCHASE TEST")
        print(f"Item:                  {purchase.get('name', 'Planned purchase')}")
        print(f"Amount:                {money(purchase['amount'])}")
        print(f"Purchase date:         {purchase['date']}")
        print(f"Decision:              {assessment.status}")
        print(f"Safe before purchase:  {money(assessment.safe_to_spend_before_purchase)}")
        print(f"Remaining after:       {money(assessment.remaining_after_purchase)}")

        if assessment.status == "WAIT":
            print(f"Shortfall:             {money(assessment.shortfall)}")
            if assessment.recommended_date:
                print(f"Earliest safe date:    {assessment.recommended_date}")
            else:
                print("Earliest safe date:    None found in search window")

    print("\n==============================\n")


if __name__ == "__main__":
    main()
