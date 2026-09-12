# Running Finanzas2026

## Requirements

Xcode 16 or newer, an iPhone or simulator on iOS 17+, and a Capital One
[Nessie](http://api.nessieisreal.com) sandbox API key and customer ID.

## Build

1. Open `Finanzas2026/Finanzas2026.xcodeproj`.
2. Select the **Finanzas2026** scheme.
3. Under **Signing & Capabilities**, choose your own team. The repository ships
   with an empty team on purpose so everyone signs with their own account —
   do not commit yours.
4. Run.

`FinanceCore` (banking + Nessie) and `FinancialCore` (the deterministic engine)
are referenced as local Swift packages from within this repository. There is
nothing to install.

## Connecting data

The app shows no financial figures until an account is linked. Tap the bank
button, enter your Nessie API key and customer ID, and connect. Credentials stay
on the device for the session and are never written to the repository.

Synced accounts and transactions are cached in Application Support, so the app
reopens with data already present.

## Where the numbers come from

Nothing is seeded with example data.

- Past days come from linked-bank transactions.
- Future days and the projected cash path come from `FinancialCore`.
- Goals and scheduled entries come from what the user adds in the app, and are
  persisted to `Application Support/Finanzas2026/user-plan.json`.

An account with no goals and no entries has none — the forecast reflects that
rather than inventing a plan.

## Gemini (optional)

The What-If screen can explain the engine's verdict in plain language. Tap
**Add Gemini key** and paste a key from Google AI Studio.

The key is entered at runtime and stored in `UserDefaults` on the device. It is
deliberately not committed: a key compiled into the binary can be extracted from
it, and a shared key means a shared quota. Each developer uses their own.

The model is only ever given a decision `FinancialCore` has already made, and is
instructed not to re-judge it or introduce numbers. If Gemini is unreachable the
screen still shows the engine's own figures.

Default model is `gemini-3.5-flash`, overridable via the `gemini.model` default.
