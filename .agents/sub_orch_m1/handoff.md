# Handoff Report - Milestone 1: Codebase Analysis and Test Design

## 1. Observation
A detailed inspection of `e:\OCR Iphone\OcrServer\VaporServer.swift` reveals the following key components and lines:
- **Line Grouping & Ordering**: Before spatial agents run, `AccountingOrchestrator` groups OCR bounding boxes into horizontal lines (`textBlocks`). It calculates the median height of all boxes (`medianHeight`) and uses a vertical grouping tolerance of `yTolerance = medianHeight * 0.4`. Boxes within this tolerance are grouped, then sorted horizontally from left to right (`x` coordinate).
- **CUI Spatial Matching (`CuiExtractorAgent`, line 628)**:
  - Searches for keywords like `["CIF", "CUI", "CODFISCAL", "RO"]` using case-insensitive comparison and fuzzy match (max distance = 1).
  - First tests if the keyword box itself contains a valid CUI.
  - If not, scans nearby boxes within:
    - Vertical range: `[keywordBox.y - keywordBox.h * 0.8, keywordBox.y + keywordBox.h * 2.0]`.
    - Horizontal range: `x >= keywordBox.x - keywordBox.w * 0.5`.
  - It validates the first match using Romania's control key checksum algorithm (`isValidCUI`, line 700).
- **Total/VAT Spatial Matching (`FinancialAmountsAgent`, line 780)**:
  - Searches for `["TOTAL", "SUMA", "ACHITAT"]` or `"TVA"`.
  - Targets same-line candidate boxes using dynamic vertical tolerance: `yTol = max(box.h * 0.6, 15.0)`.
  - Filters candidates to the right (`x > keywordBox.x - keywordBox.w * 0.5`).
  - **TVA Exclusion**: If candidate line boxes for the `"TOTAL"` keyword contain `"TVA"`, the line is skipped to prevent extracting VAT sub-totals.
  - Sanitizes and parses the amount, replacing commas with dots.
- **ANAF/BNR Resiliency**:
  - If the lookup to BNR or ANAF API fails or times out, the parser catches the error, preserves the extracted CUI, and sets `cuiRequiresVerification = true` so the user is prompted to check it manually instead of discarding the result.

---

## 2. Logic Chain
- **Spatial Proximity**: Instead of purely vertical page structures, the server associates values with labels using bounding box boundaries. The dynamic tolerance `yTol = max(box.h * 0.6, 15.0)` scales vertical alignment windows based on font size (higher tolerance for larger headings, minimum fallback for standard text).
- **Discriminator logic**: Receipt formats often place `"TOTAL TVA"` above or below the global `"TOTAL"`. Joining the same-line candidate boxes horizontally and performing a substring check for `"TVA"` cleanly filters out these subtotal lines.
- **Robustness**: Extracted data integrity is preserved via control checksum validation, while system reliability is maintained by gracefully handling external API timeouts.

---

## 3. Simulated OCR JSON Test Scenarios

### Scenario 1: Happy Path (Standard Receipt)
- **Goal**: Verify spatial extraction of standard CUI, VAT, and Total.
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
- **Expected Parsed Result**:
  - `cui`: `"8609468"`
  - `totalAmount`: `119.00`
  - `vatAmount`: `19.00`
  - `vatPercentages`: `"19%"`
  - `baseAmount`: `100.00`
  - `cuiRequiresVerification`: `false` (assuming ANAF mock success)

### Scenario 2: CUI Override and Compliance Logic
- **Goal**: Verify that when `buyer_cui` is provided, compliance checks verify it is on the receipt, issuing a warning if absent.
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
  - **Match Case**: If request passes `buyer_cui = "8609468"`, expected output: `cui = "14399840"`, no fiscal warnings.
  - **Mismatch Case**: If request passes `buyer_cui = "2816464"`, expected output: `cui = "14399840"`, and `fiscalWarnings` contains `"Atenție: Bonul fiscal nu conține CUI-ul cumpărătorului (2816464). TVA-ul este complet nedeductibil!"`.

### Scenario 3: TOTAL TVA Discrimination
- **Goal**: Verify that the parser skips `"TOTAL TVA"` lines and successfully matches the global `"TOTAL"`.
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
  - `totalAmount`: `59.50` (The `TOTAL TVA` line at `y = 800` is skipped; the global `TOTAL` at `y = 900` is matched).

### Scenario 4: Dynamic yTol Alignment Scenarios
- **Goal**: Verify that large headings with vertical misalignment are grouped successfully under dynamic `yTol`, whereas small, distinct lines are not misgrouped.
- **Sub-case A: Large Title (Success)**:
  - OCR Boxes:
    - `"TOTAL"` keyword: `y = 1000, h = 50`.
    - `"350.00"` value: `y = 1022, h = 50`.
  - Spacing is `22.0` pixels. Dynamic `yTol = max(50 * 0.6, 15.0) = 30.0`. Since `22.0 < 30.0`, they group.
  - Expected `totalAmount`: `350.00`.
- **Sub-case B: Small Distinct Lines (Ignore)**:
  - OCR Boxes:
    - `"TOTAL"` keyword: `y = 1000, h = 12`.
    - `"8609468"` value: `y = 1022, h = 12`.
  - Spacing is `22.0` pixels. Dynamic `yTol = max(12 * 0.6, 15.0) = 15.0`. Since `22.0 > 15.0`, they are correctly kept separate.
  - Expected `totalAmount`: `nil`.

### Scenario 5: General Edge Cases (Merge Failures, Formatting, Timeouts)
- **Sub-case A: Split Decimal Box**:
  - OCR Boxes: `"TOTAL"` (x=100, y=900), `"123"` (x=780, y=900), `".45"` (x=835, y=900).
  - Spatial amount extraction regex `([0-9]+[.][0-9]{2})` fails on individual boxes. Legacy line text regex fallback may also fail if spacing is not sanitized.
- **Sub-case B: Comma Formatting**:
  - OCR Boxes: `"TOTAL"`, `"123,45"`, `"LEI"` on the same line.
  - Expected `totalAmount`: `123.45` (commas replaced with dots before parsing).
- **Sub-case C: ANAF Timeout**:
  - Extract CUI `"14399840"` but trigger mock network failure / timeout.
  - Expected: `cuiRequiresVerification = true`, extracted values preserved.

---

## 4. Caveats
- No unit test harness is currently implemented in Swift in this workspace. Simulated test JSONs must be fed into the server's endpoint `/ocr` or verified via integration testing.
- CUI scanner picks up the first valid checksum. On receipts where both buyer and vendor CUI exist, vertical ordering of OCR boxes dictates the outcome unless `buyerCui` parameters match correctly.

---

## 5. Verification Method
- Inspect and verify the code structure in `e:\OCR Iphone\OcrServer\VaporServer.swift`.
- Run mock API queries with the simulated JSON bodies above using `curl` or a custom test script to check the parsed endpoint output.
