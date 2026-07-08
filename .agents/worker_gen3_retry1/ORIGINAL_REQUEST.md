## 2026-07-08T04:49:13Z
You are an Implementation Worker. Your working directory is e:\OCR Iphone\.agents\worker_gen3_retry1.
Your task is to fix the Vapor OCR extraction server and synchronize python verification scripts.

### Context and Source Files
- Swift Vapor Server source: `e:\OCR Iphone\OcrServer\VaporServer.swift`
- Verification python scripts:
  - `e:\OCR Iphone\test_logic.py`
  - `e:\OCR Iphone\test_spatial_ocr.py`
  - `e:\OCR Iphone\scratch\mock_test.py`

### Specific Tasks
1. Run the Python verification scripts (`test_logic.py`, `test_spatial_ocr.py`, `scratch/mock_test.py`) using `run_command` in `e:\OCR Iphone` to see current test failures and debug output.
2. Fix the following issues in `OcrServer/VaporServer.swift`:
   - **CUI extraction & phone numbers**:
     - Implement a robust, spatial `isBuyerCUIBox` check in `CuiExtractorAgent.process` (using relative coordinates: same line or directly above) to ignore buyer/client CUIs.
     - Ignore any candidate boxes that are associated with phone number labels (like `"TEL"`, `"FAX"`, `"MOBIL"`, `"TELEFON"`, etc.) or matches Romanian phone numbers (10 digits starting with `07`, `02`, `03`).
     - Ensure that all CUI extraction loops check these guards before eagerly returning.
   - **VAT Breakdown correction in validation**:
     - In `AccountingValidationAgent.correctVatRates`, make sure that when a VAT rate is corrected (e.g., 19% to 21% or 5% to 11%), it also updates the matching breakdowns inside `result.vatBreakdowns` (by modifying their `percentage`, `vatAmount`, and `baseAmount` fields). This prevents the final split logic in `processOcrResult` from using the old, uncorrected values.
   - **Totals & VAT amounts**:
     - Ensure that amounts parsing and regex logic correctly support spaces, commas, and dots as thousands separators.
     - Check if there is any horizontal alignment or line grouping issue under rotation, and solve it.
3. Synchronize `test_logic.py`, `test_spatial_ocr.py`, and `scratch/mock_test.py` logic with any fixes made to `VaporServer.swift` to ensure they match exactly.
4. Run all the Python tests to verify that they pass successfully.
5. Rebuild the Vapor server to verify that it compiles without errors. Note: To compile, you can run a swift build command or compile the project via xcodebuild if in a macOS environment, or whatever the user's workspace contains for building OcrServer. (Check xcode project `OcrServer.xcodeproj` or look for build commands in existing files or readmes).
6. Deliver a handoff report in `e:\OCR Iphone\.agents\worker_gen3_retry1\handoff.md` summarizing the changes, verification outputs, and compilation status.

### MANDATORY INTEGRITY WARNING
DO NOT CHEAT. All implementations must be genuine. DO NOT hardcode test results, create dummy/facade implementations, or circumvent the intended task. A Forensic Auditor will independently verify your work. Integrity violations WILL be detected and your work WILL be rejected.
