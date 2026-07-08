# OCR Analysis: 2D Clustering, Checksum, and Financial Extraction

## Executive Summary
The current receipt processing pipeline in `OcrServer/VaporServer.swift` suffers from structural vulnerabilities when receipts are rotated or placed in a 2x3 grid due to its reliance on axis-aligned global bisections and line grouping. We propose a graph-based local connectivity clustering strategy that is completely rotation-invariant, alongside a resilient CUI error-correction mechanism and robust line-free financial amounts extraction.

---

## 1. 2D Receipt Clustering Failure Analysis

The server uses a **recursive bisection clustering** algorithm (lines 1625–1768 in `VaporServer.swift`) to separate OCR bounding boxes into distinct receipt groups. This algorithm fails under two primary conditions:

### A. Rotated Receipts (Angle skew)
*   **AABB Projection Overlap:** The current code projects bounding boxes onto the $X$ and $Y$ axes using axis-aligned coordinates (`centers = group.map { $0.x + $0.w / 2.0 }`). When receipts are tilted or rotated (e.g., $15^\circ$ to $45^\circ$ or $90^\circ$ landscape mode), their axis-aligned bounding boxes (AABBs) expand and overlap significantly.
*   **Gap Disappearance:** Because of the projection overlap, the sorted coordinate arrays no longer contain clear spatial gaps. Consequently, `findBestGapSplit` yields either zero gaps or incorrect split points.
*   **Straight-Line Slice Failures:** The split logic divides boxes using a straight vertical or horizontal line (`x < sp` or `y < sp`). If the receipts are rotated, a straight vertical or horizontal line cannot separate them. It will inevitably slice diagonally through multiple receipts, scrambling their text boxes into incorrect clusters.

### B. 2x3 Grid Layouts (Fragile Bisections)
*   **Alignment Assumption:** Recursive bisection assumes that receipts are arranged in perfect rows and columns, with straight horizontal and vertical corridors extending across the entire page.
*   **Misalignment and Skew:** If one receipt is shifted slightly higher or lower than its neighbor in the same row, or if the spacing between rows/columns is small, there is no single straight line that can separate columns or rows without cutting through the shifted receipt.
*   **Cascading Split Errors:** A single wrong split at the root level (depth 0) propagates through all subsequent recursive calls, permanently separating headers, totals, or CUIs from their parent receipts.

---

## 2. Proposed Robust, Rotation-Invariant Clustering Strategy

To resolve the rotation and grid failures, we propose replacing global coordinate projections with a **Local Graph-Based (Single-Linkage) Clustering** combined with **Geodesic Anchor Propagation**.

### Why it is Rotation-Invariant:
Instead of using axis-aligned coordinate projections, this strategy operates on local spatial relationships between adjacent text boxes. The Euclidean distance between points or oriented polygons is invariant under 2D rotation. Therefore, the graph structure remains identical regardless of receipt tilt or orientation.

### Step-by-Step Algorithm:

```
+------------------------------------+
|  1. Extract Oriented Center/Size   |
|   (Using iOS Vision OCRRectItem)   |
+-----------------+------------------+
                  |
                  v
+------------------------------------+
|   2. Build Local Proximity Graph   |
|    (Connect boxes if min corner-   |
|     to-corner distance < 4.0 * h)  |
+-----------------+------------------+
                  |
                  v
+------------------------------------+
|   3. Find Connected Components     |
|   (Extracts raw receipt clusters)  |
+-----------------+------------------+
                  |
                  v
+------------------------------------+
|  4. Resolve Multi-Anchor Conflicts |
|   (Dijkstra shortest path split)   |
+------------------------------------+
```

1.  **Oriented Center and Scale Extraction:**
    *   For each `OCRBoxItem`, retrieve its oriented corners (`rect: OCRRectItem`). Calculate the oriented center $C_i = (x_c, y_c)$ as the average of the 4 corner coordinates.
    *   Define the local scale $h_i$ of the box as the average height of the oriented quad (distance between top and bottom corners).
2.  **Local Proximity Graph Construction:**
    *   For every pair of boxes $(i, j)$, calculate the minimum Euclidean distance between their 4 corners (representing the shortest physical distance between the text blocks).
    *   Connect box $i$ and box $j$ with an edge if their minimum corner distance is less than a local threshold $\theta$:
        $$\theta = k \times \text{medianHeight} \quad (\text{where } k \approx 3.0 \text{ to } 4.0)$$
3.  **Connected Components Extraction:**
    *   Find the connected components (independent subgraphs). Because the spacing between receipts is much larger than the spacing between words/lines on the same receipt, this local connectivity naturally groupings text into individual receipts.
4.  **Multi-Anchor Conflict Resolution (Geodesic Dijkstra Split):**
    *   If a connected component contains multiple CUI anchors ($A_1, A_2, \dots, A_m$), it means two receipts were placed so close that their text blocks touched.
    *   Run Dijkstra's algorithm to assign each box $B$ in the component to the CUI anchor that is closest in terms of graph path (geodesic) distance.
    *   This is highly robust: since text flows within a receipt are densely connected, the path distance to the correct anchor (within the same receipt) will be much shorter than a path that crosses the sparse bridge between two receipts, even if the straight-line Euclidean distance to the wrong anchor is short.
5.  **Unanchored Component Management:**
    *   Components with zero CUI anchors are kept as separate clusters, ensuring receipts with misread CUIs are still processed.

---

## 3. Modulo-11 CUI Checksum Verification Analysis

### A. Code Analysis of `isValidCUI`
The implementation of `isValidCUI` in `VaporServer.swift` (lines 1794–1820) is mathematically correct but has operational issues.

```swift
let calcControlDigit = (sum * 10) % 11
let finalControlDigit = calcControlDigit == 10 ? 0 : calcControlDigit
```

*   **Mathematical Equivalence:** The standard Romanian CUI checksum formula is:
    $$\text{controlDigit} = (11 - (\text{sum} \pmod{11})) \pmod{11}$$
    The code uses `(sum * 10) % 11`. Since $10 \equiv -1 \pmod{11}$, we have:
    $$(\text{sum} \times 10) \pmod{11} \equiv -\text{sum} \pmod{11}$$
    Also:
    $$(11 - (\text{sum} \pmod{11})) \pmod{11} \equiv -\text{sum} \pmod{11}$$
    Thus, `(sum * 10) % 11` is mathematically identical to the standard formula for all integers, making the checksum logic correct.

### B. Identified Checksum & Extraction Issues
1.  **Vulnerability to OCR Noise:**
    *   OCR engines frequently misread digits as letters (e.g. `'8'` $\rightarrow$ `'B'`, `'0'` $\rightarrow$ `'O'`, `'1'` $\rightarrow$ `'I'` or `'l'`).
    *   Because `isValidCUI` requires a strict mathematical match, a single character error will fail validation, causing the CUI extractor to discard the candidate entirely.
2.  **Prefix and Non-Digit Interference:**
    *   `CuiExtractorAgent.process` cleans characters by extracting only numbers:
        `let numbersOnly = String(text.filter { $0.isNumber })`
    *   If a CUI has noise (e.g. `CUI: RO 671927B`), the `numbersOnly` value becomes `671927` (missing the last digit). This fails validation because it has the wrong length and checksum.
3.  **Lack of Error-Correction Fallback:**
    *   The current implementation lacks a fuzzy number correction step (replacing `'B'` with `'8'`, `'O'` with `'0'`, etc.) before validation, resulting in a low extraction rate on noisy receipts.

---

## 4. Total/VAT Extraction Issues Analysis

### A. Line Grouping Failure Under Rotation
*   **Vertical Tolerance:** `yTolerance = medianHeight * 0.4` is used to group boxes into horizontal lines.
*   **Rotational Skew:** If a receipt is tilted even by $5^\circ$, the vertical offset between the left and right ends of a 300-pixel-wide line is $300 \times \tan(5^\circ) \approx 26$ pixels. If the median height is 15 pixels, `yTolerance` is 6 pixels.
*   **Broken Lines:** The boxes on the same line will be split into multiple separate lines. Consequently, the horizontal regex patterns (`totalPattern`, `vatPattern`) fail because the label and the value are no longer on the same line.

### B. Euclidean Distance Proximity Sorting for TOTAL
*   **Spatial Mismatch:** `FinancialAmountsAgent` sorts all boxes by Euclidean distance from the `"TOTAL"` keyword to find the nearest decimal value.
*   **Horizontal Layout Disconnect:** In standard receipt layouts, the "TOTAL" label is on the left, and the amount is on the far right. The closest decimal number might be an item price on the line directly above or below, rather than the total amount on the far right. Under rotation, this spatial disconnect is amplified, leading to incorrect total extraction.

### C. VAT Math-Matching and Split Logic Vulnerabilities
*   **Rate Capture Conflict:** If the VAT rate (e.g., `19%`) matches the VAT amount (e.g., `19.00`), the parser might incorrectly filter out the amount as the rate itself.
*   **Zero-VAT Fallback:** If the math matching fails (e.g. because the total was extracted incorrectly or OCR missed the base amount), the code defaults to `vatAmount = 0` and `vatPercentages = "-"`. This is incorrect for VAT-registered invoices and leads to compliance warnings.

---

## 5. Recommended Code Refactoring Sketch

To resolve these issues, we recommend the following changes to `VaporServer.swift`:

### A. Graph-Based Clustering Implementation
```swift
func clusterBoxesGraphBased(_ boxes: [OCRBoxItem]) -> [[OCRBoxItem]] {
    guard boxes.count > 1 else { return [boxes] }
    let sortedHeights = boxes.map { $0.h }.sorted()
    let medianHeight = sortedHeights[sortedHeights.count / 2]
    
    var adjList: [Int: [Int]] = [:]
    
    // Build local proximity edges using Euclidean corner-to-corner distance
    for i in 0..<boxes.count {
        for j in i+1..<boxes.count {
            let dist = calculateMinCornerDistance(boxes[i], boxes[j])
            if dist < medianHeight * 4.0 {
                adjList[i, default: []].append(j)
                adjList[j, default: []].append(i)
            }
        }
    }
    
    // Extract connected components (BFS/DFS)
    var visited = Set<Int>()
    var rawComponents: [[Int]] = []
    for i in 0..<boxes.count {
        if visited.contains(i) { continue }
        var component: [Int] = []
        var queue = [i]
        visited.insert(i)
        while !queue.isEmpty {
            let curr = queue.removeFirst()
            component.append(curr)
            for neighbor in adjList[curr] ?? [] {
                if !visited.contains(neighbor) {
                    visited.insert(neighbor)
                    queue.append(neighbor)
                }
            }
        }
        rawComponents.append(component)
    }
    
    // Resolve components containing multiple CUI anchors using Dijkstra/Geodesic distance
    ...
}
```

### B. CUI Error-Correction and Fallback
```swift
func cleanAndCorrectCUI(_ rawText: String) -> String? {
    // Perform character translation to fix common OCR noise
    var clean = rawText.uppercased()
        .replacingOccurrences(of: "O", with: "0")
        .replacingOccurrences(of: "I", with: "1")
        .replacingOccurrences(of: "L", with: "1")
        .replacingOccurrences(of: "S", with: "5")
        .replacingOccurrences(of: "B", with: "8")
        .replacingOccurrences(of: "Z", with: "2")
    
    let numbersOnly = String(clean.filter { $0.isNumber })
    if isValidCUI(cui: numbersOnly) {
        return numbersOnly
    }
    return nil
}
```
