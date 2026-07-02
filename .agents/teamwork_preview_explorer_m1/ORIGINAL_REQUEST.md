## 2026-07-02T12:35:07Z
You are a teamwork_preview_explorer agent.
Your working directory is: e:\OCR Iphone\.agents\teamwork_preview_explorer_m1

Your task:
1. Initialize your BRIEFING.md and progress.md in your working directory.
2. Analyze the spatial extraction logic in e:\OCR Iphone\OcrServer\VaporServer.swift (specifically looking at classes/structs/methods around `FinancialAmountsAgent` and `CuiExtractorAgent`).
3. Explain how bounding boxes are matched, grouped, or ordered horizontally and vertically, and how values are associated with keys.
4. Analyze the recent changes regarding:
   - Dynamic vertical tolerance (`yTol`) based on the height of the bounding box (`box.h` or line height).
   - Filtering/ignoring "TVA" (like "TOTAL TVA") when searching for the global "TOTAL".
5. Design simulated OCR JSON test scenarios (giving actual JSON structures / contents / box coordinates where appropriate) to verify these behaviors:
   - Happy paths: standard receipts with clear CUI, VAT, and Total lines.
   - CUI override logic: receipts that specify a CUI that should be preferred, or where CUI is extracted.
   - Discrimination between "TOTAL TVA" line (e.g. "TOTAL TVA A - 21% 2.08") and the global "TOTAL" line.
   - Dynamic `yTol` scenarios: variations in text/box size, horizontal/vertical spacing, check how varying heights affect grouping logic.
   - General edge cases: OCR box merge failures, different formats (commas vs dots, spaces, currencies), ANAF API lookup timeouts/failures.
6. Write your analysis and designed test cases into: e:\OCR Iphone\.agents\teamwork_preview_explorer_m1\analysis_report.md
7. When done, send a message to your parent conversation (ID: 0997f221-51c5-4ad2-8a0a-04826a0f502f) with a summary of your findings and the path to your analysis_report.md file.
