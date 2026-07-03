## 2026-07-03T10:16:54Z
You are a developer worker task with implementing final bug fixes and running verification tests.

MANDATORY INTEGRITY WARNING:
DO NOT CHEAT. All implementations must be genuine. DO NOT hardcode test results, create dummy/facade implementations, or circumvent the intended task. A Forensic Auditor will independently verify your work. Integrity violations WILL be detected and your work WILL be rejected.

Tasks:
1. Apply the following fixes to e:\OCR Iphone\OcrServer\VaporServer.swift:
   - In CuiExtractorAgent, update cleanCandidate(rawText:) to include "R0" (R-zero) in the prefixes array so it gets stripped during CUI fallback.
   - In FinancialAmountsAgent, check if rate is 0.0 before dividing by it. If rate == 0.0, set baseAmount = val and vatAmount = 0.0 directly.
   - In FinancialAmountsAgent, update the line check for "TVA"/"TAXA"/"TAXE" keywords. Exclude "TVA INCLUS", "TVA INCL", "TAXE INCLUSE", "TAXA INCLUSA" from triggering a skip. E.g., only skip if line contains TVA/TAXA/TAXE but not as part of those inclusive labels.
2. Apply the following fixes to e:\OCR Iphone\scratch\mock_test.py and e:\OCR Iphone\test_spatial_ocr.py:
   - In extract_financials, invoke is_buyer_cui_box(...) (or is_buyer_cui_box in the python code) during the candidate boxes loop to correctly filter out buyer CUI.
   - In clean_fallback_candidate (or the equivalent fallback cleaning function), include "R0" in the prefixes list.
3. Verify changes by executing the python tests:
   - python scratch/mock_test.py
   - python test_spatial_ocr.py
   Confirm that all tests pass successfully.
4. Document all changes and the exact command execution outputs in e:\OCR Iphone\.agents\worker_m2_remediate_gen2\handoff.md. Send a message back when complete.
