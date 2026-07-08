# Handoff Report - explorer_m1_gen3_3

## 1. Observation
I directly observed the following files and code blocks:
* **`OcrServer/VaporServer.swift`**:
  * Line 28: `let rect: OCRRectItem?` in `OCRBoxItem` structure.
  * Lines 831-847: Groups boxes into lines using:
    ```swift
    if abs(box.y - currentLine[0].y) < yTolerance {
        currentLine.append(box)
    }
    ```
  * Line 882: Strict decimal pattern `([0-9]+[.][0-9]{2})`.
  * Line 959: Strict decimal pattern `decPattern = "(?<!%)\\b([0-9]+[.,][0-9]{2})\\b(?!\\s*%)"`.
  * Lines 982-1015: Mathematical matching checking:
    ```swift
    if abs(val - expectedVat) <= 0.05
    ```
    and
    ```swift
    if abs(vatCand - baseCand * (rate / 100.0)) <= 0.05
    ```
  * Lines 1639-1741: `findBestGapSplit` and `recursiveSplit` that perform bisection using axis-aligned coordinates `x` and `y`.
* **`test_spatial_ocr.py`**:
  * Lines 613-636: Connected-components clustering using axis-aligned delta checks:
    ```python
    dx = max(0.0, max(current.x - (box.x + box.w), box.x - (current.x + current.w)))
    dy = max(0.0, max(current.y - (box.y + box.h), box.y - (current.y + current.h)))
    if dx < horizontal_threshold and dy < vertical_threshold:
    ```
* **`test_logic.py`**:
  * Lines 85-141: `recursive_xy_cut` using axis-aligned intervals on X and Y:
    ```python
    if b["x"] <= last["max"] + median_height * 2.5:
    ```
  * Lines 166-222: Column/Row midpoints cuts grid allocation.
* **`scratch/mock_test.py`**:
  * Line 266: Hardcoded column split: `col_of_box = 0 if box["x"] < 500 else 1`.

## 2. Logic Chain
1. **Rotation vulnerability**: Under rotation, the projection of receipt bounding boxes overlaps along the X and Y axes (Observation: `recursiveSplit`, `recursive_xy_cut`, `is_buyer_cui_box`, and `line grouping` rely directly on raw `x` and `y` coordinates). Therefore, any document rotation skewing the coordinate system will group unrelated items or misalign lines.
2. **Deskewing possibility**: Bounding boxes in Vision OCR contain the corners in `OCRRectItem` (Observation: `let rect: OCRRectItem?` in `VaporServer.swift:28`). Therefore, we can compute the median skew angle $\theta_{global}$ and transform the coordinates to deskewed values $(x', y')$ to make the clustering and line grouping rotation-invariant.
3. **Regex decimal limitation**: The current regex pattern (Observation: `decPattern` in `VaporServer.swift:959`) strictly expects exactly two decimal places. As a result, integers or numbers with a single decimal place are ignored, failing mathematical matches when those values are parsed.
4. **Tight matching tolerance**: The hard tolerance limit of 0.05 (Observation: `abs(val - expectedVat) <= 0.05` in `VaporServer.swift:986`) fails on OCR noise or minor rounding variances. A cost-based constraint solver will provide a softer, more robust optimization.

## 3. Caveats
* The ANAF web service for CUI validation is not mocked in the production Vapor server, meaning production runs require network access (which is blocked in CODE_ONLY mode).
* Skew angle calculation assumes that most text lines in the document are parallel (which holds for normal scanned documents but might fail for multi-oriented text/collages).

## 4. Conclusion
The implementation can be optimized for robust amounts extraction and rotation-invariant clustering by:
1. Deskewing coordinates using the median slope computed from `OCRRectItem` corners.
2. Updating the strict decimal regex to a flexible number parser matching integers and single decimals.
3. Implementing a cost-based constraint solver for math validation of totals, bases, and VATs.

## 5. Verification Method
* To verify the clustering correctness under rotation:
  1. Add a test script (e.g. `test_rotated_clustering.py`) containing bounding boxes rotated by a fixed angle $\theta$ (e.g., 30 degrees).
  2. Implement coordinates transformation $(x, y) \to (x', y')$ based on the skew angle.
  3. Verify that the clustering output on rotated boxes is identical to the output on unrotated boxes.
* To verify amounts extraction robustness:
  1. Construct a mock test containing integer amounts (e.g. `100`, `19`, `119`) and verify that they are correctly extracted and mathematically matched.
