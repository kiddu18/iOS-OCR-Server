## 2026-07-03T10:07:39Z
You are a developer worker task with implementing the spatial OCR improvements in VaporServer.swift and establishing programmatic tests.

MANDATORY INTEGRITY WARNING:
DO NOT CHEAT. All implementations must be genuine. DO NOT hardcode test results, create dummy/facade implementations, or circumvent the intended task. A Forensic Auditor will independently verify your work. Integrity violations WILL be detected and your work WILL be rejected.

Tasks:
1. Implement the designed fixes in e:\OCR Iphone\OcrServer\VaporServer.swift:
   - In clusterBoxes: Use fuzzy matching for CIF/CUI/CODFISCAL/COD FISCAL keywords as anchors, exclude buyer-associated anchors, and deduplicate anchors based on horizontal/vertical coordinates.
   - In CuiExtractorAgent: Add a robust fallback for CUI strings with OCR typos. If no mathematically valid CUI is found, search for nearby (and keyword box) alphanumeric sequences of length 2-12 containing at least one digit, sort them by distance to the keyword box, and select the closest one as result.cui with cuiRequiresVerification = true.
   - In FinancialAmountsAgent: Reconstruct the total amount as the sum of base and VAT amounts from breakdowns if the total is missing but breakdowns exist.
2. Create the directory e:\OCR Iphone\scratch (if it doesn't exist) and write a python script scratch/mock_test.py containing the programmatic mock test verified in e:\OCR Iphone\.agents\explorer_m1_gen2\proposed_mock_test.py.
3. Run scratch/mock_test.py and verify that all assertions pass successfully.
4. Run python test_spatial_ocr.py to ensure there are no regressions on the existing test suite.
5. Compile/build the Vapor server project to ensure there are no syntax or compilation errors.

Write a handoff report documenting the changes made, the exact verification commands run, and their full output at e:\OCR Iphone\.agents\worker_m2_gen2\handoff.md.
