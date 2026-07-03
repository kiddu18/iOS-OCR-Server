# Project: iOS OCR Server Spatial 2D Fix
# Scope: Multi-receipt segmentation, robust extraction, and VAT rate splitting in VaporServer.swift

## Architecture
- Swift-based VaporServer.swift containing:
  - `AccountingOrchestrator` - clusters OCRBoxItems into individual receipt groups and coordinates agents.
  - `CuiExtractorAgent` - extracts and verifies Seller CUI using spatial logic.
  - `FinancialAmountsAgent` - extracts Totals and VAT breakdowns.
  - `FiscalComplianceAgent` - checks deduction compliance and limits.
- Python verification suite:
  - `test_logic.py` - simulates/mocks the OCR boxes for 6 receipts in one image, tests the clustering, extraction, and split logic.

## Milestones
| # | Name | Scope | Dependencies | Status |
|---|---|---|---|---|
| 1 | Spatial OCR Exploration and Algorithm Design | Analyze VaporServer.swift, identify split OCR box and layout shift edge cases, design 6-receipt mock data and clustering/extraction algorithms. | None | DONE |
| 2 | Implementation of Spatial 2D Engine Fixes & Verification Tests | Implement multi-receipt clustering, split CUI/VAT extraction, and VAT splitting in VaporServer.swift. Create `test_logic.py` to verify with mock OCR coordinates. | M1 | IN_PROGRESS |
| 3 | Review and Verification | Run Reviewer and Challenger/Auditor to inspect the code changes, ensure no regressions on Scenario 1-5, and verify that the 6-receipt tests pass. | M2 | PLANNED |
| 4 | Final Synthesis | Validate Vapor server build, review logs/WebUI verification if possible, and write the final report. | M3 | PLANNED |

## Interface Contracts
### Client ↔ VaporServer (API)
- `POST /upload`: Returns a JSON response containing `UploadResponse` with `accounting_data_array` representing all segmented receipts (and split VAT rows).
- Each record in `accounting_data_array` corresponds to a physical receipt (or a specific VAT rate of a receipt) containing `cui`, `totalAmount`, `vatAmount`, `vatPercentages`, and `baseAmount`.
