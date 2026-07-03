# Empirical Verification Results - Spatial OCR Implementation

**Date/Time**: 2026-07-03T10:17:00Z
**Workspace**: `e:\OCR Iphone`
**Agent**: Challenger (Empirical Challenger)
**Roles**: critic, specialist

---

## 1. Command Execution Results & Environmental Constraints

### Attempt 1: Running `python scratch/mock_test.py`
- **Command**: `python scratch/mock_test.py`
- **Result**: **FAILED (Timeout)**
- **Reason**: The automated execution environment requires explicit user approval for `command` actions, which timed out (60 seconds) without receiving input:
  ```
  Encountered error in step execution: Permission prompt for action 'command' on target 'python scratch/mock_test.py' timed out waiting for user response.
  ```

### Attempt 2: Running `python test_spatial_ocr.py`
- **Command**: `python test_spatial_ocr.py`
- **Result**: **FAILED (Timeout)**
- **Reason**: Blocked by the same permission prompt timeout.

### Attempt 3: Compile / Build Swift/Vapor Project
- **Command**: Xcode build (`xcodebuild`)
- **Result**: **NOT FEASIBLE**
- **Reason**: 
  1. The host operating system is **Windows**, which does not support native Xcode project builds (`xcodebuild`).
  2. Command line execution is restricted by the non-interactive permission timeouts.

---

## 2. Dry Run & Logic Trace of `scratch/mock_test.py`

Given the execution blocks, a line-by-line dry run of `scratch/mock_test.py` was performed to verify the correctness of the spatial OCR logic.

### A. Clustering Verification (6 Clusters Found)
- The mock canvas has dimensions `1000 x 1500` containing **6 receipts** arranged in a `2x3` grid:
  - Column 0: $x \in [50, 450]$, Column 1: $x \in [550, 950]$
  - Row 0: $y \in [50, 450]$, Row 1: $y \in [550, 950]$, Row 2: $y \in [1050, 1450]$
- `cluster_boxes(boxes)` calculates `median_height` ($20$ px) and detects **6 unique seller anchors** based on keyword matching (e.g. `CIF`, `CUI`, `CODFISCAL`, `RO`):
  1. "CIF" at $(100, 100)$
  2. "CIF" at $(600, 100)$
  3. "CUI RO 12345674" at $(100, 600)$
  4. "CUI: RO 123456789" at $(600, 600)$
  5. "CIF R0987654A" at $(100, 1100)$
  6. "CUI RO 55553" at $(600, 1100)$
- Using vertical cuts ($x = 350$) and horizontal cuts ($y \in [350, 850]$), the algorithm correctly groups every box into its corresponding receipt quadrant.
- **Verification**: **6 clusters are successfully identified.**

### B. Accounting Rows Verification (7 Accounting Rows Expected)
The 6 clusters correspond to:
- **Receipt 1 (Row 0, Col 0)**: Seller CUI is "12345P" (requires verification), total is 119.00, VAT is 19%.
- **Receipt 2 (Row 0, Col 1)**: Seller CUI is "1234565", total is 200.00, VAT is 19%.
- **Receipt 3 (Row 1, Col 0)**: Seller CUI is "12345674", total is 150.00, VAT is 9%.
- **Receipt 4 (Row 1, Col 1)**: Seller CUI is "123456789". Contains **multiple VAT rates**: 19% (100.00 base, 19.00 VAT) and 9% (50.00 base, 4.50 VAT). This splits into **2 accounting rows** (one for each rate).
- **Receipt 5 (Row 2, Col 0)**: Seller CUI is "987654A" (requires verification), total is 80.00, VAT is 5%.
- **Receipt 6 (Row 2, Col 1)**: Seller CUI is "55553" (POS receipt, 0% VAT), total is 45.00.
- **Verification**: 6 receipts yield exactly **7 accounting rows** due to the dual VAT rate split on Receipt 4.

### C. Critical Finding: CUI Extraction Bug in Python Mock Script
During the manual trace of **Receipt 1** CUI extraction, a logical bug was found in `scratch/mock_test.py`:
1. Receipt 1 contains the buyer CUI box `{"text": "RO 87654329", "x": 180, "y": 200}`.
2. `87654329` is a mathematically valid CUI.
3. In `extract_financials`, CUI candidate filtering only performs basic keyword exclusions:
   ```python
   if "CLIENT" in clean_text or "CUMP" in clean_text or "BENEF" in clean_text or "CNP" in clean_text:
       continue
   ```
   Because `"RO87654329"` does not contain those keywords directly, it is NOT skipped and is added to `candidate_boxes` because it contains `"RO"`.
4. The helper function `is_buyer_cui_box(...)` (which contains the 2D spatial check to detect buyer labels to the left or above) is **never called** in `extract_financials` or `extract_cui_with_fallback`.
5. Consequently, `extract_cui_with_fallback` matches `87654329` as the seller CUI under Step 1 (valid CUI in candidate boxes) and returns `("87654329", False)`.
6. This causes the test's CUI assertion to fail:
   ```python
   r1_rows = [r for r in all_results if r["cui"] == "12345P"]
   assert len(r1_rows) == 1  # Fails! actual cui is "87654329"
   ```

---

## 3. Dry Run & Logic Trace of `test_spatial_ocr.py`

`test_spatial_ocr.py` runs 5 regression scenarios:
- **Scenario 1 (Happy Path)**: Parses CUI, Total, VAT, and Base correctly.
- **Scenario 2 (CUI Override/Compliance)**: Verifies buyer/seller CUI logic. Although `is_buyer_cui_box` is missing here as well, the order of boxes in `s2_boxes` ensures that the correct seller CUI box (`"14399840"`) is processed first in nearby checks before the buyer CUI is evaluated, allowing the assertion to pass.
- **Scenario 3 (TVA Discrimination)**: Verifies that "TOTAL TVA" is not confused with invoice total.
- **Scenario 4 (Dynamic yTol)**: Verifies vertical layout alignment limits.
- **Scenario 5 (Edge Cases)**: Verifies comma formatting and ANAF timeout simulation.

---

## 4. Swift Implementation Audit (`VaporServer.swift`)

Unlike the Python mock scripts, the core Swift implementation in `VaporServer.swift` **does not have this bug**.
- Inside `CuiExtractorAgent.process`, it correctly defines and invokes `isBuyerBox` on line 732:
  ```swift
  if isBuyerBox(box, medianHeight: medianHeight) {
      continue
  }
  ```
- The `isBuyerBox` helper checks both direct text contains, token fuzzy matches, and 2D spatial relationships.
- In Receipt 1's layout, `"RO 87654329"` is located at $x=180, y=200$, while `"CLIENT:"` is at $x=100, y=200$. 
  - $dy = 0 < 1.5 \times 20$
  - $dx = 80 > 0$ and $80 < 12 \times 20$
- Therefore, the Swift server correctly marks `"RO 87654329"` as a buyer box, ignores it from candidate boxes, and proceeds to extract the fallback seller CUI `"12345P"` from `"R0 12345P"`, matching the design specifications perfectly.

---

## 5. Conclusions & Recommendations
- **Correctness of Core Implementation**: The Swift-based server implementation is correct and properly avoids extracting the buyer CUI as the seller CUI.
- **Python Mock Implementation Bug**: The Python mock scripts (`scratch/mock_test.py` and `test_spatial_ocr.py`) contain a logic discrepancy because they do not call the spatial buyer box exclusion logic (`is_buyer_cui_box`) during CUI candidate extraction.
- **Recommendation**: To keep Python test environments fully aligned with production Swift logic, update `extract_financials` in `scratch/mock_test.py` and `CuiExtractorAgent.process` in `test_spatial_ocr.py` to filter candidate boxes using `is_buyer_cui_box` (or equivalent) before attempting CUI extraction.
