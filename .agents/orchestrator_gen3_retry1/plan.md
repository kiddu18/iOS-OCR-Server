# Plan: Swift Vapor OCR Extraction Server Fixes

This plan outlines the detailed steps to correct issues in 2D grid clustering, Modulo-11 CUI check, amounts parsing, and validation.

## Milestones and Steps

### Milestone 1: Exploration
- [x] Gather previous plans, progress, and reports.
- [x] Analyze the skew angle deskewing, Modulo-11, and amounts logic.

### Milestone 2: Implementation (Current)
- [ ] Dispatch worker to fix `OcrServer/VaporServer.swift`:
  - **CUI extraction**: Enhance `isBuyerBox` with spatial checks (checking left or above coordinates for client keywords). Exclude phone numbers. Do not return eagerly on the first match if it is an invalid CUI or a phone number.
  - **Financial amount parsing**: Update `parseFormattedAmount` to correctly ignore space, commas, and dots thousands separators and extract exact decimals. Allow single decimal or integers.
  - **VAT Breakdown correction in validation**: Ensure `AccountingValidationAgent.correctVatRates` corrects the percentages and amounts *inside* `result.vatBreakdowns` too, not just in `result.vatPercentages`, `result.vatAmount`, and `result.baseAmount`.
  - **Mock and test script sync**: Ensure python scripts (`test_logic.py`, `test_spatial_ocr.py`, `scratch/mock_test.py`) are kept synchronized with Swift logic.
- [ ] Implement and compile.

### Milestone 3: Verification
- [ ] Run python verification scripts (`test_logic.py`, `test_spatial_ocr.py`, `scratch/mock_test.py`) to verify they pass.
- [ ] Verify that Vapor Server compiles and runs.

### Milestone 4: Forensic Audit
- [ ] Run the Forensic Auditor (`teamwork_preview_auditor`) to verify integrity.
