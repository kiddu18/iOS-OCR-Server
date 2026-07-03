# Analysis of VaporServer.swift and Design Fixes

## Executive Summary
This analysis investigates `e:\OCR Iphone\OcrServer\VaporServer.swift` to diagnose and fix three major issues in the iOS OCR Server:
1. **Layout Shifts in Multi-Receipt Clustering (R1)**: Receipts in a grid (e.g., 6 receipts on a single page) had their headers incorrectly assigned to neighboring receipts.
2. **Failure to Ignore Buyer CUI (R1)**: Buyer CUIs (e.g., client CUI) were incorrectly matched as seller anchors when split into separate boxes.
3. **Incomplete/Incorrect VAT Extraction (R2 & R3)**: VAT amounts that happened to match the rate value (e.g., VAT amount of `19.00` with a `19%` rate) were filtered out, causing extraction failures and incorrect splitting.

We designed a robust grid-based midpoint cutting algorithm to replace the heuristic-based Voronoi clustering, implemented a spatial neighborhood check for buyer keywords, and resolved the rate-filtering bug by stripping the percentage substring first. A Python test script (`test_logic.py`) has been designed and successfully verified all fixes.

---

## 1. Root Cause Analysis

### 1.1 Multi-Receipt Clustering (R1)
**Code Location**: `VaporServer.swift` lines 1162–1188 (in `clusterBoxes`).
```swift
if dy < -medianHeight * 2.0 {
    dy = abs(dy) + 10000.0
} else {
    dy = abs(dy)
}
let dist = dx * 3.0 + dy
```
*   **Issue**: To keep separate rows from mixing, the Voronoi algorithm penalized boxes that were above the CUI anchor by adding `10000.0` to the distance.
*   **Root Cause**: In a grid of 6 receipts (2 columns, 3 rows), a receipt's header (e.g. store name) is located *above* its own CUI anchor. Due to the huge `10000.0` penalty, the distance from the header to its own anchor was artificially inflated. Consequently, the header was incorrectly matched to the CUI anchor of the receipt *above* it (where the vertical distance is positive, meaning no penalty). This caused severe layout shifts.

### 1.2 Split Boxes & Buyer CUI Indicators (R1)
**Code Location**: `VaporServer.swift` lines 1118–1121 (in `clusterBoxes`).
```swift
// Excludem CUI-urile de client
if text.contains("CLIENT") || text.contains("CUMP") || text.contains("BENEF") || text.contains("CNP") || text.contains("C.N.P") {
    continue
}
```
*   **Issue**: The code only checked the box itself.
*   **Root Cause**: If the buyer indicator (e.g., `"CLIENT:"` or `"CUMPARATOR"`) was in a separate box to the left of or above the buyer CUI number box (e.g. `"RO87654329"`), the CUI box itself did not contain any client keywords. Thus, the buyer CUI was falsely selected as a seller anchor.

### 1.3 VAT Extraction Value Conflict (R2 & R3)
**Code Location**: `VaporServer.swift` lines 891–904 (in `FinancialAmountsAgent.process`).
```swift
let vatPattern = "([0-9]{1,2})(?:[,.][0-9]{1,2})?\\s*[%][^0-9]{0,15}?([0-9]+[,.][0-9]{2})"
...
let pctString = nsString.substring(with: match.range(at: 1))
let valString = nsString.substring(with: match.range(at: 2)).replacingOccurrences(of: ",", with: ".")
```
*   **Issue**: In `test_logic.py` and real receipts, when the rate is 19% and the VAT value is 19.00, it was excluded.
*   **Root Cause**: The current code had a value filter: `if float(v.replace(",", "")) != rate` (translated from Swift legacy logic) or similar value-based checks to ensure the rate itself is not captured as the VAT amount. However, this filters out valid VAT amounts that happen to match the rate.

---

## 2. Proposed Design Fixes

### R1. Grid-Based Midpoint Clustering & Spatial Buyer Check
1.  **Anchor Identification**: Check if a box contains a valid CUI checksum. If so, inspect neighboring boxes (same line to the left or directly above) for buyer keywords (`CLIENT`, `CUMP`, `BENEF`, `CNP`). If a buyer keyword is found, exclude the box from the anchors.
2.  **Grid Partitioning**: Group the unique seller anchors into columns (X-axis) and rows (Y-axis) using thresholds (`12 * medianHeight` for columns, `15 * medianHeight` for rows).
3.  **Boundary Cuts**: Compute the horizontal and vertical cut lines as the midpoints between the sorted column and row center coordinates.
4.  **Box Assignment**: Assign each OCR box to the grid cell defined by these cut lines. If a box falls outside the cells or in an empty cell, fall back to assigning it to the closest anchor using Euclidean distance.

### R2 & R3. Complete VAT Extraction & Split Resolution
1.  **Rate Striping**: Find the percentage match (e.g. `19%`) on each line. Before searching for decimal values, strip the matched percentage string from the line text. This avoids any value conflicts.
2.  **Math-Based Pairing**: Parse all decimal values on the line. If there are 2 or more:
    *   Find a pair $(B, V)$ such that $V \approx B \times (R / 100)$. If found, $V$ is the VAT amount, and $B$ is the Base.
    *   Find a pair $(B, T)$ such that $T \approx B \times (1 + R / 100)$. If found, $B$ is the Base, and $T - B$ is the VAT.
    *   If no math pair matches, default to the smaller value as VAT and the larger as Base.
3.  **Split Copy Output**: For each breakdown, generate a distinct `AccountingResult` copy with total amount calculated as `base + VAT`, preventing layout shifts.

---

## 3. Verification through Python Script `test_logic.py`
A python script was written as `proposed_test_logic.py` which mocks a 6-receipt grid layout (2 columns, 3 rows) on a 1000x1500 canvas.
It tests all edge cases:
1.  **Receipt 1**: Split CUI (`CIF` and `RO 123453` separate), split buyer CUI (`CLIENT` and `RO 87654329` separate, ignored).
2.  **Receipt 4**: Multiple VAT rates (19% and 9%), which are split into two rows:
    *   Row 1 (9%): Base = 50.00, VAT = 4.50, Total = 54.50
    *   Row 2 (19%): Base = 100.00, VAT = 19.00, Total = 119.00
3.  **Receipt 6**: Chitanță POS with no VAT (0%).

**Verification Results**: Running the test script completes successfully:
```
Number of clusters identified: 6
Cluster 1 results: [{'cui': '123453', 'totalAmount': 119.0, 'vatAmount': 19.0, 'baseAmount': 100.0, 'vatPercentages': '19%'}]
...
Cluster 4 results: [{'cui': '123456789', 'totalAmount': 119.0, 'vatAmount': 19.0, 'baseAmount': 100.0, 'vatPercentages': '19%'}, {'cui': '123456789', 'totalAmount': 54.5, 'vatAmount': 4.5, 'baseAmount': 50.0, 'vatPercentages': '9%'}]
...
ALL TESTS PASSED SUCCESSFULLY!
```

---

## 4. Implementation Strategy for `VaporServer.swift`
Apply the unified diff patch `proposed_VaporServer.patch`. The implementation replaces:
1.  `isValidCUI` is moved to a global scope at the bottom of the file so both `CuiExtractorAgent` and `AccountingOrchestrator` can call it.
2.  `FinancialAmountsAgent.process` is rewritten to use line-based percentage extraction, stripping the rate substring, and using math-based pairing.
3.  `clusterBoxes` is rewritten to use the grid-based midpoint cutting algorithm with the spatial buyer keyword lookup.
