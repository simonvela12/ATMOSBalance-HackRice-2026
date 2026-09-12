# iPhone device smoke test

This is the next integration checkpoint after the standalone Swift Package tests pass.

## Goal

Prove that the installed iOS app can import `FinancialCore`, execute the engine on a physical iPhone, and display deterministic outputs.

## Quick path in Xcode

1. Pull the latest `lucas-math` branch.
2. Ensure `FinancialCore` is added as a local package dependency to the iOS app target.
3. Add `FinancialCore/Examples/iOS/FinancialCoreDeviceSmokeTestView.swift` to the iOS app target.
4. Temporarily navigate to `FinancialCoreDeviceSmokeTestView()` from an existing screen.
5. Select Simon's connected iPhone as the run destination.
6. Build and run the app on the phone.
7. Open the smoke-test screen and tap **Run FinancialCore**.

Expected sample output includes approximately:

- projected cash: `$8500`
- target headroom: `$1250`
- safe to spend now: `$750`
- current health: `SAFE`
- horizon health: `SAFE`
- `$450` What-If: `SAFE`

The exact presentation can differ; the important checkpoint is that the call runs inside the installed app and produces values without crashing.

## After the dummy-data test passes

Replace the sample `FinancialProfile` with the data already produced by the app's qualitative pipeline.

Map qualitative output into FinancialCore concepts:

- marked recurring / irregular / one-time income -> `IncomeEvent`
- committed or essential future expenses -> `ExpenseEvent`
- priority / must-happen objectives -> `Goal(priority: .mandatory)`
- nice-to-have objectives -> `Goal(priority: .flexible)`
- user-confirmed runway / protected needs -> `PersonalReserveStep`
- bank/account balance restrictions -> `InstitutionalMinimum`
- recent normal discretionary spending -> `WeeklySpendingSample`
- reimbursements -> expense now + future one-time income

Do not let qualitative/AI logic directly set SAFE/TIGHT/NOT_SAFE. It should normalize context; `FinancialCore` makes the deterministic decision.

## What to verify on the real phone

- the app launches with `import FinancialCore`
- the smoke-test view runs without crash
- values match the standalone package result
- changing a dummy purchase amount changes the What-If result predictably
- changing a goal/reserve changes safe-to-spend predictably
- after connecting real qualitative data, marked categories/priorities actually alter the financial outputs

Once these pass, the next step is replacing the temporary smoke-test screen with the real home / What-If / goal UI.
