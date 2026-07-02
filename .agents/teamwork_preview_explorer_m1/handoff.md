# Handoff Report

## 1. Observation
- Analyzed `e:\OCR Iphone\OcrServer\VaporServer.swift`:
  - `CuiExtractorAgent` is defined at line 628. Nearby scan logic uses:
    ```swift
    $0.y >= keywordBox.y - keywordBox.h * 0.8 && $0.y <= keywordBox.y + keywordBox.h * 2.0 &&
    $0.x >= keywordBox.x - keywordBox.w * 0.5
    ```
  - `FinancialAmountsAgent` is defined at line 780. Dynamic vertical tolerance:
    ```swift
    let yTol = max(box.h * 0.6, 15.0)
    ```
  - `TOTAL TVA` line exclusion:
    ```swift
    let lineTextForCheck = lineBoxes.map { $0.text.uppercased() }.joined(separator: " ")
    if lineTextForCheck.contains("TVA") {
        continue // Ignoram liniile "TOTAL TVA"
    }
    ```
  - Romanian CUI validation (`isValidCUI` method) at line 700.
  - `AccountingOrchestrator` text block formation at line 1002.
- Verified logic of `isValidCUI` in `test_regex.swift` at line 6.

## 2. Logic Chain
1. **Vertical alignment & line grouping**: `AccountingOrchestrator` uses `yTolerance = medianHeight * 0.4` to group boxes into lines, then sorts them horizontally.
2. **Spatial associations**: In both CUI and Total agents, keyword boxes (keys) are matched, and then candidates (values) are filtered by dynamic vertical boundaries (`yTol` based on `box.h * 0.6` or height ratios like `-0.8h` to `+2.0h`) and horizontal bounds (`x` position relative to keyword).
3. **Ignored sub-totals**: Concatenating lines and checking for `"TVA"` prevents picking up the `"TOTAL TVA"` values as the global receipt total, since a true total line does not contain `"TVA"`.
4. **Resilience**: CUI extraction persists the extracted value even if ANAF verification fails or times out, by setting `result.cui = numbersOnly` after catching errors.

## 3. Caveats
- No actual Swift test suite exists in the workspace; validation was done by inspection of source files.
- The CUI extractor returns the first valid CUI it finds. If a receipt contains both vendor and buyer CUIs, the result relies on the order Vision/OCR returns the boxes (typically top-to-bottom), which can lead to extracting the buyer CUI if it appears before the vendor CUI, unless `buyerCui` is passed in the request to compare against.

## 4. Conclusion
The OCR spatial extraction logic successfully handles line misalignment (via dynamic `yTol`) and avoids false-positive total amounts from VAT summary lines (via TVA check). Five detailed JSON test cases were designed and documented in `analysis_report.md` to cover happy paths, CUI overrides, TVA filtering, yTol variations, and edge cases.

## 5. Verification Method
1. Inspect `e:\OCR Iphone\.agents\teamwork_preview_explorer_m1\analysis_report.md` to verify the designed test scenarios.
2. Review the Swift implementation files referenced above to confirm matching line numbers and logic.
