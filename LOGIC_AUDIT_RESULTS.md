# Logic Audit Results

Generated: 2026-03-27T18:53:02.315212
Runtime: 22s

## Sweep Scope

- Incomes: ₹1L to ₹60L in ₹1L increments
- Age groups: all 4 app-supported groups
- Employment types: both
- City mode: metro and non-metro
- Rent/HRA scenarios: 5
- 80C values: 3
- Home loan scenarios: 5
- NPS values: 3
- Insurance scenarios: 5
- Education loan scenarios: 4
- Donation scenarios: 3

Total profiles audited: 12960000

## Core Results

- Invariant failures: 0
- Monotonicity failures: 0
- Profiles with zero tax in both regimes: 1792400
- Profiles with non-zero and different tax in both regimes: 10364580
- Old regime better: 706690
- New regime better: 10457490
- Equal tax in both regimes: 1795820

## Notable Findings

- No fatal engine invariant failures were detected if `invariant failures` is `0`.
- No tax monotonicity regressions across rising income were detected if `monotonicity failures` is `0`.
- The regime engine remains approximation-driven for HRA/basic salary, 80GG ATI, donations, and professional tax.
- The app does not currently collect rupee inputs for health insurance premium or bank interest, so these cannot be modeled as exact deductions in tax payable.

## Samples

- Sensitivity: hasNPS flag does not affect tax logic when contribution is unchanged.
- Sensitivity: health-insurance yes/no does not affect tax payable because premium amounts are not collected.
- Sensitivity: app has no distinct 80+ slab input; "Above 60" always uses the 60-79 slab.
