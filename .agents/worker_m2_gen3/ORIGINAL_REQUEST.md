## 2026-07-07T21:31:00Z

You are worker_m2_gen3. Your working directory is e:\OCR Iphone\.agents\worker_m2_gen3.
Your task is to implement the fixes in `OcrServer/VaporServer.swift` and update the test scripts in the workspace.

Detailed Fix Requirements:
1. **Rotation-Invariant 2D Receipt Clustering**:
   - Compute the median skew angle theta using corner coordinates of `OCRRectItem` (Vision output) for each text box:
     `theta_i = atan2(topRight.y - topLeft.y, topRight.x - topLeft.x)`
   - Take the median skew angle of all boxes to find the document's global rotation angle.
   - Translate all box center coordinates (x, y) to deskewed coordinates (x', y') using:
     `x' = x * cos(-theta) - y * sin(-theta)`
     `y' = x * sin(-theta) + y * cos(-theta)`
   - Replace the bisection split clustering in `VaporServer.swift` with a Graph-Based (Single-Linkage) clustering algorithm using local Euclidean corner-to-corner distances. Connect two boxes with an edge if their minimum corner distance is less than `4.0 * medianHeight`. Find connected components using BFS/DFS.
   - If a component has multiple CUI/CIF anchors, partition it using Dijkstra's shortest path algorithm based on geodesic (graph path) distance.
   - Ensure the new clustering logic is also integrated or synchronized in the python testing scripts (`test_logic.py`, `test_spatial_ocr.py`, `scratch/mock_test.py`) so they stay aligned.

2. **CUI Candidate Extraction Fixes**:
   - In `CuiExtractorAgent`:
     - Ignore 10-digit numbers starting with "07", "02", or "03" (phone numbers).
     - Refine "RO" matching so it doesn't match words containing "RO" (like "RON", "ROMPETROL"). Only match "RO" if it's followed by digits or is a standalone prefix.
     - Support CUI anchors grouped in single OCR blocks (e.g. "CIF: RO 1234567").
     - Prioritize mathematically valid CUIs near keywords before falling back to all numbers in the document.

3. **Amounts Extraction Fixes**:
   - Group boxes into horizontal lines using deskewed y' coordinates.
   - Support parsing numbers >= 1,000 using comma/dot thousands separators (e.g. "1,234.56" -> 1234.56).
   - Relax regex constraint to match integers and single decimals (e.g. "100" and "19.0" instead of strictly requiring two decimals).
   - Remove the keyword "REST" from fallback pattern to avoid matching returned change.

4. **VAT Recalculation Date Bug Fix**:
   - In `AccountingValidationAgent.correctVatRates`, check the document date *before* performing any VAT rate recalculations. If the date is 2024 or earlier, do not perform the 19% -> 21% or 5% -> 11% auto-corrections.

5. **Compilation and Verification**:
   - Compile the server and ensure it builds with zero errors.
   - Run the Python regression and mock tests: `test_logic.py`, `test_spatial_ocr.py`, `scratch/mock_test.py` and ensure they pass completely.
