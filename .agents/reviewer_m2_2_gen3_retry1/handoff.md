# Handoff Report - Reviewer 2

This report reviews the changes made in `OcrServer/VaporServer.swift` and compares them with the Python tests (`test_logic.py`, `test_spatial_ocr.py`, `scratch/mock_test.py`).

---

## 1. Observation

- **File Path**: `e:\OCR Iphone\OcrServer\VaporServer.swift`
- **File Path**: `e:\OCR Iphone\test_logic.py`
- **File Path**: `e:\OCR Iphone\test_spatial_ocr.py`
- **File Path**: `e:\OCR Iphone\scratch/mock_test.py`

### Key observations in `VaporServer.swift`:
1. **Spatial Buyer CUI Checks**: Implemented inside `CuiExtractorAgent.process` via a local function `isBuyerCUIBoxLocal` (lines 769–807) and inside the main class via `isBuyerCUIBox` (lines 1620–1656).
2. **Phone Number Exclusions**: Implemented inside `CuiExtractorAgent.process` via `isPhoneOrPhoneLabelLocal` (lines 809–842) and within `isValidCUI` (lines 2040–2045) to ignore 10-digit numbers starting with "07", "02", or "03".
3. **Dynamic VAT Rate Corrections**: Implemented inside `AccountingValidationAgent.correctVatRates` (lines 1313–1419), which updates the percentages, base, and VAT amounts inside the result structures.
4. **Line Grouping & Rotation**: Grouping is performed in `FinancialAmountsAgent.process` (lines 961–978) and `processOcrResult` (lines 1558–1581). Rotation correction (deskewing) is performed in `clusterBoxes` (lines 1715–1752).

### Key observations of discrepancies:
1. **Phone number checks in CUI Anchor Detection**: `clusterBoxes` uses a local function `isCuiAnchor` (lines 1777–1799) to identify CUI anchors. It does NOT check or exclude phone numbers or phone labels, unlike `test_logic.py`'s `is_seller_cui_box` (line 78) and `scratch/mock_test.py`'s `is_seller_anchor_box` (line 226).
2. **Line-based extraction in `FinancialAmountsAgent`**: Swift `FinancialAmountsAgent.process` (lines 987–990) uses a purely 2D Euclidean distance check (`dist < medianHeight * 2.0`) to find nearby text for keyword validation, whereas Python `test_spatial_ocr.py` (lines 480–485) and `scratch/mock_test.py` (lines 408–419) use line-based horizontal proximity.
3. **VAT Breakdown algorithms**: Swift uses a global mathematical pairing approach (`rates` vs `allVals` combinatorics) inside `FinancialAmountsAgent.process` (lines 1106–1145), whereas the Python tests use line-by-line percentage and value extraction.

---

## 2. Logic Chain

1. **Buyer CUI Exclusion**: The implementation of `isBuyerCUIBoxLocal` correctly checks 2D spatial relationships (same line left-label, or directly above label). This ensures buyer CUIs are ignored as seller candidates during CUI extraction.
2. **Phone Exclusion during Clustering**: If a phone number is formatted such that it passes the CUI check (e.g., starts with a country code "+40" resulting in 10 digits that do not start with "07", "02", "03", and happens to satisfy the CUI checksum), and it is located near a phone label, the Swift `isCuiAnchor` will consider it a valid CUI anchor because it doesn't call `isPhoneOrPhoneLabelLocal`. The Python tests explicitly check and exclude this. Therefore, the clustering in Swift may produce incorrect sub-clusters on real-world inputs containing phone numbers.
3. **Robustness of Total Check**: In Swift `FinancialAmountsAgent.process`, if a line-item `"TOTAL"` box is processed before the final `"TOTAL"` box (due to arbitrary box list ordering), the nearest decimal candidate (within 2D distance) is matched. If it's a smaller number, it will be extracted as the total amount, and the loop will break. The line-based check in Python avoids this by checking the line content for "TVA" keywords and filtering accordingly.

---

## 3. Caveats

- We were unable to execute the Python test suite directly via `run_command` due to the user permission prompt timing out.
- The Swift code is analyzed statically; runtime Vapor server behavior (e.g. Vision framework interaction) was not verified in an active process.

---

## 4. Conclusion

The Swift implementation in `VaporServer.swift` contains the requested fixes, but they are **not fully synchronized** with the Python simulation tests (`test_logic.py`, `test_spatial_ocr.py`, `scratch/mock_test.py`). There are minor gaps in CUI anchor filtering (lack of phone label check) and line-based total matching in the Swift code.

---

## 5. Verification Method

- Run the Python simulation tests directly to verify their baseline passes:
  `python test_logic.py`
  `python test_spatial_ocr.py`
  `python scratch/mock_test.py`
- Inspect `OcrServer/VaporServer.swift` lines 1777–1799 (`isCuiAnchor`) and check if phone number/label exclusions are added.

---

# Quality Review Report

**Verdict**: REQUEST_CHANGES

## Findings

### [Major] Finding 1: Lack of Phone Number/Label Exclusion in CUI Anchor Detection

- **What**: CUI Anchor detection inside `clusterBoxes` does not exclude boxes containing phone numbers or phone labels.
- **Where**: `OcrServer/VaporServer.swift` lines 1777–1799 (`isCuiAnchor`).
- **Why**: A phone number box that mathematically passes the CUI checksum (e.g. from "+40" country prefix and a random checksum match) will be treated as a CUI anchor. This will cause `clusterBoxes` to incorrectly split single receipts or group them wrong.
- **Suggestion**: Add a call to a phone number/label check inside `isCuiAnchor` to mirror the Python test `is_seller_anchor_box` check:
  ```swift
  if isPhoneOrPhoneLabelLocal(box) { return false } // Needs adapter for local call in clusterBoxes
  ```

### [Major] Finding 2: Distance-based Proximity instead of Line-based in `FinancialAmountsAgent`

- **What**: Proximity search around `"TOTAL"` and `"TVA"` keywords in `FinancialAmountsAgent.process` uses Euclidean distance (`dist < medianHeight * 2.0`) instead of horizontal line alignment.
- **Where**: `OcrServer/VaporServer.swift` lines 987–990.
- **Why**: If a table is wide or contains columns, the `"TVA"` or `"TOTAL"` label might be further than `2.0 * medianHeight` from the value. Furthermore, a value on a different line could be physically closer than a value on the same line, resulting in wrong amounts.
- **Suggestion**: Implement horizontal line-based search matching the Python test implementation.

---

# Adversarial Challenge Report

**Overall risk assessment**: MEDIUM

## Challenges

### [Medium] Challenge 1: Wide Receipts / Table Layouts
- **Assumption challenged**: That the total/VAT amount is always the physically closest decimal box to the label.
- **Attack scenario**: A receipt with a wide table layout where "TOTAL" is on the left and the amount is on the far right (distance > 2 * medianHeight), but a line item value is directly above the "TOTAL" label (distance < 2 * medianHeight).
- **Blast radius**: The line item value will be extracted as the total amount, causing a validation failure.
- **Mitigation**: Use the structured lines (`lines`) generated on lines 962–977 to search for values on the same line.

## Stress Test Results

- `Scenario 3 (TVA Discrimination)` -> Expected: totalAmount = 59.50 -> Actual/Predicted: totalAmount = 50.00 -> **FAIL** (in Swift static trace due to distance-based match on `50.00` first).
