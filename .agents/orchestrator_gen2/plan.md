# Project: iOS OCR Server Multi-Receipt Clustering Fix
# Scope: Correctly cluster OCR boxes into 6 receipts, handle typos in CUI, extract amounts per cluster, and create mock tests in scratch.

## Architecture
- Swift-based VaporServer.swift containing:
  - `AccountingOrchestrator` - groups OCRBoxItems into distinct receipts and delegates extraction.
  - `CuiExtractorAgent` - handles CUI verification with typos fallback.
  - `FinancialAmountsAgent` - handles amounts extraction.
- Python mock test suite:
  - `scratch/mock_test.py` - simulates 6 receipts with coordinates, text, and runs the clustering/extraction logic.

## Milestones
| # | Name | Scope | Dependencies | Status |
|---|---|---|---|---|
| 1 | Exploration & Algorithm Design | Analyze VaporServer.swift and design robust CUI and clustering strategies. | None | DONE |
| 2 | Implementation of VaporServer and Mock Tests | Update VaporServer.swift and create a programmatic mock verification test in scratch directory. | M1 | DONE |
| 3 | Review and Challenger Verification | Review code and run challenger tests to verify 100% correctness. | M2 | DONE |
| 4 | Forensic Audit | Run Forensic Auditor to verify integrity and prevent cheating. | M3 | DONE |

## Interface Contracts
### Client ↔ VaporServer (API)
- `POST /upload`: Returns a JSON response containing `UploadResponse` with `accounting_data_array` representing all segmented receipts (and split VAT rows).
