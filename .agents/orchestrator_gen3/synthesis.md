# Synthesis of Findings - OCR Spatial Extraction Server

## Executive Summary
This document synthesizes findings from three Explorer subagents (Grid Clustering, CUI and Amounts, Integration and Testing). The core extraction logic in `VaporServer.swift` suffers from structural bugs: axis-aligned 2D bisection clustering fails under rotation/misalignment, Modulo-11 CUI extraction suffers from high false-positive rates (phone numbers, totals), thousands separators break amounts >= 1,000, and a critical bug in the VAT validation agent silently corrupts historical data.

---

## 1. Consensus Findings & Actionable Recommendations

### A. 2D Clustering & Rotation Skew
* **Consensus**: Axis-aligned projections (recursive bisection, row/column splits, Union-Find box-distance logic) assume unrotated alignment and fail when images are tilted or placed in a 2x3 grid.
* **Proposed Solution**:
  1. **Compute Skew Angle**: Compute the median skew angle $\theta$ using the corners in `OCRRectItem` (Vision output):
     $$\theta_i = \text{atan2}(\text{topRight.y} - \text{topLeft.y}, \text{topRight.x} - \text{topLeft.x})$$
     Compute the median $\theta$ of all text boxes to find the document's global rotation skew.
  2. **Transform Coordinates**: Project all coordinates to a deskewed coordinate system $(x', y')$ before clustering or grouping into lines:
     $$x' = x \cos(-\theta) - y \sin(-\theta)$$
     $$y' = x \sin(-\theta) + y \cos(-\theta)$$
  3. **Graph-Based (Single-Linkage) Clustering**: Build a local connectivity graph using Euclidean corner-to-corner distances (which are rotation-invariant). Connect boxes within a threshold (e.g. $4.0 \times \text{medianHeight}$). Run BFS/DFS to identify raw components. If a component contains multiple CUI/CIF anchors, partition it using geodesic (graph path) distance via Dijkstra's algorithm.

### B. Modulo-11 CUI Checksum & Extraction
* **Consensus**: The checksum formula `(sum * 10) % 11` is correct. However, CUI extraction suffers from extreme false-positive rates due to eager returns, lack of phone-number guards, and loose keyword matching.
* **Proposed Solution**:
  1. **Add Phone-Number Guard**: Explicitly ignore 10-digit numbers starting with `07`, `02`, or `03` (high probability of false positive checksum matches).
  2. **Refine Keyword Guard**: Ensure `"RO"` keyword matching does not match common substrings like `"RON"`, `"ROMPETROL"`, etc. Only match candidate numbers if they are spatially close to CUI labels.
  3. **Fix Standalone "CIF" Anchor Detection**: Expand anchor detection to match boxes containing `"CIF:"`, `"CUI:"`, `"COD FISCAL"`, or starting with `"CIF"`, even if grouped in a single OCR block.
  4. **Strict CUI Priority**: Prioritize mathematically valid CUIs close to keywords before falling back to all numbers in the document.

### C. Financial Amounts Extraction (Total, VAT, Base)
* **Consensus**: The line grouping algorithm and amounts parser are fragile to rotation and strict regex patterns.
* **Proposed Solution**:
  1. **Line Grouping**: Group boxes into lines using deskewed coordinates $y'$ instead of raw coordinates.
  2. **Support Thousands Separators**: Update amount matching regex to support numbers with comma/dot thousands separators (e.g., `1,234.56` or `1.234,56`), normalising them to standard doubles.
  3. **Remove "REST" Keyword**: Remove `"REST"` from the fallback total pattern to avoid matching returned change.
  4. **Support Integers/Single Decimals**: Support parsing integers and single-decimal numbers to ensure math verification does not fail on formatted values like `100` or `19.0`.

### D. Critical Bug: Historical VAT Validation Corruption
* **Consensus**: In `AccountingValidationAgent`, 19% and 5% VAT rates are automatically recalculated to 21% and 11% (2026 rates). If the document date is pre-2025 (e.g. 2024 or earlier), the code removes the warning but fails to revert the recalculated base and VAT amounts, permanently corrupting historical data.
* **Proposed Solution**:
  * Check the document date **before** performing any VAT rate recalculations. If the date is 2024 or earlier, bypass the 2026 rate auto-correction entirely.

---

## 2. Roster and Verification Path
* **Implementation Worker**: We will spawn a Worker agent to modify `OcrServer/VaporServer.swift` and update the test scripts.
* **Verification**: The worker must verify that:
  1. The server compiles.
  2. Running the regression and mock scripts (`test_logic.py`, `test_spatial_ocr.py`, `scratch/mock_test.py`) passes all tests.
