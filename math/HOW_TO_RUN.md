# How to try the financial engine

## Source of truth: Swift

From now on, the real engine is:

`math/FinancialEngine.swift`

The Python files are only an older reference prototype. Do not build new features in Python.

## Where it runs

The final app is an iPhone app, so the Swift/SwiftUI project is run in **Xcode on a Mac**.

If you are on Windows, you can still edit/review the files in GitHub, but you do not need to install Python and you do not need to set up Swift locally just for the hackathon. Simon can add `FinancialEngine.swift` to the Xcode project and run the app/tests on the Mac.

## Tests

The Swift tests are in:

`math/FinancialEngineTests.swift`

They check the main financial rules, including:

- the reference $8,000 / $7,000 protected scenario
- irregular income confidence
- one-time income not being counted twice
- protected goals not being double-counted
- unsafe purchases returning WAIT

## Inputs

For now, the model receives these Swift values from the app/data layer:

- current cash
- protected cash
- safety buffer
- dated income events
- dated expense events
- goals
- purchase amount/date

The app UI and Nessie connection will eventually create these values and pass them into `FinancialEngine`.

## Current reference scenario

- Current cash: $8,000
- Protected cash: $7,000
- Safety buffer: $250
- Expected future income: $1,000
- Essential future expenses: $500

Result at the target date:

- Projected balance: $8,500
- Safe to spend: $1,250

The rules can be changed later without rebuilding the UI because the calculations are isolated inside the engine.
