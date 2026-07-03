# Handoff Report — Remediation Fixes

## 1. Observation
- Modified `e:\OCR Iphone\OcrServer\VaporServer.swift`:
  - **Swift Precedence Bug**: Changed line 936 `vatAmount = (totalCand - baseCand * 100).rounded() / 100` to `vatAmount = ((totalCand - baseCand) * 100).rounded() / 100`.
  - **Swift Single-VAT Total Preservation**: Inside `AccountingOrchestrator.processOcrResult` (around line 1127), replaced `splitCopy.totalAmount = ((b.baseAmount + b.vatAmount) * 100).rounded() / 100` with `splitCopy.totalAmount = breakdowns.count > 1 ? ((b.baseAmount + b.vatAmount) * 100).rounded() / 100 : (result.totalAmount ?? ((b.baseAmount + b.vatAmount) * 100).rounded() / 100)`.
  - **Restore Dynamic yTol**: In `FinancialAmountsAgent.process`, replaced the loop over pre-grouped lines with a loop over `boxes` individually using `yTol = max(box.h * 0.6, 15.0)` to find same-line candidate values to the right. Checked that `cleanText` does not contain "SUBTOTAL" and the line does not contain "TVA", "TAXA", or "TAXE".
  - **Swift Buyer CUI Space Normalization**: In `FiscalComplianceAgent.process`, normalized `fullText` and `buyerCui` to uppercase and stripped spaces before calling `.contains(...)`.
- Modified `e:\OCR Iphone\test_logic.py`:
  - Implemented `recursive_xy_cut` (mirroring `recursiveXYCut` in Swift).
  - Configured `cluster_boxes` to fallback to `recursive_xy_cut` when `len(unique_anchors) <= 1`.
  - Synced total amount preservation logic for single breakdowns.
  - Aligned `groups[best_idx].append(box)` outside the inner loop.
- Modified `e:\OCR Iphone\test_spatial_ocr.py`:
  - Synced `AccountingResult` to include `vatBreakdowns`.
  - Added exclusion of client-like CUI boxes inside `CuiExtractorAgent.process`.
  - Updated line check exclusions for "TVA", "TAXA", and "TAXE" inside `FinancialAmountsAgent.process`.
  - Populated `result.vatBreakdowns` in `FinancialAmountsAgent.process` and implemented single-VAT total preservation split logic in `process_ocr_result`.

- Attempted to run tests using:
  - `python test_logic.py`
  - `python test_spatial_ocr.py`
  - *Observation*: The commands timed out waiting for OS/user interactive permission approval in the code execution environment.

## 2. Logic Chain
- **Swift Precedence Fix**: The expression `(totalCand - baseCand * 100)` would multiply `baseCand` by 100 before subtraction, resulting in incorrect calculations. Parenthesizing as `((totalCand - baseCand) * 100)` guarantees subtraction runs first.
- **Single-VAT Total Preservation**: When there is only one VAT breakdown, we should preserve the original `result.totalAmount` if it is present, rather than reconstructing it from the sum of base and VAT (which could introduce rounding errors). If there are multiple breakdowns, we sum the parts.
- **Dynamic yTol**: By looping through each box individually instead of grouping them statically first, we handle cases where font sizes or header text heights vary, preventing grouping failures for large totals.
- **CUI Normalization**: Checking for CUI numbers inside full text using space-independent lookup prevents formatting mismatches (e.g. `RO 1234` matching `RO1234`).
- **Python-Swift Sync**: To keep the test suites representing the actual production server behavior, we synchronized `test_logic.py` and `test_spatial_ocr.py` with these exact algorithms.

## 3. Caveats
- Since the workspace commands timed out waiting for manual user confirmation of execution permission, they could not be verified in the shell directly during the automated run. However, the code was verified statically for syntax and logic alignment.

## 4. Conclusion
All requested remediation fixes were successfully implemented in `VaporServer.swift`, `test_logic.py`, and `test_spatial_ocr.py`.

## 5. Verification Method
- Inspect the file changes directly to check correct implementation.
- Run `python test_logic.py` and `python test_spatial_ocr.py` manually in the terminal when permissions are allowed to confirm they pass.
