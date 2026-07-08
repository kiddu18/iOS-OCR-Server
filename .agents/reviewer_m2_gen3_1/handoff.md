# Handoff Report — reviewer_m2_gen3_1

## 1. Observation
- `test_logic.py` and `scratch/mock_test.py` passed successfully.
- `test_spatial_ocr.py` failed with `AssertionError: Expected total to be None, got 8609468.0` in Scenario 4b (Dynamic yTol Alignment).
- In `OcrServer/VaporServer.swift` lines 1295-1310, `getYearFromDate` handles 2-digit years as follows:
  ```swift
  if year <= 24 {
      return 2000 + year
  } else {
      return 1900 + year
  }
  ```
- In `test_logic.py` line 324 and `scratch/mock_test.py` line 429, the fallback regex for `total_pattern` still includes the keyword `"REST"`, whereas it has been removed from `OcrServer/VaporServer.swift` and `test_spatial_ocr.py`.

## 2. Logic Chain
- **Scenario 4b Test Failure**: The input boxes in Scenario 4b are placed at vertical coordinates `y=1000` (for `"TOTAL"`) and `y=1022` (for `"8609468"`). Since the font height is small (`h=12`), the vertical separation (`22`) exceeds the dynamic tolerance (`12 * 0.4 = 4.8`), grouping them into distinct lines. Consequently, line-based extraction does not align them. However, in `FinancialAmountsAgent.process` (line 530 of `test_spatial_ocr.py`), the fallback regex `total_pattern` contains `\s*`, which matches newlines (`\n`). Thus, the regex matches `"TOTAL\n8609468"` and erroneously extracts `8609468.0` as the total.
- **2-Digit Year Bug**: The current year is 2026. A receipt from 2025 or 2026 with a 2-digit year (e.g., `"12.10.25"` or `"08.07.26"`) will be parsed by `getYearFromDate` as `1925` or `1926` because `year` (25/26) is greater than 24. Since `1925 <= 2024` and `1926 <= 2024` are true, `correctVatRates` will return early, completely skipping VAT auto-correction for 2025 and 2026 receipts.
- **"REST" Keyword Discrepancy**: The production server code `OcrServer/VaporServer.swift` removed `"REST"` from the fallback `totalPattern` to avoid false positives (since "rest" means change/cash back in Romanian). However, the test files `test_logic.py` and `scratch/mock_test.py` were not updated to reflect this change.

## 3. Caveats
- I did not test the actual ANAF web service connection since network access is restricted in our environment.
- I assumed standard Romanian codepage settings on Windows console caused the `UnicodeEncodeError` when running `test_spatial_ocr.py` without `PYTHONIOENCODING=utf-8`.

## 4. Conclusion
- The verdict is **REQUEST_CHANGES** due to:
  1. The assertion failure in `test_spatial_ocr.py` (Scenario 4b).
  2. The 2-digit year parsing bug in `VaporServer.swift` that bypasses VAT auto-correction for 2025/2026 receipts.
  3. The legacy `"REST"` keyword discrepancy in the python test files.

## 5. Verification Method
- Execute the test suite with:
  ```powershell
  python test_logic.py
  $env:PYTHONIOENCODING="utf-8"; python test_spatial_ocr.py
  python scratch/mock_test.py
  ```

---

## Review Summary

**Verdict**: REQUEST_CHANGES

## Findings

### [Critical] Finding 1: 2-Digit Year Bug Bypasses VAT Correction
- **What**: 2-digit years representing 2025 or 2026 are parsed as 1925 or 1926.
- **Where**: `OcrServer/VaporServer.swift` lines 1295-1310 (`getYearFromDate` helper).
- **Why**: It uses a hardcoded threshold of `year <= 24` to determine if it should add `2000` or `1900`. For any year >= 25, it maps to `1900 + year`. Thus, years 25 and 26 become 1925 and 1926, which are <= 2024, causing the agent to skip VAT correction.
- **Suggestion**: Increase the threshold (e.g. `year <= 50` or `year <= 35`) so that years 25 and 26 correctly map to 2025 and 2026.

### [Major] Finding 2: Scenario 4b Test Failure
- **What**: Test fails because `totalAmount` is incorrectly extracted from a separate line.
- **Where**: `test_spatial_ocr.py` line 1097 (`assert res4b.totalAmount is None`).
- **Why**: The fallback regex uses `\s*`, matching the newline character `\n` that separates the word "TOTAL" from "8609468" on the next line.
- **Suggestion**: Change `\s*` in the fallback regex to only match horizontal spaces (e.g. `[ \t]*`).

### [Minor] Finding 3: Legacy `"REST"` Keyword Discrepancy
- **What**: The keyword `"REST"` remains in the fallback total regex of `test_logic.py` and `scratch/mock_test.py`.
- **Where**: `test_logic.py:324` and `scratch/mock_test.py:429`.
- **Why**: Oversights in syncing python test scripts with production updates.
- **Suggestion**: Remove `"REST"` from these files.

## Verified Claims

- Rotation-invariant clustering layout logic -> verified via `test_logic.py` -> PASS
- Modulo-11 CUI check and phone numbers exclusion -> verified via `scratch/mock_test.py` -> PASS
- Amounts formatting (thousands separators, integers, decimals) -> verified via Scenario 5 in `test_spatial_ocr.py` -> PASS

## Coverage Gaps
- None.

---

## Challenge Summary

**Overall risk assessment**: MEDIUM

## Challenges

### [High] Challenge 1: 2-Digit Year Bypassing Auto-Correction
- **Assumption challenged**: The date parsing threshold `year <= 24` is safe for modern 2-digit years.
- **Attack scenario**: A receipt dated `15.05.25` or `10.01.26` is parsed. The system thinks it is from `1925` or `1926` and bypasses the auto-correction of old VAT rates to 2026 rates.
- **Blast radius**: Prevents proper auto-correction of VAT rates for current 2025/2026 receipts.
- **Mitigation**: Update the threshold to `year <= 50` or dynamic current year.

## Stress Test Results

- **Input**: Box `TOTAL` followed by a number on a distinct line.
  - **Expected**: Ignored as distinct lines.
  - **Actual**: Matched across line boundaries due to `\s*` matching `\n` -> FAIL (Scenario 4b).
