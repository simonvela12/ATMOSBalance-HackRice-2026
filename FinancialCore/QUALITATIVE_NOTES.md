# Deterministic qualitative notes (no AI required)

The app can support a free-text "context" or "miscellaneous notes" tab without embedding an LLM.

The design is deliberately constrained: the user writes a short note about a selected income, expense, goal, or general financial rule. `QualitativeNoteInterpreter` recognizes a compact catalog of financially meaningful phrases and converts them into structured directives. The UI should then show the interpretation back to the user for confirmation before applying it.

This is not open-ended natural-language understanding. If the parser does not recognize the note, it must not guess. The UI can instead offer chips or a follow-up question.

## Examples

Income:

- "I don't expect to receive this frequently." -> irregular income
- "This is a one-time payment." -> one-time income
- "I get this every two weeks." -> recurring income + biweekly cadence
- "There's about a 60% chance I receive this." -> irregular-income confidence = 0.60

Expense:

- "I have to pay this every month." -> committed recurring monthly expense
- "This is optional and I can cancel it." -> not committed
- "They owe me for this and will pay me next Friday." -> expected reimbursement on next Friday
- "This isn't essential, but I already committed to it." -> non-essential but committed

Goal:

- "I can't postpone this." -> mandatory
- "This goal can wait." -> flexible

General:

- "I need to keep at least $500 untouched." -> personal reserve of $500
- "I want a $1,000 reserve starting October 1." -> dated reserve step

Spanish equivalents are supported for the core MVP phrases as well.

## API

```swift
let result = QualitativeNoteInterpreter.parse(
    note,
    context: QualitativeNoteContext(
        subject: .expense,
        referenceAmount: transaction.amount,
        referenceDate: transaction.date,
        label: transaction.merchant
    ),
    asOfDate: Date()
)
```

The result exposes:

- `directives`: structured changes the app can apply;
- `missingFields`: data the parser knows it still needs, such as reimbursement date or recurrence cadence;
- `matchedRules`: deterministic rule names useful for debugging;
- `recognizedSomething`: whether any supported concept was recognized;
- `isActionable`: whether at least one directive was produced and no required field is missing.

The UI should never silently apply an unrecognized sentence.

## Structured directives

Current directives include:

- income type: recurring / irregular / one-time;
- irregular-income confidence;
- expense committed vs optional;
- expense essential vs non-essential;
- expected reimbursement date;
- weekly / biweekly / monthly recurrence;
- mandatory vs flexible goal;
- personal reserve amount and effective date.

## Materialization

`QualitativeDirectiveMaterializer` turns some directives into the dated events the math engine already understands.

For example, when the user selects an $85 expense and writes:

> They owe me for this and will pay me next Friday.

The parser produces an `expectReimbursement` directive. The materializer can create a future `.oneTime` `IncomeEvent` for $85 on that date. The original expense remains visible, so the temporary liquidity dip is preserved.

Recurring income and expenses can also be expanded through the planning horizon using the selected transaction as the amount/date anchor and `FinancialScheduleBuilder` underneath.

## Recommended UI flow

```text
Selected transaction / goal / general context
                  ↓
            user types note
                  ↓
      QualitativeNoteInterpreter
                  ↓
      structured interpretation
                  ↓
   "We understood this as..." card
                  ↓
        user confirms / edits
                  ↓
 normalization + materialization
                  ↓
          FinancialProfile
                  ↓
            FinancialCore
```

This gives the app a conversational feel without claiming that a model understands arbitrary language and without making affordability depend on AI output.

## Why confirmation matters

A phrase parser is intentionally narrower than an LLM. That is a feature for this MVP: every supported phrase maps to a known financial rule, and ambiguity is visible instead of hidden.

For a hackathon demo, a confirmation card can say things like:

- "We'll treat this income as irregular."
- "We'll expect this $85 reimbursement next Friday."
- "We'll include this expense every month."
- "We'll protect a $500 reserve starting today."

If a required detail is missing, ask one deterministic follow-up instead of guessing, e.g. "When do you expect to be paid back?"
