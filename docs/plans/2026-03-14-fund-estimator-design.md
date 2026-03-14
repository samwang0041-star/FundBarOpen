# Fund Estimator Accuracy Upgrade

## Goal

Improve domestic fund intraday estimates without changing the product surface or adding new vendors.

## Changes

1. Fix report-date price parsing.
   The historical kline endpoint returns both open and close. The estimator was using the first price field, which can diverge from the true close and distort holding drift correction.

2. Add a rolling factor calibration layer.
   For each fund, use recent official NAV history to learn how the fund has actually behaved against the current index proxy set:
   - HS300
   - ZZ500
   - ChiNext
   - STAR 50

3. Blend holdings and factor estimates.
   Keep the disclosed-holdings estimate as the base.
   Increase the factor-model weight when:
   - holdings disclosure is older
   - known holdings coverage is weaker
   - the factor fit has enough samples and explanatory power

## Why this is the right next step

- It directly addresses the largest live error source: stale holdings.
- It stays inside current Eastmoney data coverage.
- It is measurable with unit tests and future backtests.
- It avoids premature ML complexity.

## Current Limits

- The factor universe is still coarse.
- Holdings still only cover the disclosed top positions.
- There is no persistent backtest dataset yet.

## Recommended Next Steps

1. Build a backtest harness that stores intraday predictions and compares them with later official NAV.
2. Expand unknown-position proxies from broad style indexes to sector indexes.
3. Persist per-fund calibration diagnostics for tuning and confidence display.
