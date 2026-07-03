# Quality and Adversarial Review Report

## Review Summary

**Verdict**: REQUEST_CHANGES

This review evaluates the modifications made to `OcrServer/VaporServer.swift` and the corresponding mock test suite in `scratch/mock_test.py` for Milestone 2. 

Overall, the architectural design of the grid-based clustering algorithm, the fallback logic for OCR CUI typos, and the split VAT row amount reconstruction is solid and well-integrated. However, a major correctness bug has been identified in both the implementation and the mock test script that prevents the fallback CUI extraction from working as expected, causing the mock test to fail upon execution.

---

## Findings

### [Major] Finding 1: Missing "R0" Prefix in Fallback CUI Cleaner
- **What**: The prefixes list in the CUI fallback candidate cleaning logic does not contain `"R0"` (R-zero), despite the mock test simulating OCR inaccuracies using this exact prefix.
- **Where**: 
  - `OcrServer/VaporServer.swift` (line 803)
  - `scratch/mock_test.py` (line 95)
- **Why**: 
  In Romania, the seller CUI is often prefixed with `"RO"`. A common OCR error is misrecognizing `"RO"` as `"R0"` (R-zero). 
  To test this, the mock test injects OCR typos into Receipt 1 (`"R0 12345P"`) and Receipt 5 (`"CIF R0987654A"`). 
  In the cleaning logic:
  ```swift
  let prefixes = ["CIF", "CUI", "RO", "COD", "FISCAL", "CODFISCAL"]
  ```
  Since `"R0"` is not in the prefixes list, the cleaner fails to strip the `"R0"` prefix from `"R012345P"` and `"R0987654A"`, returning them as-is. However, the mock test assertions in `mock_test.py` expect `"12345P"` and `"987654A"`. Because they do not match, the mock test will fail with an assertion error.
- **Suggestion**: 
  Add `"R0"` to the `prefixes` array in both Swift and Python:
  ```swift
  let prefixes = ["CIF", "CUI", "RO", "R0", "COD", "FISCAL", "CODFISCAL"]
  ```

### [Minor] Finding 2: Lack of Filtering and Sorting in Python Mock Grid Clustering
- **What**: The Python implementation of `cluster_boxes` does not filter out empty clusters or sort the final clusters spatially when using the grid clustering path, unlike the Swift version.
- **Where**: `scratch/mock_test.py` (lines 235-376)
- **Why**: 
  In `VaporServer.swift`, after grid or XY-cut clustering, the clusters are filtered (`$0.count >= 3`) and sorted top-to-bottom, left-to-right. In `mock_test.py`, the grid-based clustering returns the groups raw. If OCR boxes are out of order, the Python clusters will be out of order compared to the Swift server output, leading to potential alignment issues.
- **Suggestion**: 
  Apply the same filtering and sorting to the grid clustering path in `mock_test.py` as is done in the recursive XY-cut fallback.

---

## Verified Claims

- **Claim 1**: Spatial clustering groups OCR boxes into 6 receipts in a 2x3 grid.
  - *Method*: Mathematical trace of columns/rows grouping and grid cuts (vCuts at `x = 350` and hCuts at `y = 350, 850`).
  - *Result*: **PASS**. The layout correctly maps the 6 receipts to cells `(0,0)`, `(0,1)`, `(1,0)`, `(1,1)`, `(2,0)`, `(2,1)` without duplicates.
- **Claim 2**: Deduplication of anchors prevents duplicate grid columns/rows.
  - *Method*: Static trace of anchor deduplication with spatial distance threshold (`dx < medianHeight * 5.0 && dy < medianHeight * 3.0`).
  - *Result*: **PASS**. Nearby duplicate anchor detections (such as CUI keyword and number boxes) are filtered correctly.
- **Claim 3**: Multiple VAT rate rows are split and totals are reconstructed.
  - *Method*: Static trace of `processOcrResult` (Swift) and `extract_financials` (Python) splitting `vatBreakdowns`.
  - *Result*: **PASS**. On Receipt 4, the split produces two rows (119.00 total for 19% rate and 54.50 total for 9% rate) matching the total of 173.50.

---

## Coverage Gaps
- **BNR and ANAF Remote APIs** — risk level: **Low** — recommendation: **Accept Risk**. 
  The project utilizes remote API endpoints (`webservicesp.anaf.ro` and `bnr.ro`). Network failure or timeouts are handled gracefully via local fallback variables (`fallbackRate = 5.0` and `cuiRequiresVerification = true`), which minimizes the risk of server crashes in production.

---

## Unverified Items
- **Local Swift Compilation and Test Run** — reason not verified: 
  The current command-line environment requires explicit Windows user permission prompts, which timed out during execution. Verification was conducted using rigorous static analysis and dry-running logic.

---
---

# Adversarial Challenge Report

## Challenge Summary

**Overall risk assessment**: MEDIUM

The system relies heavily on geometric heuristics (`medianHeight`, spatial thresholds) for document segmentation and table parsing. This approach is highly performant but introduces edge cases under layout distortion.

---

## Challenges

### [Medium] Challenge 1: Degenerate Median Height
- **Assumption challenged**: OCR boxes are assumed to have a non-zero, reasonable height (`medianHeight`) which is used as the scaling factor for all spatial tolerances.
- **Attack scenario**: If the input image is highly skewed or contains empty/corrupt OCR items where height is reported as 0 or 1, the spatial threshold multipliers (`medianHeight * 12.0`, etc.) collapse to 0.
- **Blast radius**: Grid clustering column/row grouping fails, and anchor deduplication fails, causing every box to be classified as a distinct column/row/anchor, leading to out-of-memory or high resource usage.
- **Mitigation**: Enforce a lower bound on `medianHeight` (e.g., `max(computedMedianHeight, 5.0)`).

### [Low] Challenge 2: Merged Grid Cell Overwriting
- **Assumption challenged**: The cell coordinates `\(aRow),\(aCol)` map uniquely to a single anchor.
- **Attack scenario**: If two receipts are printed extremely close to each other, their anchors might fall into the same grid cell.
- **Blast radius**: The dictionary `cellToAnchorIdx` overwrites the first anchor index with the second, causing the first cluster to be empty and discarded, effectively merging two receipts.
- **Mitigation**: Allow `cellToAnchorIdx` to map to a list of anchors, or dynamically adjust the grid cuts if cells overlap.

---

## Stress Test Results

- **Grid Segregation with OCR Typos** → Grid cuts successfully isolate columns and rows → **PASS** (verified via manual coordinate trace).
- **ANAF Endpoint Timeout** → Network error in URLSession → **PASS** (retains CUI, marks `cuiRequiresVerification = true`).
- **No valid CUI on Document** → Text cleaning fallback → **FAIL** (due to missing `"R0"` prefix, it fails to strip the typo prefix and leaves the CUI dirty).

---

## Unchallenged Areas
- **OCR Engine (Vision Framework) Accuracy** — reason not challenged: Out of scope. The server assumes the Apple Vision framework produces coordinate boxes of reasonable accuracy.
