# OCR Spatial Extraction Analysis Report

This report analyzes the spatial OCR extraction logic in `VaporServer.swift`, reviews the recent changes, and defines simulated OCR JSON test scenarios to verify happy paths, edge cases, and compliance logic.

---

## 1. Spatial Extraction Logic Analysis

The server performs accounting data extraction by passing OCR bounding boxes through a pipeline of specialized agents. Two of these agents rely heavily on spatial reasoning: `CuiExtractorAgent` and `FinancialAmountsAgent`.

### A. Line Grouping (Vertical & Horizontal Ordering)
Before individual agents run, the `AccountingOrchestrator` groups raw OCR boxes into vertical lines (`textBlocks`) to support legacy regex searches:
1. **Vertical Sorting**: All bounding boxes are sorted by their vertical coordinate `y` (`boxes.sorted { $0.y < $1.y }`).
2. **Median Height Calculation**: The orchestrator calculates the median box height (`medianHeight`) to establish a standard font/line size scale.
3. **Line Grouping**: A vertical tolerance is set as `yTolerance = medianHeight * 0.4`. Starting from the top, boxes are added to the same line if their `y` coordinate is within `yTolerance` of the first box of that line.
4. **Horizontal Sorting**: Each line's boxes are sorted horizontally by `x` (`line.sorted { $0.x < $1.x }`).
5. **Text Block Generation**: The sorted texts are joined with a space.

### B. Key-Value Spatial Matching
For the spatial agents, association between a keyword (key) and its corresponding value is determined by spatial proximity on the 2D plane:

#### 1. CuiExtractorAgent (CUI/CIF Extraction)
- **Keywords**: `["CIF", "CUI", "CODFISCAL", "RO"]` (matched using case-insensitive check and fuzzy matching with tolerance = 1).
- **Same-Box Extraction**: First, it checks if the candidate keyword box itself contains a valid CUI (e.g. `"CIF RO8609468"`). If so, it extracts and validates the number immediately.
- **Nearby Box Scan**: If the keyword box doesn't contain the value, it searches for neighboring boxes within:
  - **Vertical bounds**: `y` coordinate in `[keywordBox.y - keywordBox.h * 0.8, keywordBox.y + keywordBox.h * 2.0]`. This allows the CUI to be on the same line or up to two line-heights below the keyword.
  - **Horizontal bounds**: `x` coordinate greater than or equal to `keywordBox.x - keywordBox.w * 0.5` (representing the region to the right of the keyword).
  - **Ordering**: Neighboring candidate boxes are sorted horizontally by `x` (`$0.x < $1.x`).
  - **Validation**: The first box in this sorted order containing a valid Romanian CUI (validated using the control key checksum) is selected.

#### 2. FinancialAmountsAgent (Total & VAT Extraction)
- **Keywords**: `["TOTAL", "SUMA", "ACHITAT"]` (for totals) or `"TVA"` (for VAT).
- **Vertical bounds**: `abs(candidateBox.y - keywordBox.y) < yTol`, where `yTol = max(box.h * 0.6, 15.0)`. This strictly targets the same line but allows for minor tilt or baseline shifts.
- **Horizontal bounds**: `x > keywordBox.x - keywordBox.w * 0.5` (strictly to the right).
- **Ordering**: Line boxes are sorted horizontally from left to right (`$0.x < $1.x`).
- **Validation**:
  - **Total**: The line must NOT contain the word `"TVA"`. The first value matching the currency amount pattern `([0-9]+[.][0-9]{2})` (after replacing commas with dots) is chosen.
  - **VAT**: The combined text of the line is matched against `([0-9]{1,2})(?:[,.][0-9]{1,2})?\\s*[%][^0-9]{0,15}?([0-9]+[,.][0-9]{2})`, extracting both the percentage rate and the amount.

---

## 2. Analysis of Recent Changes

### A. Dynamic Vertical Tolerance (`yTol`)
- **Code**: `let yTol = max(box.h * 0.6, 15.0)`
- **Behavior**: Instead of using a fixed pixel threshold (which fails on high-resolution images or large-format receipts), the vertical search window scales with the line height of the keyword box itself. 
  - For small text (e.g. `box.h = 10`), it falls back to the safety minimum of `15.0`.
  - For large header/total text (e.g. `box.h = 45`), the tolerance expands to `27.0`, ensuring that misaligned total amounts in large print are still correctly grouped with their label.

### B. TVA Line Filtering
- **Code**:
  ```swift
  let lineTextForCheck = lineBoxes.map { $0.text.uppercased() }.joined(separator: " ")
  if lineTextForCheck.contains("TVA") {
      continue // Ignoram liniile "TOTAL TVA"
  }
  ```
- **Behavior**: On Romanian receipts, it is common to see lines like `"TOTAL TVA 19% 1.90"` or `"TOTAL TVA A 9.50"`. Under basic spatial matching, the keyword `"TOTAL"` would match, and the amount `1.90` or `9.50` would be extracted as the global receipt total, which is incorrect.
- By joining the text of all candidate boxes to the right of the `"TOTAL"` keyword and checking for `"TVA"`, the agent skips these lines entirely, moving on to match the true global `"TOTAL"` line (e.g., `"TOTAL 11.90"`).

---

## 3. Simulated OCR JSON Test Scenarios

Below are structured JSON test cases matching the `OCRResult` format (specifically the `boxes` array containing `OCRBoxItem` structures).

### Test Case 1: Happy Path (Standard Receipt)
- **Goal**: Verify successful spatial extraction of a standard receipt containing vendor CUI, TVA line, and a global Total line.
- **OCR Input JSON**:
```json
{
  "text": "S.C. MEGA IMAGE S.R.L.\nCIF: RO 8609468\nTVA 19% 19.00\nTOTAL 119.00",
  "image_width": 1000,
  "image_height": 2000,
  "boxes": [
    { "text": "S.C.", "x": 100, "y": 100, "w": 80, "h": 25 },
    { "text": "MEGA", "x": 190, "y": 100, "w": 90, "h": 25 },
    { "text": "IMAGE", "x": 290, "y": 100, "w": 100, "h": 25 },
    { "text": "CIF:", "x": 100, "y": 150, "w": 80, "h": 25 },
    { "text": "RO", "x": 190, "y": 150, "w": 50, "h": 25 },
    { "text": "8609468", "x": 250, "y": 150, "w": 120, "h": 25 },
    { "text": "TVA", "x": 100, "y": 800, "w": 80, "h": 25 },
    { "text": "19%", "x": 190, "y": 800, "w": 60, "h": 25 },
    { "text": "19.00", "x": 800, "y": 800, "w": 100, "h": 25 },
    { "text": "TOTAL", "x": 100, "y": 900, "w": 120, "h": 25 },
    { "text": "119.00", "x": 800, "y": 900, "w": 120, "h": 25 }
  ]
}
```
- **Expected Output**:
  - `documentType`: `"Bon Fiscal"` (or based on text blocks classification)
  - `cui`: `"8609468"` (ANAF verified or kept fallback)
  - `totalAmount`: `119.00`
  - `vatAmount`: `19.00`
  - `vatPercentages`: `"19%"`
  - `baseAmount`: `100.00`
  - `cuiRequiresVerification`: `false` (assuming ANAF mock success)

---

### Test Case 2: CUI Override and Verification Logic
- **Goal**: Verify that when `buyer_cui` is provided, compliance checks pass if it is present on the document, and a warning is issued if it is missing.
- **OCR Input JSON**:
```json
{
  "text": "S.C. DANTE INTERNATIONAL S.A.\nCIF: RO 14399840\nCUI CUMPARATOR: RO 8609468\nTOTAL 100.00",
  "image_width": 1000,
  "image_height": 2000,
  "boxes": [
    { "text": "CIF:", "x": 100, "y": 100, "w": 80, "h": 25 },
    { "text": "RO", "x": 190, "y": 100, "w": 50, "h": 25 },
    { "text": "14399840", "x": 250, "y": 100, "w": 120, "h": 25 },
    { "text": "CUI", "x": 100, "y": 900, "w": 60, "h": 25 },
    { "text": "CUMPARATOR:", "x": 170, "y": 900, "w": 160, "h": 25 },
    { "text": "RO", "x": 340, "y": 900, "w": 50, "h": 25 },
    { "text": "8609468", "x": 400, "y": 900, "w": 120, "h": 25 },
    { "text": "TOTAL", "x": 100, "y": 1000, "w": 100, "h": 25 },
    { "text": "100.00", "x": 800, "y": 1000, "w": 100, "h": 25 },
    { "text": "BON FISCAL", "x": 100, "y": 1100, "w": 200, "h": 25 }
  ]
}
```
- **Execution Scenarios**:
  1. **Correct Buyer CUI**: Pass `buyer_cui = "8609468"`.
     - *Expected Output*: `cui = "14399840"` (extracted vendor CUI), `fiscalWarnings` should be empty (since "8609468" is present in `fullText`).
  2. **Missing Buyer CUI**: Pass `buyer_cui = "2816464"`.
     - *Expected Output*: `cui = "14399840"`, `fiscalWarnings` contains `"Atenție: Bonul fiscal nu conține CUI-ul cumpărătorului (2816464). TVA-ul este complet nedeductibil!"`.

---

### Test Case 3: TOTAL TVA Discrimination
- **Goal**: Verify that the parser ignores `"TOTAL TVA"` lines and successfully matches the global `"TOTAL"` line.
- **OCR Input JSON**:
```json
{
  "text": "SUBTOTAL 50.00\nTOTAL TVA A - 19% 9.50\nTOTAL 59.50",
  "image_width": 1000,
  "image_height": 2000,
  "boxes": [
    { "text": "SUBTOTAL", "x": 100, "y": 700, "w": 150, "h": 25 },
    { "text": "50.00", "x": 800, "y": 700, "w": 100, "h": 25 },
    { "text": "TOTAL", "x": 100, "y": 800, "w": 100, "h": 25 },
    { "text": "TVA", "x": 210, "y": 800, "w": 70, "h": 25 },
    { "text": "A", "x": 290, "y": 800, "w": 30, "h": 25 },
    { "text": "-", "x": 330, "y": 800, "w": 20, "h": 25 },
    { "text": "19%", "x": 360, "y": 800, "w": 60, "h": 25 },
    { "text": "9.50", "x": 800, "y": 800, "w": 100, "h": 25 },
    { "text": "TOTAL", "x": 100, "y": 900, "w": 100, "h": 25 },
    { "text": "59.50", "x": 800, "y": 900, "w": 100, "h": 25 }
  ]
}
```
- **Expected Output**:
  - `totalAmount`: `59.50` (The `TOTAL TVA` line at `y = 800` is skipped because it contains `"TVA"` in its same-line boxes. The parser successfully extracts `59.50` from the line at `y = 900`).

---

### Test Case 4: Dynamic yTol Scenarios
- **Goal**: Verify that large fonts with vertical misalignment are correctly grouped under the dynamic `yTol` logic, whereas standard small fonts strictly reject distant values.
- **OCR Input JSON (Large font/title layout)**:
```json
{
  "text": "TOTAL 350.00",
  "image_width": 1000,
  "image_height": 2000,
  "boxes": [
    { "text": "TOTAL", "x": 100, "y": 1000, "w": 200, "h": 50 },
    { "text": "350.00", "x": 800, "y": 1022, "w": 150, "h": 50 }
  ]
}
```
- *Analysis*: The vertical difference between keyword and amount is `1022 - 1000 = 22.0` pixels.
  - `yTol = max(50.0 * 0.6, 15.0) = 30.0`.
  - Since `22.0 < 30.0`, grouping is successful.
- *Expected Output*: `totalAmount = 350.00`.

- **OCR Input JSON (Small font layout, distinct lines)**:
```json
{
  "text": "TOTAL\nCUI: 8609468",
  "image_width": 1000,
  "image_height": 2000,
  "boxes": [
    { "text": "TOTAL", "x": 100, "y": 1000, "w": 80, "h": 12 },
    { "text": "CUI:", "x": 100, "y": 1022, "w": 60, "h": 12 },
    { "text": "8609468", "x": 180, "y": 1022, "w": 100, "h": 12 }
  ]
}
```
- *Analysis*: The vertical difference is `1022 - 1000 = 22.0` pixels.
  - `yTol = max(12.0 * 0.6, 15.0) = 15.0`.
  - Since `22.0 > 15.0`, the CUI label/value is correctly ignored as candidate for the TOTAL line.
- *Expected Output*: `totalAmount = nil` (fails spatial, falls back to regex or largest number, but doesn't wrongly associate CUI number with TOTAL).

---

### Test Case 5: General Edge Cases

#### A. Box Merge Failures (Decimal Amount Split)
- **Goal**: Check behavior when the amount is split into separate decimal and integer boxes.
- **OCR Input JSON**:
```json
{
  "text": "TOTAL 123 .45",
  "image_width": 1000,
  "image_height": 2000,
  "boxes": [
    { "text": "TOTAL", "x": 100, "y": 900, "w": 100, "h": 25 },
    { "text": "123", "x": 780, "y": 900, "w": 50, "h": 25 },
    { "text": ".45", "x": 835, "y": 900, "w": 30, "h": 25 }
  ]
}
```
- *Analysis*: The regex `([0-9]+[.][0-9]{2})` checks each individual box text. Neither `"123"` nor `".45"` matches this regex.
- *Expected Output*: Spatial total extraction fails. It falls back to the legacy regex on the combined line text block `"TOTAL 123 .45"`, which might also fail if spaces are present. This reveals a limitation where OCR box merging is critical before agent processing.

#### B. Currency/Formatting Variations (Commas vs Dots)
- **Goal**: Verify that Romanian comma decimals (e.g. `123,45`) are sanitized and parsed correctly.
- **OCR Input JSON**:
```json
{
  "text": "TOTAL 123,45 LEI",
  "image_width": 1000,
  "image_height": 2000,
  "boxes": [
    { "text": "TOTAL", "x": 100, "y": 900, "w": 100, "h": 25 },
    { "text": "123,45", "x": 800, "y": 900, "w": 100, "h": 25 },
    { "text": "LEI", "x": 910, "y": 900, "w": 50, "h": 25 }
  ]
}
```
- *Expected Output*: `totalAmount = 123.45` (successfully replaces `","` with `"."` and parses).

#### C. ANAF API Timeout / Failure
- **Goal**: Verify that when the ANAF API times out or returns a non-200 status, the CUI is still kept but marked as needing manual verification.
- **Mock ANAF Response (Simulated HTTP 500 or network timeout)**:
  - *Expected Output*: `cui = "14399840"`, but `cuiRequiresVerification = true`, `companyName = nil`, `companyAddress = nil`. The extracted data is not discarded.
