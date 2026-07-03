# Handoff Report - Empirical Verification of Spatial OCR

## 1. Observation
- **Command Executions**:
  - Proposing `python scratch/mock_test.py` in `e:\OCR Iphone` failed with error:
    `Encountered error in step execution: Permission prompt for action 'command' on target 'python scratch/mock_test.py' timed out waiting for user response.`
  - Proposing `python test_spatial_ocr.py` failed with the identical permission prompt timeout.
  - Compiling the Swift project is not feasible because the user's operating system is Windows, where `xcodebuild` (Xcode toolchain) is unavailable.
- **Python Mock Code (scratch/mock_test.py)**:
  - In `extract_financials` (lines 401-410):
    ```python
    # CUI Extraction
    cui_keywords = ["CIF", "CUI", "CODFISCAL", "RO"]
    candidate_boxes = []
    for box in boxes:
        clean_text = box["text"].upper().replace(".", "").replace(" ", "")
        if "CLIENT" in clean_text or "CUMP" in clean_text or "BENEF" in clean_text or "CNP" in clean_text:
            continue
        if any(kw in clean_text or (len(clean_text) <= len(kw) + 2 and is_fuzzy_match(clean_text, kw, 1)) for kw in cui_keywords):
            candidate_boxes.append(box)
    ```
  - The 2D spatial check helper `is_buyer_cui_box(...)` is defined on line 44 but is never called inside `extract_financials` or `extract_cui_with_fallback`.
- **Python Test Code (test_spatial_ocr.py)**:
  - In `CuiExtractorAgent.process` (lines 185-194):
    ```python
    # 1. Cautare Spatiala Inteligenta 2D (Fuzzy)
    cui_keywords = ["CIF", "CUI", "CODFISCAL", "RO"]
    candidate_boxes = []
    
    for box in boxes:
        clean_text = box.text.upper().replace(".", "").replace(" ", "")
        if "CLIENT" in clean_text or "CUMP" in clean_text or "BENEF" in clean_text or "CNP" in clean_text:
            continue
        if any(kw in clean_text or (len(clean_text) <= len(kw) + 2 and is_fuzzy_match(clean_text, kw, 1)) for kw in cui_keywords):
            candidate_boxes.append(box)
    ```
  - Similarly, there is no spatial check to exclude buyer CUI boxes in `CuiExtractorAgent.process`.
- **Swift Core Implementation (OcrServer/VaporServer.swift)**:
  - Inside `CuiExtractorAgent.process` (lines 729-734):
    ```swift
    for box in boxes {
        let cleanText = box.text.uppercased().replacingOccurrences(of: ".", with: "").replacingOccurrences(of: " ", with: "")
        
        if isBuyerBox(box, medianHeight: medianHeight) {
            continue
        }
    ```
    This correctly filters out buyer boxes spatially before adding them to candidate boxes.
- **Previous Agent Run results**:
  - Found recorded in `e:\OCR Iphone\.agents\challenger_m2_1_gen2\results.md`.

## 2. Logic Chain
1. Since the execution environment timed out during the permission prompt for `run_command`, empirical verification cannot rely on running CLI scripts. We must instead use static logic tracing.
2. Tracing `cluster_boxes(boxes)` in `scratch/mock_test.py`:
   - It identifies 6 unique seller anchors:
     1. "CIF" at $(100, 100)$
     2. "CIF" at $(600, 100)$
     3. "CUI RO 12345674" at $(100, 600)$
     4. "CUI: RO 123456789" at $(600, 600)$
     5. "CIF R0987654A" at $(100, 1100)$
     6. "CUI RO 55553" at $(600, 1100)$
   - Using row cuts at $y = 350, 850$ and column cuts at $x = 350$, it correctly partitions the canvas into a 2x3 grid, resulting in **exactly 6 clusters**.
3. Tracing `extract_financials` on each cluster:
   - Receipts 1, 2, 3, 5, and 6 yield 1 row each.
   - Receipt 4 contains multiple VAT rates (19% and 9%), which splits it into 2 rows.
   - Total rows = $1 \times 5 + 2 = 7$ accounting rows.
4. Tracing the CUI extraction step for Receipt 1:
   - The buyer box `{"text": "RO 87654329", "x": 180, "y": 200}` contains "RO", which is in `cui_keywords`.
   - Since "RO 87654329" does not contain any of the negative keywords (`"CLIENT"`, `"CUMP"`, `"BENEF"`, `"CNP"`), it is incorrectly appended to `candidate_boxes`.
   - Because `is_buyer_cui_box` is never called, the buyer box is processed.
   - `87654329` is mathematically valid. Thus, `extract_cui_with_fallback` returns `87654329` as the seller CUI.
   - This causes the mock test assertion `assert len(r1_rows) == 1` (where `r1_rows` filters for CUI `12345P`) to fail in the Python mock test script.
5. Checking the Swift implementation shows `isBuyerBox` is correctly called, which filters out the buyer box `"RO 87654329"` before CUI evaluation, meaning the production codebase behaves correctly.

## 3. Caveats
- Command executions were not tested live due to environment timeouts.
- Swift code compilation was not performed as the operating system is Windows (Xcode projects are only buildable on macOS).

## 4. Conclusion
- **Clustering and Row Generation**: Correctly generates 6 clusters and 7 accounting rows.
- **Python test mock discrepancy**: A bug exists in both `scratch/mock_test.py` and `test_spatial_ocr.py` where a buyer CUI (`87654329` in Receipt 1) is incorrectly extracted as the seller CUI, which would cause `scratch/mock_test.py` to fail its assertions if run.
- **Production Swift Core**: Production Swift code is correct and does not contain this bug.

## 5. Verification Method
- **To test Python mock execution**: Run `python scratch/mock_test.py` and `python test_spatial_ocr.py` on a platform where command approval is possible.
- **Verification of Swift Code**: Inspect lines 729-734 in `OcrServer/VaporServer.swift`.
