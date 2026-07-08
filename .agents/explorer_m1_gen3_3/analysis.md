# Analysis of Vapor Server Amounts Extraction and 2D Clustering

## Executive Summary
This report analyzes the current implementation of amounts extraction (TVA, Totals, Base) and 2D clustering in the Vapor OCR server and mock scripts. It identifies critical vulnerabilities regarding document rotation and strict format parsing, and proposes robust, math-validated optimization solutions using deskewing transformations and constraint-based amount solvers.

---

## 1. Current Implementation Overview

### 1.1 2D Clustering
* **VaporServer.swift (`clusterBoxes` method)**:
  * Uses **Recursive Bisection Clustering** based on CUI anchors (`CODFISCAL`, `CIF` etc.).
  * For multiple CUI anchors, it evaluates axis-aligned splits on the X and Y coordinates. It calculates center coordinates (`x + w/2`, `y + h/2`), identifies splits that partition the anchors, and chooses the split on the axis with the largest gap.
  * If no or one CUI anchor is present, it returns all boxes as a single cluster (no splitting).
* **test_logic.py (`cluster_boxes` method)**:
  * If multiple anchors: Groups unique CUI anchors into columns (X distance < 12 * median height) and rows (Y distance < 15 * median height). It calculates cuts as midpoints, creating a grid structure, and assigns each box to the nearest cell containing an anchor.
  * If single/no anchor: Falls back to `recursive_xy_cut`, which cuts columns/rows using hard thresholds (`2.5 * median_height` for X, `3.5 * median_height` for Y).
* **scratch/mock_test.py (`cluster_boxes` method)**:
  * Uses a simpler column-based split (left column if `x < 500`, right if `x >= 500`). Within columns, boxes are assigned to the anchor directly above them.
* **test_spatial_ocr.py (`cluster_boxes` method)**:
  * Uses a connected-components / union-find spatial clustering with axis-aligned bounding box gaps:
    * `dx = max(0, max(c.x - (b.x + b.w), b.x - (c.x + c.w)))`
    * `dy = max(0, max(c.y - (b.y + b.h), b.y - (c.y + c.h)))`
    * Merges if `dx < 10 * median_height` and `dy < 8 * median_height`.

### 1.2 Amounts Extraction (TVA, Totals, Base)
* **Total Extraction**:
  * Groups boxes into horizontal lines using a hard Y tolerance (`abs(box.y - currentLine[0].y) < medianHeight * 0.4`).
  * Scans for keywords (`TOTAL`, `SUMA`, `ACHITAT`).
  * If found, finds the nearest box containing a decimal number matching `\b([0-9]+[.][0-9]{2})\b` (skipping typical VAT percentages).
  * Fallbacks: Class regex search and taking the largest decimal amount.
* **VAT & Base Extraction**:
  * POS receipts default to `0%` VAT, with `Base = Total`.
  * Regular receipts:
    1. Extract percentage rates (e.g. `19%`). Default to Romanian rates `[21.0, 19.0, 11.0, 9.0, 5.0]` if none are found.
    2. Extract all unique decimal amounts matching `(?<!%)\b([0-9]+[.,][0-9]{2})\b(?!\\s*%)`.
    3. Mathematical matching:
       * **Method A**: If Total is known, test if any decimal value matches `Total * rate / (100 + rate)` (tolerance 0.05).
       * **Method B**: Try to find a pair of decimals where `Vat = Base * rate / 100` (tolerance 0.05).
    4. Proximity Fallback: If mathematical matching fails but "TVA" is found, look for nearby decimals.
* **Validation Agent (`AccountingValidationAgent`)**:
  * Performs VAT rate corrections for Romanian tax laws (e.g., 19% -> 21% for 2026, 5% -> 11%).
  * Compares `Total == Base + VAT` (within 0.02 tolerance). Recalculates base if the difference is small; flags warning and requests verification if the difference is large.

---

## 2. Vulnerabilities and Limitations

### 2.1 Rotation Failure in 2D Clustering
* All current clustering methods (Recursive Bisection, Row/Column cuts, Grid Partitioning, Union-Find) assume that the document coordinate axes are perfectly aligned with the coordinate system of the image.
* When an image is rotated (even by a small angle like 10-15 degrees, or completely by 90/180/270 degrees):
  * **Line projections overlap**: The projection of lines/columns onto the X or Y axis no longer shows clean gaps. This breaks the Recursive Bisection and Grid-cut splits, causing text boxes from different receipts to be clustered together.
  * **Incorrect line grouping**: In `FinancialAmountsAgent`, line grouping relies on `abs(box.y - currentLine[0].y) < yTolerance`. With rotation, the left end and right end of a single text line will have a Y-coordinate difference larger than the tolerance, causing words from the same line to be split into separate lines.

### 2.2 Strict Regex Constraints on Decimal Numbers
* The regex used for gathering amounts is extremely strict:
  * `(?<!%)\b([0-9]+[.,][0-9]{2})\b(?!\\s*%)`
* **Vulnerability**: It strictly requires exactly two decimal digits.
  * If the OCR engine reads an amount as an integer (e.g. `100` instead of `100.00`) or with a single decimal place (e.g. `19.0` instead of `19.00`), the number is **completely ignored** by the amount extractor.
  * This breaks the mathematical matching, as the candidate values will not be present in `allVals`.
  * Thousand separators (e.g. `1,200.50` or `1.200,50` or `1 200.50`) are also either split into multiple numbers or ignored.

### 2.3 Strict Tolerances for Mathematical Matching
* The mathematical checks use a strict absolute tolerance of `0.05`.
* Under OCR noise, digit substitutions (e.g., `8` read as `3` or `0` read as `9`), or simple rounding variations by cash registers, the absolute difference might exceed `0.05`.
* If a single value fails this matching, the server falls back to arbitrary heuristic extraction, which is prone to wrong totals and VAT mismatches.

---

## 3. Optimization Proposals

### 3.1 Deskewing Coordinates using OCRRectItem (Rotation Optimization)
The Vision framework provides normalized polygon coordinates in `OCRRectItem` (topLeft, topRight, bottomLeft, bottomRight). We can leverage these corners to deskew all coordinates before clustering:

1. **Calculate the Skew Angle ($\theta$)**:
   * For each box, compute the slope of its top edge:
     $$\theta_i = \text{atan2}(\text{topRight\_y} - \text{topLeft\_y}, \text{topRight\_x} - \text{topLeft\_x})$$
   * Take the median of all $\theta_i$ to find the global rotation angle $\theta_{global}$ of the document.
2. **Apply Rotation Transformation**:
   * For each box, transform its center coordinate $(x, y)$ to the deskewed coordinate system $(x', y')$:
     $$x' = x \cos(-\theta_{global}) - y \sin(-\theta_{global})$$
     $$y' = x \sin(-\theta_{global}) + y \cos(-\theta_{global})$$
   * Perform all line groupings, column alignments, CUI anchor selections, and clustering splits on $(x', y')$.

### 3.2 Robust Number Parser
Replace the strict 2-decimal regex with a robust parser that matches integers and decimals, and normalizes them:
* **Proposed Regex**:
  `\b[0-9]{1,3}(?:[.,\s]?[0-9]{3})*(?:[.,][0-9]{1,2})?\b`
* **Parsing Logic**:
  1. Extract matching string.
  2. Strip internal spaces and thousand separators.
  3. Replace the decimal separator with a dot.
  4. Parse as Double.
  5. Exclude candidate numbers that are likely years (e.g. 2024, 2025, 2026) or telephone numbers.

### 3.3 Score-Based Mathematical Matcher (Constraint Solver)
Instead of matching combinations using strict nested loops and a rigid 0.05 tolerance, implement a constraint-based scoring system:
1. Define a list of candidate values: all extracted numbers, plus virtual numbers computed from them (e.g., $val \times (1 + \frac{rate}{100})$ or $val \times \frac{rate}{100}$).
2. For each combination of $(Total, Base, VAT, Rate)$, calculate a cost score:
   $$\text{Cost} = |Total - (Base + VAT)| + \text{KeywordPenalty} + \text{LayoutPenalty}$$
   * **Keyword Penalty**: Low if $Total$ is near a "TOTAL" keyword, $VAT$ is near "TVA", and $Base$ is near "NET" or "BAZA".
   * **Layout Penalty**: Low if the values align vertically or horizontally in the deskewed space.
3. Select the combination with the lowest Cost score. This is highly robust to missing values or minor OCR noise.

### 3.4 Unified 2D Clustering Framework (2D Grid Alignment)
In corporate receipts, documents are often laid out side-by-side or in multi-page grids. A robust 2D clustering framework should combine:
1. **Deskewing**: Maps all boxes to horizontal/vertical alignment.
2. **Anchor Identification**: Find all unique CUI/CIF boxes.
3. **Voronoi-based / Distance Partitioning**:
   * If multiple anchors exist, define the boundary between them by finding the mid-point orthogonal to the line connecting adjacent anchors in the deskewed coordinate space.
   * Assign remaining text boxes to their nearest anchor partition based on deskewed coordinates.
