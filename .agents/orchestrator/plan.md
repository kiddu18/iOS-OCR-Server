# Project: OCR Iphone Testing
# Scope: Comprehensive Testing and Manual Review of OCR Server Spatial Logic

## Architecture
- Swift-based VaporServer.swift containing:
  - `AccountingOrchestrator` - parses OCRBoxItems, groups them into document clusters, and runs extraction agents.
  - `DocumentClassificationAgent` - classifies document type.
  - `DocumentDetailsAgent` - extracts series, number, and date.
  - `CuiExtractorAgent` - extracts and validates CUI (CIF) using spatial logic and ANAF API.
  - `FinancialAmountsAgent` - extracts global total amount and VAT amount using 2D spatial search.
  - `FiscalComplianceAgent` - checks fiscal limits and CUI deduction warnings.
- The test suite will be written in Python, porting/simulating the Swift spatial agent extraction algorithms to run against simulated JSON OCR configurations.

## Milestones
| # | Name | Scope | Dependencies | Status |
|---|---|---|---|---|
| 1 | Codebase Analysis and Test Design | Trace VaporServer.swift spatial logic, identify edge cases, design test scenarios (CUI override, total vs total tva) | None | DONE |
| 2 | Test Suite Implementation | Implement Python simulation of Swift agents and run the automated test cases | M1 | IN_PROGRESS |
| 3 | Verification & Edge Case Validation | Verify test correctness, confirm fixes work correctly and do not crash on unexpectedly formatted receipts | M2 | PLANNED |
| 4 | Final Reporting | Synthesize findings into the final manual review and test results report | M3 | PLANNED |

## Interface Contracts
- Input to `AccountingOrchestrator.processOcrResult`: Array of OCRBoxItem JSONs, optional buyer CUI string.
- Output from `AccountingOrchestrator.processOcrResult`: `AccountingResult` structure containing:
  - documentType: String?
  - documentSeries: String?
  - documentNumber: String?
  - documentDate: String?
  - cui: String?
  - totalAmount: Double?
  - vatAmount: Double?
  - vatPercentages: String?
  - baseAmount: Double?
  - fiscalWarnings: [String]
  - globalRequiresManualVerification: Bool
