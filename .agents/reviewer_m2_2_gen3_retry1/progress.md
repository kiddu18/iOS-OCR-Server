# Progress

- [x] Run Python tests to see the baseline status (tried, but command execution timed out for permission).
- [x] Inspect VaporServer.swift changes.
- [x] Verify the 4 key issues:
  1. Spatial buyer/client CUI checks: VERIFIED (implemented via `isBuyerCUIBoxLocal` / `isBuyerCUIBox`).
  2. Phone number exclusions: VERIFIED for CUI extraction, but a gap was found in CUI anchor detection where phone numbers are not excluded.
  3. Dynamic VAT rate corrections: VERIFIED (recalculates both the single result attributes and the array/vatBreakdowns split items dynamically).
  4. Robust rotation-invariant line grouping: VERIFIED (uses deskewed boxes in clustering, but `FinancialAmountsAgent` uses distance-based matching instead of line-based).
- [x] Review Swift syntax correctness: VERIFIED (syntactically correct, including trailing comma support).
- [x] Write findings and recommendations to handoff.md.

Last visited: 2026-07-08T08:02:40+03:00
