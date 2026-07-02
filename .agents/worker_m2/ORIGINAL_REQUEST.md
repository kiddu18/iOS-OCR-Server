## 2026-07-02T12:37:45Z
You are a worker subagent. Your role is: worker.
Your working directory is: e:\OCR Iphone\.agents\worker_m2
Your task is:
1. Implement a Python test script `test_spatial_ocr.py` at the project root `e:\OCR Iphone`.
2. The script must simulate/implement the exact spatial parsing agents and logic from `VaporServer.swift` in Python, including:
   - `clusterBoxes(boxes)` (spatial clustering using horizontal and vertical thresholds based on median height).
   - same-line grouping and horizontal sorting with `yTolerance = medianHeight * 0.4`.
   - `DocumentClassificationAgent` (factura, bon fiscal, POS receipt, fuel, hand receipt, unknown).
   - `DocumentDetailsAgent` (regex extraction of series, number, and date).
   - `CuiExtractorAgent` (fuzzy lookup of CUI keywords, check self, check spatial proximity, validation checksum of CUI via `isValidCUI`, mock API verifyWithANAF, and regex fallback).
   - `FinancialAmountsAgent` (fuzzy lookup of total keywords, filter same line boxes, skip lines with "TVA", sanitize comma, regex match, fallback regex, ultimate fallback taking highest amount; POS/hand receipt vat logic; spatial VAT extraction, fallback VAT).
   - `FiscalComplianceAgent` (warnings for buyer CUI presence in Bon Fiscal, limit of 100 EUR from BNR mock rate, missing elements for Factura).
   - `AccountingOrchestrator` (integrates the pipeline).
3. Mock the external BNR EUR XML API and ANAF CUI API calls. Specifically, mock ANAF call to succeed for standard CUIs and allow simulating a timeout (so `cuiRequiresVerification` becomes true). Mock BNR lookup to return a rate (default 5.0).
4. Implement and run the 5 designed test scenarios:
   - Scenario 1: Happy Path (Standard Receipt)
     - Text: "S.C. MEGA IMAGE S.R.L.\nCIF: RO 8609468\nTVA 19% 19.00\nTOTAL 119.00"
     - Verify: cui = "8609468", total = 119.00, vat = 19.00, vatPercentages = "19%", baseAmount = 100.00, cuiRequiresVerification = False
   - Scenario 2: CUI Override and Compliance Logic (both matching and mismatching buyer CUI cases)
     - Text: "S.C. DANTE INTERNATIONAL S.A.\nCIF: RO 14399840\nCUI CUMPARATOR: RO 8609468\nTOTAL 100.00"
     - Match Case (buyerCui = "8609468"): expected cui = "14399840", no buyer CUI mismatch warnings.
     - Mismatch Case (buyerCui = "2816464"): expected cui = "14399840", and fiscalWarnings contains "Atenție: Bonul fiscal nu conține CUI-ul cumpărătorului (2816464). TVA-ul este complet nedeductibil!"
   - Scenario 3: TOTAL TVA Discrimination
     - Text: "SUBTOTAL 50.00\nTOTAL TVA A - 19% 9.50\nTOTAL 59.50"
     - Verify: totalAmount = 59.50 (the "TOTAL TVA" line is skipped, global "TOTAL" is matched)
   - Scenario 4: Dynamic yTol Alignment
     - Sub-case A: Large Title (Success) - TOTAL keyword (y=1000, h=50), 350.00 value (y=1022, h=50). yTol = 30.0. Spacing 22.0 < 30.0. Grouped. Verify total = 350.00.
     - Sub-case B: Small Distinct Lines (Ignore) - TOTAL keyword (y=1000, h=12), 8609468 value (y=1022, h=12). yTol = 15.0. Spacing 22.0 > 15.0. Separated. Verify total = None.
   - Scenario 5: General Edge Cases
     - Sub-case A: Split Decimal Box - TOTAL (x=100, y=900), 123 (x=780, y=900), .45 (x=835, y=900). Verify total is correctly reconstructed as 123.45.
     - Sub-case B: Comma Formatting - TOTAL, 123,45, LEI. Verify total is 123.45.
     - Sub-case C: ANAF Timeout - Extract CUI "14399840", ANAF lookup times out/fails. Verify cuiRequiresVerification = True, extracted CUI is preserved.
5. Create a Python script `test_spatial_ocr.py` that can be run from the command line using `python test_spatial_ocr.py`.
6. Run the script and report the test results back to the sub-orchestrator.

MANDATORY INTEGRITY WARNING — include this verbatim in the Worker's dispatch prompt:
"DO NOT CHEAT. All implementations must be genuine. DO NOT hardcode test results, create dummy/facade implementations, or circumvent the intended task. A Forensic Auditor will independently verify your work. Integrity violations WILL be detected and your work WILL be rejected."
