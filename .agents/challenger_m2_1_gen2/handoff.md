# Handoff Report — challenger_m2_1_gen2

## 1. Observation
- **Action attempted**: Executed commands `python scratch/mock_test.py` and `python test_spatial_ocr.py` via `run_command` in `e:\OCR Iphone`.
- **Verbatim Tool Error**:
  ```
  Encountered error in step execution: Permission prompt for action 'command' on target 'python scratch/mock_test.py' timed out waiting for user response. The user was not able to provide permission on time.
  ```
- **Code checked**:
  - `e:\OCR Iphone\scratch\mock_test.py` lines 44-90 (defining `is_buyer_cui_box`), lines 393-413 (where CUI candidate boxes are filtered in `extract_financials`), lines 108-175 (the `extract_cui_with_fallback` implementation), and lines 558-694 (the mock test assertions).
  - `e:\OCR Iphone\test_spatial_ocr.py` lines 180-246 (the `CuiExtractorAgent` implementation).
  - `e:\OCR Iphone\OcrServer\VaporServer.swift` lines 664-754 (Swift `CuiExtractorAgent` and nested helper `isBuyerBox` implementation).
- **Environment**: User OS is **Windows** (Xcode project `OcrServer.xcodeproj` is present but requires macOS / `xcodebuild` toolchain).

## 2. Logic Chain
1. Since execution of command-line tools is blocked by permission prompt timeouts in this automated harness, we performed a dry run analysis of the Python and Swift files (Observation 1).
2. The mock receipt canvas layout in `scratch/mock_test.py` consists of 6 receipts in a 2x3 grid, which produces 6 unique clusters using coordinates and v-cuts/h-cuts (Observation 1).
3. The mock receipts are processed into exactly 7 output rows (Receipt 4 has two VAT rates and splits into 2 rows; the others produce 1 row each).
4. However, we discovered a bug in `scratch/mock_test.py` CUI extraction:
   - The test script defines `is_buyer_cui_box` on line 44, but never calls it in `extract_financials` or `extract_cui_with_fallback`.
   - The buyer CUI box `"RO 87654329"` in Receipt 1 is not skipped, because the candidate loop only checks if substring `"CLIENT"` is in the box itself.
   - Because `87654329` is mathematically valid, it gets extracted as the seller CUI, causing the test's CUI assertion to fail: `assert len(r1_rows) == 1` fails on line 674.
5. In `test_spatial_ocr.py`, a similar lack of buyer CUI exclusion exists in `CuiExtractorAgent.process`, but it happens to pass Scenario 2 only due to the specific order of the input boxes in `s2_boxes` (the seller CUI box is processed first).
6. In the core Swift implementation `OcrServer/VaporServer.swift`, this bug is **not present**: `isBuyerBox` is correctly called in the extraction loop on line 732, meaning the production code behaves correctly and filters out the buyer CUI.

## 3. Caveats
- Command execution was simulated and verified via manual code-path tracing since `run_command` timed out.
- Assumed standard python execution behavior for standard libraries `re` and `functools`.

## 4. Conclusion
The core Swift spatial OCR implementation in `VaporServer.swift` is correct and robust against buyer CUI extraction issues. However, the Python verification scripts (`scratch/mock_test.py` and `test_spatial_ocr.py`) have a logical bug where they do not call the buyer box filter helper, meaning the mock test script will raise an `AssertionError` if run. 

## 5. Verification Method
1. Run the Python mock test script in an interactive terminal where permission is granted:
   ```powershell
   python scratch/mock_test.py
   ```
2. Verify that it raises an `AssertionError` at line 674 due to `cui` mismatch for Receipt 1.
3. Fix the mock script by adding the call to `is_buyer_cui_box(box, boxes, median_height)` inside `extract_financials` CUI candidate loop to see it pass successfully.
