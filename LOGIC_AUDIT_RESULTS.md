# Logic Audit Results

Generated: 2026-07-31T19:35:13.548503
Rule set: FY2025-26 Filing / AY 2026-27
Runtime: 40s

## Sweep Scope

- Incomes: ₹1L to ₹60L in ₹1L increments
- Age groups: all 5 app-supported groups
- Employment types: both
- City mode: metro and non-metro
- Rent/HRA scenarios: 5
- 80C values: 3
- Home loan scenarios: 5
- NPS values: 3
- Insurance scenarios: 5
- Education loan scenarios: 4
- Donation scenarios: 3

Total profiles audited: 16200000

## Core Results

- Invariant failures: 0
- Monotonicity failures: 0
- Profiles with zero tax in both regimes: 2170900
- Profiles with non-zero and different tax in both regimes: 12956710
- Old regime better: 986760
- New regime better: 13039050
- Equal tax in both regimes: 2174190

## Notable Findings

- No fatal engine invariant failures were detected if `invariant failures` is `0`.
- No tax monotonicity regressions across rising income were detected if `monotonicity failures` is `0`.
- The regime engine remains approximation-driven for HRA/basic salary, 80GG ATI, donations, and professional tax.
- Health insurance premium and bank interest are exact when users add optional accuracy inputs; otherwise they stay as visible assumptions/readiness guidance.

## Samples

- Sensitivity: hasNPS flag does not affect tax logic when contribution is unchanged.
- Sensitivity: health-insurance yes/no does not affect tax payable until an exact premium amount is added.
