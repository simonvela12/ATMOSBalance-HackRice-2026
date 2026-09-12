# Hackathon2026
# Qualitative Transaction Tagging System

## Purpose

The goal of this system is to give financial transactions more meaning than just amount, merchant, and category.

The app should understand not only **what the user spent**, but also:

* whether the expense was necessary or optional
* how flexible the expense is
* whether it was planned
* whether it happens repeatedly
* whether it should be reduced before other expenses
* whether it affects an important financial goal

These qualitative tags will later be used by the financial engine to make recommendations.

---

# 1. Spending Categories

Every expense should have one main category.

Possible categories:

* Housing
* Food
* Transportation
* Education
* Entertainment
* Shopping
* Travel
* Health
* Subscriptions
* Utilities
* Social
* Personal Care
* Fees
* Other

Examples:

| Transaction  | Category       |
| ------------ | -------------- |
| Chipotle     | Food           |
| Uber         | Transportation |
| F1 ticket    | Entertainment  |
| Netflix      | Subscriptions  |
| Miami hotel  | Travel         |
| H-E-B        | Food           |
| Rice tuition | Education      |

The category describes **what the money was spent on**.

It does not determine whether the expense was good or bad.

---

# 2. Need Level

Every transaction should also have a `needLevel`.

Possible values:

### Essential

The user realistically cannot remove this expense without affecting basic needs or important obligations.

Examples:

* rent
* tuition
* required medication
* groceries
* necessary transportation
* utilities

### Important

The expense is not strictly essential, but removing it could significantly affect the user's normal life or commitments.

Examples:

* phone bill
* gym membership used regularly
* school supplies
* transportation that has alternatives
* professional expenses

### Optional

The user can remove or delay the expense without serious consequences.

Examples:

* restaurants
* parties
* concert tickets
* premium subscriptions
* clothes that are not needed
* entertainment
* upgrades

Example:

```text
Chipotle
Amount: $18
Category: Food
Need Level: Optional
```

while:

```text
H-E-B groceries
Amount: $65
Category: Food
Need Level: Essential
```

This distinction is important because category alone is not enough.

---

# 3. Flexibility

Every expense should have a `flexibility` tag.

Possible values:

### Fixed

The amount or payment is difficult to change.

Examples:

* rent
* tuition installment
* insurance
* fixed subscription

### Semi-Flexible

The expense is necessary or normal, but its amount can be reduced.

Examples:

* groceries
* transportation
* utilities
* phone plan

### Flexible

The expense can easily be reduced, delayed, or removed.

Examples:

* eating out
* nightlife
* concerts
* shopping
* entertainment

This tag helps determine **where the app should recommend saving money first**.

Example recommendation logic:

```text
Reduce Flexible expenses first.
Then Semi-Flexible expenses.
Avoid recommending cuts to Fixed expenses unless necessary.
```

---

# 4. Planning Status

Every expense should have a `planningStatus`.

Possible values:

### Planned

The expense was known before it happened.

Examples:

* Miami trip
* F1 ticket
* tuition payment
* planned dinner

### Unplanned

The expense happened without being included in the user's plan.

Examples:

* spontaneous Uber
* unexpected restaurant
* impulse purchase

### Emergency

The expense was unexpected but necessary.

Examples:

* urgent medical cost
* car repair
* emergency travel

This distinction prevents the app from treating all unexpected spending as irresponsible.

For example:

```text
$300 emergency repair
```

should not be treated the same way as:

```text
$300 impulse shopping purchase
```

---

# 5. Frequency

Every expense should have a `frequency`.

Possible values:

* Recurring
* Occasional
* One-Time

### Recurring

Expected to repeat.

Examples:

* rent
* subscriptions
* phone bill
* gym

### Occasional

Happens repeatedly but not on a fixed schedule.

Examples:

* restaurants
* Uber
* nightlife
* groceries

### One-Time

Not expected to happen again.

Examples:

* F1 ticket
* laptop purchase
* flight ticket
* one specific event

---

# 6. Goal Relationship

Expenses can optionally be linked to a financial goal or plan.

Possible values:

```text
goalId = Miami
goalId = F1
goalId = None
```

Example:

```text
American Airlines
$280
Category: Travel
Need Level: Optional
Planning Status: Planned
Goal: Miami
```

This prevents the system from treating planned goal spending as random overspending.

For example:

If the user saved specifically for Miami, spending $280 on the Miami flight should reduce the remaining Miami budget rather than appear as general bad spending.

---

# 7. User Priority

For planned expenses, the user can assign a priority.

Possible values:

### High

The user strongly wants to protect this plan.

Example:

```text
Miami trip
Priority: High
```

### Medium

The user wants it, but it can be sacrificed if necessary.

Example:

```text
F1 ticket
Priority: Medium
```

### Low

The expense should be one of the first things delayed if money becomes tight.

Example:

```text
New headphones
Priority: Low
```

The financial engine should not automatically decide what matters more to the user.

The user supplies this context.

---

# 8. Recommended Spending Object

Eventually, an expense could look conceptually like this:

```text
Transaction

Merchant: Chipotle
Amount: $18
Date: September 14

Category: Food

Need Level:
Optional

Flexibility:
Flexible

Planning Status:
Unplanned

Frequency:
Occasional

Goal:
None
```

Another example:

```text
Transaction

Merchant: Formula 1
Amount: $450

Category:
Entertainment

Need Level:
Optional

Flexibility:
Flexible

Planning Status:
Planned

Frequency:
One-Time

Goal:
F1

Priority:
Medium
```

Another:

```text
Transaction

Merchant:
Apartment Rent

Amount:
$900

Category:
Housing

Need Level:
Essential

Flexibility:
Fixed

Planning Status:
Planned

Frequency:
Recurring
```

---

# 9. Income Qualitative Tags

Income also needs qualitative information.

Every income event should contain:

* source
* type
* confidence
* expected recurrence

---

## Income Type

Possible values:

### Recurring

Income expected on a relatively predictable basis.

Examples:

* regular campus job
* fixed monthly allowance
* recurring employment

### Irregular

Income that happens multiple times but cannot be guaranteed.

Examples:

* tutoring
* freelance work
* paid sessions
* side jobs

### One-Time

Income that should not be used to predict future income.

Examples:

* family transfers related to a special event
* selling an item
* account closure transfer
* one-time bonus
* refund

---

# 10. Income Confidence

Future income should have a confidence level.

For the first version of the model:

### Confirmed

```text
confidence = 1.0
```

The income is effectively guaranteed.

Example:

```text
Already scheduled campus paycheck
```

### Likely

Suggested initial value:

```text
confidence = 0.7
```

Example:

```text
Tutoring work that usually happens
```

### Possible

Suggested initial value:

```text
confidence = 0.3
```

Example:

```text
Possible freelance work that has not been booked
```

The exact numbers can later be modified by the financial model.

---

# 11. Example Income Events

Example 1:

```text
Source:
Campus job

Amount:
$300

Type:
Recurring

Confidence:
Confirmed
```

Expected contribution:

```text
$300
```

---

Example 2:

```text
Source:
Tutoring

Amount:
$300

Type:
Irregular

Confidence:
Likely
```

If the math engine uses:

```text
Likely = 70%
```

then:

```text
Expected income contribution = $210
```

---

Example 3:

```text
Source:
Family transfer

Amount:
$2,000

Type:
One-Time
```

If the money already arrived:

```text
It contributes to current cash.
```

But:

```text
It should NOT be projected as future income.
```

This rule is especially important because otherwise unusual income could severely distort the forecast.

---

# 12. Automatic vs User-Confirmed Tags

The app can automatically suggest tags based on merchant and transaction history.

Example:

```text
Merchant:
Uber

Suggested category:
Transportation

Suggested frequency:
Occasional
```

However, users should be able to correct the interpretation.

Example:

The system sees:

```text
+$1,500 transfer
```

Instead of assuming what it means, the application could ask:

```text
How should we treat this income?

Recurring
Irregular
One-Time
```

This combines:

```text
Automatic classification
+
User context
```

The user should always be able to override the system.

---

# 13. How the Financial Engine Can Use These Tags

The qualitative layer should not directly decide whether a user can afford something.

Instead, it provides context to the mathematical engine.

Example:

```text
Flexible + Optional + Unplanned
```

means:

```text
Good candidate for spending reduction.
```

While:

```text
Fixed + Essential + Recurring
```

means:

```text
Protect this expense in the forecast.
```

An initial recommendation hierarchy could be:

```text
1. Reduce Optional + Flexible expenses
2. Reduce Optional + Semi-Flexible expenses
3. Delay Low-Priority planned purchases
4. Reduce Important + Flexible expenses
5. Avoid touching Essential + Fixed expenses
```

This hierarchy should later be combined with the user's goals and financial situation.

---

# 14. Calendar Interpretation

The same qualitative information can help determine calendar colors.

A day should NOT simply become red because the user spent a lot of money.

Example:

```text
$900 rent
```

should not automatically produce a red day.

Instead, the app should consider whether spending caused the user to move away from their financial plan.

Possible future system:

### Green

Spending is consistent with the user's plan and goals.

### Yellow

Spending reduced the user's safety margin or exceeded expected flexible spending.

### Red

Spending materially endangered a protected goal, safety buffer, or future obligation.

This should eventually be calculated by the financial engine rather than using raw spending amount alone.

---

# 15. Core Principle

The qualitative system exists to answer:

> What does this transaction mean for this specific user?

Rather than only:

> How much did the user spend?

The same $100 can represent very different financial behavior:

```text
$100 medication
Essential / Fixed
```

versus:

```text
$100 nightclub
Optional / Flexible
```

versus:

```text
$100 Miami hotel deposit
Optional / Planned / High-Priority Goal
```

The app should understand these differences before making recommendations.
