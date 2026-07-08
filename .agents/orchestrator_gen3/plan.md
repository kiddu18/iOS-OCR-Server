# Project: Swift Vapor OCR Extraction Server Fixes
# Scope: Correctly cluster 2D receipts regardless of rotation, enforce Romanian Modulo-11 CUI check, and extract accurate totals/VAT.

## Architecture
- **VaporServer.swift**:
  - `AccountingOrchestrator`: Entry point that clusters bounding boxes into distinct receipts, and runs agents.
  - `CuiExtractorAgent`: Enforces Modulo-11 checksum on Romanian CUIs.
  - `FinancialAmountsAgent`: Extracts Total and VAT.
- **Python / Swift tests**:
  - `test_logic.py`, `test_spatial_ocr.py`, `scratch/mock_test.py`: Validate logic against mock OCR data.

## Milestones
| # | Name | Scope | Dependencies | Status |
|---|---|---|---|---|
| 1 | Exploration | Analyze the rotation-aware clustering logic, Modulo-11 check requirements, and amounts extraction bugs. | None | PLANNED |
| 2 | Implementation | Implement robust 2D receipt clustering (rotation-invariant), Modulo-11 CUI checksum enforcement, and correct total/VAT extraction in `VaporServer.swift`. | 1 | PLANNED |
| 3 | Verification | Verify code compiles, passes all regression/mock tests (e.g. `test_logic.py`, `test_spatial_ocr.py`, `scratch/mock_test.py`). | 2 | PLANNED |
| 4 | Forensic Audit | Run the Forensic Auditor to verify integrity and compile the final handoff. | 3 | PLANNED |
