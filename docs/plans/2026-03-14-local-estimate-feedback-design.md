# Local Estimate Feedback Loop

## Goal

Improve estimate accuracy for every user without introducing a backend service.

## Design

1. Every fund snapshot now carries a `valuationDate`.
   This separates the date being estimated from the reference NAV date used as the return baseline.

2. When an official fund NAV arrives for the same `valuationDate`,
   the app writes a local `FundEstimateObservation` record:
   - estimated NAV
   - official NAV
   - baseline NAV
   - return error

3. Before saving a new local estimate,
   the app reads recent observation records for that fund and derives a rolling bias.
   The bias correction is:
   - fully local
   - weighted toward recent errors
   - damped when the sample size is small or the error sign is inconsistent

## Why local-only works

- The computation is tiny.
- The app only tracks a handful of assets.
- Accuracy gains come from per-fund feedback, not centralized training.
- This avoids server cost, privacy concerns, and operational risk.

## Limits

- Corrections are user-device specific unless CloudKit syncs them.
- Bias correction cannot fix same-day regime changes it has never seen.
- The model still depends on public data quality and disclosure lag.

## Next Step

Build a local backtest/report screen so users can see:
- recent prediction errors
- rolling bias
- which funds are currently less reliable
