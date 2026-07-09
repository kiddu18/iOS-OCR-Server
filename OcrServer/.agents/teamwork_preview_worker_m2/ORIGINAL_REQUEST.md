## 2026-07-09T09:46:21Z
You are teamwork_preview_worker. Your working directory is e:\OCR Iphone\OcrServer\.agents\teamwork_preview_worker_m2.

Please implement the following changes in the workspace:

1. R3 Payment Account Suggestions:
- In `e:\OCR Iphone\OcrServer\VaporServer.swift`:
  - Inside `AccountingValidationAgent.process` (around line 1128): Check if `result.documentType == "Chitanță de mână"`, set `result.suggestedAccount = "5311"`. Check if `result.documentType == "Chitanță POS"`, set `result.suggestedAccount = "5125"`. Otherwise, run the default suggestion logic.
  - Inside the `forcedDocumentType` check (around line 1224): If forced is "Chitanță de mână", set `result.suggestedAccount = "5311"`. If forced is "Chitanță POS", set `result.suggestedAccount = "5125"`.
- In `e:\OCR Iphone\WebClient\app.js`:
  - Inside `suggestAccount(companyName, fileType)` (around line 88): Check if `fileType === 'Chitanță de mână'`, return `'5311'`. Check if `fileType === 'Chitanță POS'`, return `'5125'`.
- In `e:\OCR Iphone\test_adversarial_challenger.py` and `e:\OCR Iphone\scratch\adversarial_tests.py`:
  - Inside `suggest_account` (around line 766): Check if `result.documentType == "Chitanță de mână"`, set `result.suggestedAccount = "5311"` and return. Check if `result.documentType == "Chitanță POS"`, set `result.suggestedAccount = "5125"` and return.

2. Align Python tests with CUI constraints and prevent fake CUI anchors:
- In `e:\OCR Iphone\test_adversarial_challenger.py`, `e:\OCR Iphone\test_spatial_ocr.py`, and `e:\OCR Iphone\scratch\adversarial_tests.py`:
  - In `is_valid_cui(cui: str) -> bool`: Change length requirement to `4 <= len(cui) <= 10` (from `2 <= len(cui) <= 10`), matching the Swift implementation.
  - In the third fallback total amount extraction logic inside `FinancialAmountsAgent.process` (taking the largest number): Parse the CUI from `result.cui` (if it exists) into a float and exclude this value from the candidate total amounts list to avoid extracting the CUI as the total amount.

3. Execution and verification:
- Execute the python tests `test_logic.py`, `test_spatial_ocr.py`, and `test_adversarial_challenger.py` using PowerShell with environment variable `$env:PYTHONIOENCODING="utf-8"` set, and verify they all compile and pass successfully.

Write your final report to e:\OCR Iphone\OcrServer\.agents\teamwork_preview_worker_m2\handoff.md.

MANDATORY INTEGRITY WARNING:
DO NOT CHEAT. All implementations must be genuine. DO NOT hardcode test results, create dummy/facade implementations, or circumvent the intended task. A Forensic Auditor will independently verify your work. Integrity violations WILL be detected and your work WILL be rejected.
