# Handoff Report — explorer_m1_gen2

## 1. Observation
- `test_logic.py` (lines 4-24) defines `is_valid_cui` and `extract_cui` which validates Romanian CUIs using a modulo 11 control digit check:
  ```python
  def is_valid_cui(cui):
      if not (2 <= len(cui) <= 10) or not cui.isdigit():
          return False
      ...
  ```
- `test_logic.py` (lines 143-165) uses `is_seller_cui_box` as a strict anchor filter, which calls `extract_cui` and requires mathematically valid CUIs to determine the number of receipts:
  ```python
      for box in boxes:
          cui = is_seller_cui_box(box, boxes, median_height)
          if cui:
              ...
              if not is_dup:
                  unique_anchors.append(box)
  ```
- `VaporServer.swift` (lines 1286-1309) uses hardcoded contains checks on strings for anchor detection, which is susceptible to OCR inaccuracies (e.g. "COD F1SCAL"):
  ```swift
              // Match seller CUI patterns
              let hasSeller = noDots.contains("COD FISCAL") ||
                              noSpaces.contains("CODFISCAL") ||
                              noDots.contains("IDENTIFICARE") ||
                              noSpaces.hasPrefix("CIF") ||
                              noDots.hasPrefix("CIF") ||
                              noDots.contains(" CIF")
  ```
- `VaporServer.swift` (lines 663-794) defines `CuiExtractorAgent.process`, which only saves CUIs that are validated by `isValidCUI(cui: numbersOnly)`. If validation fails, it falls back to a regex pattern (`"\\b([0-9]{2,10})\\b"`) that only matches pure digit sequences, completely discarding typos such as `"R077454P"`.

## 2. Logic Chain
1. Since the current clustering code in `test_logic.py` depends on mathematical validation of CUIs to establish anchors, any OCR error in the CUI itself (e.g., `"R077454P"` instead of `"RO7745470"`) will cause `is_seller_cui_box` to return `None`.
2. This failure prevents the anchor from being detected, causing the receipt to either be missed or clustered incorrectly.
3. Therefore, changing the anchor detection to match seller *keywords* (e.g. `"CIF"`, `"CUI"`) with fuzzy matching and spatial verification (and excluding buyer labels), rather than demanding valid CUIs, will allow robust clustering of all 6 receipts regardless of CUI spelling or digit errors.
4. Additionally, by adding an alphanumeric fallback of length 2–12 (which cleans common prefixes and ranks by physical distance to the CUI keyword anchor) in `CuiExtractorAgent.process`, we can retrieve noisy strings (like `"R077454P"`) when `isValidCUI` returns false.
5. In `FinancialAmountsAgent.process`, calculating missing `totalAmount` from the sum of VAT breakdowns if total is not directly found ensures amounts are always reconciled.

## 3. Caveats
- BNR XML API calls (for currency conversion/checking limits) assume network connectivity. If the server is offline, it will fall back to `5.0`.
- Highly distorted receipts (where columns overlap significantly and coordinates are chaotic) might still affect coordinate-based grid clustering.

## 4. Conclusion
We have designed a robust strategy for:
1. Fuzzy keyword-based anchor clustering.
2. Alphanumeric fallback CUI extraction for noisy OCR.
3. Total amount restoration based on VAT breakdowns.
4. Programmatic mock test setup that validates these scenarios (implemented as a Python script).

## 5. Verification Method
- Code inspect files:
  - `e:\OCR Iphone\.agents\explorer_m1_gen2\analysis.md` (detailed strategy and Swift changes).
  - `e:\OCR Iphone\.agents\explorer_m1_gen2\proposed_mock_test.py` (simulates the 6-receipt grid and confirms clustering + fallback CUI extraction).
- To run the validation script:
  ```powershell
  python "e:\OCR Iphone\.agents\explorer_m1_gen2\proposed_mock_test.py"
  ```
