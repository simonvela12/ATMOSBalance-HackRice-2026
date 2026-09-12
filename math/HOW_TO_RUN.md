# How to try the financial engine

You do **not** need to edit `prototype.py` to test the model.

## The only file you normally edit

Open:

`math/demo_config.json`

That file contains the demo inputs: current cash, protected cash, safety buffer, future income, expenses, goals, and the purchase you want to test.

## Run it

Open a terminal in the `math` folder and run:

```bash
python3 run_demo.py
```

The program prints the forecast, safe-to-spend amount, and the purchase decision.

## Main input fields

- `current_cash`: money available in accounts today
- `protected_cash`: money that must not be spent
- `safety_buffer`: extra minimum cash buffer
- `target_date`: date for the main forecast
- `income_events`: future income events
- `expense_events`: future committed expenses
- `goals`: mandatory or flexible goals
- `purchase_to_test`: optional purchase to evaluate

### Income types

Use exactly one of:

- `recurring`
- `irregular`
- `oneTime`

For `irregular`, `confidence` is between `0.0` and `1.0`. Example: an expected $500 irregular payment at 60% confidence contributes $300 to the deterministic forecast.

## Important

Dates use `YYYY-MM-DD`, for example `2026-11-30`.

Do not change `prototype.py` just to try different financial scenarios. Change `demo_config.json`, save it, and run `python3 run_demo.py` again.
