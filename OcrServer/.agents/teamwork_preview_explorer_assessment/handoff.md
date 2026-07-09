# Handoff Report: OCR Server codebase and Requirements Investigation

This handoff report summarizes the read-only investigation of the OCR Server codebase (`e:\OCR Iphone\OcrServer`) and checks requirements R1-R4, build configuration, and verification scripts.

---

## 1. Observations

We observed the following exact file locations, configurations, and logic blocks:

### 1.1 Swift OCR & Processing Files
- **`e:\OCR Iphone\OcrServer\TextRecognizerPlus.swift`**:
  - Probes orientation at lines 37-39:
    ```swift
    for orientation in [CGImagePropertyOrientation.up, .right, .down, .left] {
        let rotated = rotate(cg, orientation: orientation)
    ```
  - Performs word-level OCR coordinates mapping at lines 136-150.
  - Crops and enhances thermal prints per segment at lines 183-185 (`enhanceForThermalPrint`).
- **`e:\OCR Iphone\OcrServer\ReceiptPipelinePatch.swift`**:
  - Implements recursive XY-cut segmenter at lines 59-90 (`xycut`).
  - Merges fragments vertically at lines 106-128 (`mergeFragments`).
  - Performs semantic splits based on receipt headers at lines 131-152 (`splitByHeaderAnchors`).
  - Validates CUI checksum at lines 158-174 (`isValid`).
  - Calls ANAF v9 API in batch mode at lines 246-274 (`verifyBatch`).
  - Evaluates date-aware Romanian VAT rates at lines 294-315 (`validRates` & `warningForRate`).
  - Math-reconciles totals/VAT at lines 347-370 (`reconcile`).
- **`e:\OCR Iphone\OcrServer\VaporServer.swift`**:
  - Handles `/upload` API POST requests at lines 291-521.
  - Normalizes extracted CUIs by stripping leading zeros at line 450:
    ```swift
    let cleanCui = String(Int(cui) ?? 0)
    ```
  - Compares the official ANAF name against the OCR header at lines 458-466:
    ```swift
    let score = ANAF.nameMatchScore(anafName: officialName, ocrHeader: ocrText)
    ...
    if score >= 0.35 {
        accountingDataArray[i].cuiRequiresVerification = false
    } else {
        accountingDataArray[i].cuiRequiresVerification = true
        accountingDataArray[i].fiscalWarnings.append("⚠️ Nume necorelat...")
    }
    ```
  - Forces 0% VAT, base = total, and clears breakdowns for receipts at lines 1224-1230:
    ```swift
    if forced == "Chitanță de mână" || forced == "Chitanță POS" {
        result.vatAmount = 0
        result.vatPercentages = "-"
        result.baseAmount = result.totalAmount
        result.vatRequiresVerification = false
        result.vatBreakdowns = nil
    }
    ```
  - Categorizes standard expense accounts (Class 6) using `AccountSuggestion.suggest(fullText:)` at lines 1129-1134, but **lacks any payment account suggestion logic (5311/5125)**.

### 1.2 Web Exporter File
- **`e:\OCR Iphone\WebClient\app.js`**:
  - Exports receipts under `"Sumă Plătită"` and leaves base/VAT empty in Excel at lines 296-307 and 322-339:
    ```javascript
    const isChitanta = d.documentType === 'Chitanță de mână' || d.documentType === 'Chitanță POS';
    const totalHeader = isChitanta ? 'Sumă Plătită' : mapping.total;
    // ... maps to Sumă Plătită and clears base/vat/vatPercentages if isChitanta is true
    ```

### 1.3 Xcode build settings
- **`e:\OCR Iphone\OcrServer.xcodeproj\project.pbxproj`**:
  - Target SDK: `iphoneos`
  - Deployment target: iOS `18.4` (lines 208, 269)
  - Swift version: `5.0` (line 309, 342)
  - Vapor framework package dependency: `https://github.com/vapor/vapor.git` up to next major version `4.115.1` (lines 371-378).

### 1.4 Mock/Test scripts
- Located in `e:\OCR Iphone`:
  - `test_logic.py`: Mocks classification, CUI checking, and XY-cut.
  - `test_spatial_ocr.py`: Mock spatial engine simulator.
  - `test_adversarial_challenger.py`: Rigorous test suite validating math corrections and edge cases.
  - `test_regex.swift`: Script to test regular expressions in Swift.
  - `poc_pipeline.py`: Python PoC running segmenter + extraction on test images.

---

## 2. Logic Chain

1. **R1 (Orientare și Extracție 2D)**:
   - Physical orientation correction is handled by fast-probing all four rotations and physically rotating the image using `CIImage.oriented()`.
   - Multi-receipt spatial 2D segmenting is handled via recursive XY-cut, vertical fragment merging, and header-based semantic splits.
2. **R2 (Completeness & Alignment)**:
   - Field extraction agents identify CUI (hardened with OCR digit repairs and buyer context checks), Series, Number, Date, and financial amounts (Base, VAT, Total).
   - Dynamic VAT rates conform to date-aware Romanian tax regulations.
   - Mathematical validation reconciles base + VAT = total and corrects minor OCR errors.
3. **R3 (Selective Receipt Processing)**:
   - Forcing 0% VAT and setting Base = Total are correctly handled in the Swift pipeline.
   - Writing the total amount under "Sumă Plătită" in the Excel sheet is implemented in the WebClient's JS exporter.
   - **Gap Identified**: The code does **not** suggest the payment account `5311` (for handwritten cash receipts) or `5125` (for card/POS receipts). Instead, it classifies receipts under standard class 6 expense accounts.
4. **R4 (Double Validation)**:
   - Extracted CUIs are normalized (by stripping leading zeros) before matching keys in the ANAF query results.
   - Company name fuzzy matching checks the tokenized intersection of the ANAF official name and the OCR header.
   - Mismatches (score < 0.35) are successfully flagged with a warning.

---

## 3. Caveats

- We did not compile or run the Vapor server on a physical iOS device as this is a read-only investigation.
- Verification commands run on the local Python interpreter were not executed because the permission prompt timed out. We assume the Python test suites are valid and functional.

---

## 4. Conclusion

The OCR Server successfully implements the physical image rotation, multi-receipt spatial 2D extraction engine (R1), field extraction/alignment/mathematical correction (R2), Excel column mapping for receipts (R3), and CUI normalization + company name fuzzy validation (R4).

**Crucial Gap**: The codebase **fails** to suggest the payment accounts `5311` (for handwritten/cash receipts) and `5125` (for card/POS receipts) as required by R3. Instead, it suggests general expense accounts (like 6022, 623, 628).

---

## 5. Verification Method

To verify the logic and findings:
1. Inspect the account suggestion logic in `AccountingValidationAgent` (`VaporServer.swift` lines 1129-1134) to confirm it does not branch on receipt document types to suggest `5311` / `5125`.
2. Inspect `e:\OCR Iphone\WebClient\app.js` (lines 296-307) to verify the Excel export headers mapping for `"Sumă Plătită"`.
3. Build and run the Vapor server:
   ```bash
   xcodebuild -project OcrServer.xcodeproj -scheme OcrServer -sdk iphoneos -configuration Debug
   ```
4. Run Python unit tests:
   ```bash
   python test_adversarial_challenger.py
   ```
