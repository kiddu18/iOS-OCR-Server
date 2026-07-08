## 2026-07-08T05:06:05Z
You are an Implementation Worker (Remediation). Your working directory is e:\OCR Iphone\.agents\worker_m2_remediate_gen3_retry1.
Your task is to fix the remaining bugs in the Vapor OCR server and synchronize all Python verification/adversarial tests.

### Background & Context
We received reviews from Reviewer 1, Reviewer 2, and Challenger 1. The previous iteration failed due to:
1. A date-parsing bug where 2-digit years like `25` or `26` map to `1925`/`1926` in `getYearFromDate`, skipping VAT corrections.
2. CUI anchor detection in `clusterBoxes` not excluding phone numbers.
3. Total and VAT extraction in `FinancialAmountsAgent.process` relying on Euclidean distance instead of horizontal line alignment.
4. Python verification tests not implementing `AccountingValidationAgent` and expecting old uncorrected VAT rates (like 5% for Receipt 5).

### Detailed Fixes Required in `OcrServer/VaporServer.swift`
1. **Fix `getYearFromDate`**:
   In `OcrServer/VaporServer.swift`, locate the `getYearFromDate` function. Change the condition `year <= 24` to `year <= 50` so that years `25` (2025) and `26` (2026) are correctly parsed as `2025` and `2026`.
2. **Make spatial helpers file-level and update CUI Anchor checks**:
   - Extract `isBuyerCUIBoxLocal` and `isPhoneOrPhoneLabelLocal` from `CuiExtractorAgent.process` to the file scope (e.g., above `AccountingOrchestrator`) so they can be called by multiple agents/methods.
   - Update their signatures to accept `in boxes: [OCRBoxItem]` and `medianHeight: Double`:
     ```swift
     fileprivate func isBuyerCUIBoxLocal(_ box: OCRBoxItem, in boxes: [OCRBoxItem], medianHeight: Double) -> Bool { ... }
     fileprivate func isPhoneOrPhoneLabelLocal(_ box: OCRBoxItem, in boxes: [OCRBoxItem], medianHeight: Double) -> Bool { ... }
     ```
   - In `clusterBoxes`, inside the local function `isCuiAnchor`, check and ignore phone numbers and buyer boxes using these helpers:
     ```swift
     if isPhoneOrPhoneLabelLocal(box, in: deskewedBoxes, medianHeight: medianHeight) { return false }
     if isBuyerCUIBoxLocal(box, in: deskewedBoxes, medianHeight: medianHeight) { return false }
     ```
3. **Implement Line-based Proximity Search in `FinancialAmountsAgent.process`**:
   - Change spatial TOTAL extraction to find matching decimal boxes on the same horizontal line, mirroring `test_spatial_ocr.py` (lines 474–506).
   - Implement spatial TVA extraction using horizontal line-based search before math matching, mirroring `test_spatial_ocr.py` (lines 542–568).
   - Remove the dead line grouping code (lines 961-978).

### Detailed Fixes Required in Python Tests
1. **Python validation agent**:
   - Implement the `AccountingValidationAgent` corrections logic in `test_logic.py`, `test_spatial_ocr.py`, and `scratch/mock_test.py` to match Swift behavior.
   - For Receipts with no date (e.g. Receipt 5), the VAT rate of `5%` will be corrected to `11%`. Update assertions for Receipt 5 in `test_logic.py`, `test_spatial_ocr.py`, and `scratch/mock_test.py` to assert:
     - `vatPercentages` == `11%`
     - `vatAmount` == `7.93`
     - `baseAmount` == `72.07`
     - `totalAmount` == `80.00`
2. **Adversarial test verification**:
   - Locate and run the newly added `scratch/adversarial_tests.py`. Make sure it passes.

### Verification Guidelines
- Explain clearly to the user what commands you propose to run and wait for approval. Set `WaitMsBeforeAsync` appropriately or monitor completion when run.
- Build the server (check compilation).
- Run all python tests (`test_logic.py`, `test_spatial_ocr.py`, `scratch/mock_test.py`, `scratch/adversarial_tests.py`) to confirm success.
- Deliver your handoff report in `e:\OCR Iphone\.agents\worker_m2_remediate_gen3_retry1\handoff.md`.

### MANDATORY INTEGRITY WARNING
DO NOT CHEAT. All implementations must be genuine. DO NOT hardcode test results, create dummy/facade implementations, or circumvent the intended task. A Forensic Auditor will independently verify your work. Integrity violations WILL be detected and your work WILL be rejected.
