# Handoff Report - explorer_m1_gen3_1

## 1. Observation
I investigated the Vapor server codebase at `e:\OCR Iphone\OcrServer\VaporServer.swift`. Specifically:
*   **Recursive Bisection Clustering:** Lines 1639-1652:
    ```swift
    if axis == "x" {
        centers = group.map { $0.x + $0.w / 2.0 }.sorted()
        anchorPositions = anchorsInGroup.map { $0.x + $0.w / 2.0 }
    } else {
        centers = group.map { $0.y + $0.h / 2.0 }.sorted()
        anchorPositions = anchorsInGroup.map { $0.y + $0.h / 2.0 }
    }
    ```
    And lines 1731-1738:
    ```swift
    if gapX >= gapY, let sp = finalSplitX {
        left = group.filter { $0.x + $0.w / 2.0 < sp }
        right = group.filter { $0.x + $0.w / 2.0 >= sp }
    } else if let sp = finalSplitY {
        left = group.filter { $0.y + $0.h / 2.0 < sp }
        right = group.filter { $0.y + $0.h / 2.0 >= sp }
    }
    ```
*   **Modulo-11 Checksum calculation:** Lines 1816-1819:
    ```swift
    let calcControlDigit = (sum * 10) % 11
    let finalControlDigit = calcControlDigit == 10 ? 0 : calcControlDigit
    return finalControlDigit == controlDigit
    ```
*   **Line Grouping & Financial Amount extraction:** Lines 832-847:
    ```swift
    var currentLine = [sortedByY[0]]
    let yTolerance = medianHeight * 0.4
    
    for box in sortedByY.dropFirst() {
        if abs(box.y - currentLine[0].y) < yTolerance {
            currentLine.append(box)
        } else {
            lines.append(currentLine)
            currentLine = [box]
        }
    }
    ```

## 2. Logic Chain
1.  **Rotated Receipts & 2x3 Grid Layout Failures:**
    *   Since `centers` are projected horizontally or vertically using axis-aligned coordinates, a rotated receipt's bounding box centers overlap with those of neighboring receipts.
    *   This causes the bisection split point `sp` (which is a straight vertical or horizontal line in coordinate space) to slice through the middle of the rotated receipts, separating their header/footer elements.
    *   In a 2x3 grid, any minor vertical or horizontal misalignment between receipts prevents a single global straight line from separating them without intersecting some bounding boxes.
2.  **Modulo-11 Checksum verification:**
    *   The formula `(sum * 10) % 11` is mathematically equivalent to `(11 - (sum % 11)) % 11` for all integers, making it correct.
    *   However, if a CUI is read with OCR errors (e.g. `'8'` read as `'B'`), the character is stripped and the checksum fails validation, leaving no error-corrected fallback.
3.  **Financial extraction issues:**
    *   The line grouping algorithm relies on a rigid vertical tolerance of `medianHeight * 0.4`. Tilted or rotated text lines violate this baseline tolerance, resulting in scrambled horizontal lines and broken regex extraction.
    *   Euclidean distance proximity checks to find the total amount ignore column layout, leading to item prices above or below being misclassified as the total amount.

## 3. Caveats
*   I assumed that oriented quadrilaterals (`OCRRectItem` corners) are returned accurately by the iOS Vision framework. If iOS Vision returns incomplete quadrilaterals, the graph-based clustering will fall back to AABB center distances.
*   I did not run the server in a live test environment because this is a read-only investigation.

## 4. Conclusion
The current 2D bisection clustering is fragile to rotations and grid misalignments. We recommend replacing it with a graph-based (Single-Linkage) local clustering approach using oriented box corners and geodesic Dijkstra propagation. We also suggest introducing CUI OCR error correction and line-free financial amounts matching.

## 5. Verification Method
*   Inspect the detailed analysis in `e:\OCR Iphone\.agents\explorer_m1_gen3_1\analysis.md`.
*   A test script simulating OCR outputs with grid layouts and rotations can be run to verify the accuracy of the proposed graph-based clustering.
