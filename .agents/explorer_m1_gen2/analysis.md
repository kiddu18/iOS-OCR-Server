# Detailed Analysis and Strategy Design Report

## 1. Executive Summary
This document outlines the findings, detailed design, and code proposals for improving receipt clustering, handling OCR inaccuracies in CUI (Tax ID) extraction, correctly extracting financial amounts (Total, VAT, Base), and setting up programmatic mock tests.

The proposed improvements build on the existing spatial OCR processing architecture in `OcrServer/VaporServer.swift` and `test_logic.py`, making it resilient to OCR inaccuracies, missing coordinates, and multi-receipt layouts.

---

## 2. Findings on Current Implementations
After analyzing `OcrServer/VaporServer.swift`, `test_logic.py`, and `test_spatial_ocr.py`, the following limitations were identified:

1. **Strict Anchor Dependency on Valid CUIs:**
   - The current clustering logic in `test_logic.py` identifies anchors via `is_seller_cui_box()`, which requires extracting a *mathematically valid CUI*.
   - If a CUI has OCR noise (e.g. `'R077454P'` instead of `'RO7745470'`), the CUI validation fails, the box is not recognized as an anchor, and the receipt cluster is completely missed or merged incorrectly.
   
2. **Lack of Fuzzy Match for Anchor Keywords:**
   - In `VaporServer.swift`, anchor detection looks for exact keyword matches (e.g. `"COD FISCAL"`, `"CODFISCAL"`, `"CIF"`).
   - If OCR produces minor spelling errors (e.g. `"CODF1SCAL"` or `"C1F"`), anchor detection fails.

3. **Inability to Retrieve Inaccurate CUIs:**
   - When a CUI is read with typos (e.g. digits misread as characters), the existing `CuiExtractorAgent` fails verification and falls back to regex. The regex only searches for numeric sequences, meaning the noisy alphanumeric string is lost.

4. **Incomplete Base/Total Amount Sync:**
   - In `FinancialAmountsAgent` (`VaporServer.swift`), if the total amount is not found but VAT breakdowns are extracted, the `baseAmount` is not computed properly because it relies on a non-nil `totalAmount`.

---

## 3. Detailed Design

### 3.1. Robust Receipt Clustering Strategy (Requirement 1)
Instead of matching valid CUI numbers, we use **seller keyword anchors** with fuzzy matching and spatial deduction.
- **Anchor Keywords:** `"CIF"`, `"CUI"`, `"CODFISCAL"`, `"FISCAL"`, `"COD FISCAL"`.
- **Fuzzy Token Matching:** Split box text into alphanumeric tokens and check if any token has a Levenshtein distance $\le 1$ (for 3-char keywords) or $\le 2$ (for longer keywords) to any of the anchor keywords.
- **Buyer CUI Exclusion:** Exclude anchors near buyer-identifying terms (`"CLIENT"`, `"CUMP"`, `"BENEF"`, `"CNP"`, `"C.N.P"`), using similar fuzzy token and spatial checking.
- **Deduplication:** Dedup anchors by checking absolute Euclidean distance. If two candidate anchors are within `5 * medianHeight` horizontally and `3 * medianHeight` vertically, they represent the same receipt and are merged.

### 3.2. Robust CUI Extraction with Fallback (Requirement 2)
If no mathematically valid CUI is found on the receipt:
1. **Define Candidate Boxes:** Filter boxes that contain or fuzzy match seller CUI keywords.
2. **Clean Text:** Clean candidate texts and adjacent boxes by stripping common prefixes (`"CIF"`, `"CUI"`, `"RO"`, `"COD"`, `"FISCAL"`, `"CODFISCAL"`) and retaining only alphanumeric characters.
3. **Alphanumeric Fallback:** Extract any resulting alphanumeric string of length 2–12 that contains at least one digit.
4. **Distance Proximity Sorting:** Rank fallback candidates by spatial distance to the CUI keyword box. The closest candidate is selected as `result.cui` with `cuiRequiresVerification = true`.

### 3.3. Financial Amounts Extraction Strategy (Requirement 3)
- **Total Amount:**
  - Retrieve the value via line-based spatial matching to `"TOTAL"`, `"SUMA"`, `"ACHITAT"` (excluding lines containing `"TVA"` / `"TAXA"` / `"TAXE"`).
  - Apply regex fallback on the full text.
  - Fall back to the maximum numeric value that does not match common VAT rates (24, 21, 19, 11, 9, 5).
- **VAT and Base Amount:**
  - For POS receipts, set VAT = 0, Base = Total, and VAT Percent = `"-"`.
  - For invoices/standard receipts, parse percentage signs (`%`). Reconcile using:
    - $\text{VAT} \approx \text{Base} \times \text{Rate}$
    - $\text{Total} \approx \text{Base} \times (1 + \text{Rate})$
  - If the total amount is missing but VAT rate breakdowns are successfully retrieved, reconstruct the total as:
    $$\text{Total Amount} = \sum \text{Base Amount} + \sum \text{VAT Amount}$$
- **Split Logic:**
  - If a receipt has multiple VAT rates, split the single `AccountingResult` into separate items (one per VAT rate). The sub-total is computed as $\text{Base} + \text{VAT}$.

---

## 4. Code Proposals

### 4.1. Proposed Updates for `VaporServer.swift`

#### Modification A: Helper Methods on `String` & `isBuyerBox`/`isSellerAnchor` inside `clusterBoxes`
Modify `clusterBoxes` in `AccountingOrchestrator` to implement fuzzy keyword anchors:

```swift
    // Separa cutiile de text in documente distincte
    func clusterBoxes(_ boxes: [OCRBoxItem]) -> [[OCRBoxItem]] {
        guard boxes.count > 1 else { return [boxes] }
        
        let sortedHeights = boxes.map { $0.h }.sorted()
        let medianHeight = CGFloat(sortedHeights[sortedHeights.count / 2])
        
        var uniqueAnchors: [OCRBoxItem] = []
        
        // Helper checking if a box represents a buyer
        func isBuyerBox(_ box: OCRBoxItem) -> Bool {
            let text = box.text.uppercased()
            let buyerKeywords = ["CLIENT", "CUMP", "BENEF", "CNP", "C.N.P"]
            
            for kw in buyerKeywords {
                if text.contains(kw) { return true }
            }
            
            let tokens = text.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }
            for token in tokens {
                for kw in buyerKeywords {
                    let tolerance = (kw.count <= 3) ? 0 : 1
                    if token.isFuzzyMatch(kw, tolerance: tolerance) {
                        return true
                    }
                }
            }
            
            for other in boxes {
                if other.x == box.x && other.y == box.y { continue }
                let otherText = other.text.uppercased()
                var hasBuyerKeyword = false
                for kw in buyerKeywords {
                    if otherText.contains(kw) {
                        hasBuyerKeyword = true
                        break
                    }
                }
                if !hasBuyerKeyword { continue }
                
                let dy = box.y - other.y
                let dx = box.x - other.x
                
                if abs(dy) < Double(medianHeight) * 1.5 && dx > 0 && dx < Double(medianHeight) * 12.0 {
                    return true
                }
                if dy > 0 && dy < Double(medianHeight) * 2.5 && abs(dx) < Double(medianHeight) * 6.0 {
                    return true
                }
            }
            return false
        }
        
        // Helper checking if a box is a seller CUI/CIF keyword anchor
        func isSellerAnchor(_ box: OCRBoxItem) -> Bool {
            let upper = box.text.uppercased()
            let noDots = upper.replacingOccurrences(of: ".", with: "")
            let noSpaces = noDots.replacingOccurrences(of: " ", with: "")
            
            if isBuyerBox(box) { return false }
            if upper.contains("%") { return false }
            if noSpaces.hasPrefix("BON") || noDots.contains("BON ") { return false }
            
            let sellerKeywords = ["CIF", "CUI", "CODFISCAL", "FISCAL", "COD FISCAL"]
            
            // Direct containment
            for kw in sellerKeywords {
                if noDots.contains(kw) || noSpaces.contains(kw.replacingOccurrences(of: " ", with: "")) {
                    return true
                }
            }
            
            // Fuzzy match on tokens
            let tokens = upper.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }
            for token in tokens {
                for kw in sellerKeywords {
                    let tolerance = (kw.count <= 3) ? 1 : 2
                    if token.isFuzzyMatch(kw, tolerance: tolerance) {
                        return true
                    }
                }
            }
            
            // Spatial check (is keyword nearby?)
            for other in boxes {
                if other.x == box.x && other.y == box.y { continue }
                let otherUpper = other.text.uppercased()
                let otherNoDots = otherUpper.replacingOccurrences(of: ".", with: "")
                let otherNoSpaces = otherNoDots.replacingOccurrences(of: " ", with: "")
                
                var otherHasSellerKeyword = false
                for kw in sellerKeywords {
                    if otherNoDots.contains(kw) || otherNoSpaces.contains(kw.replacingOccurrences(of: " ", with: "")) {
                        otherHasSellerKeyword = true
                        break
                    }
                }
                
                if !otherHasSellerKeyword {
                    let otherTokens = otherUpper.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }
                    for token in otherTokens {
                        for kw in sellerKeywords {
                            let tolerance = (kw.count <= 3) ? 1 : 2
                            if token.isFuzzyMatch(kw, tolerance: tolerance) {
                                otherHasSellerKeyword = true
                                break
                            }
                        }
                        if otherHasSellerKeyword { break }
                    }
                }
                
                if otherHasSellerKeyword {
                    let dy = abs(box.y - other.y)
                    let dx = abs(box.x - other.x)
                    if dy < Double(medianHeight) * 2.0 && dx < Double(medianHeight) * 12.0 {
                        return true
                    }
                }
            }
            return false
        }
        
        for box in boxes {
            if isSellerAnchor(box) {
                // Deduplicate anchors
                var isDuplicate = false
                for existing in uniqueAnchors {
                    let dx = abs(existing.x - box.x)
                    let dy = abs(existing.y - box.y)
                    if dx < Double(medianHeight) * 5.0 && dy < Double(medianHeight) * 3.0 {
                        isDuplicate = true
                        break
                    }
                }
                
                if !isDuplicate {
                    uniqueAnchors.append(box)
                }
            }
        }
        
        // ... [Rest of clusterBoxes grid clustering logic continues unmodified] ...
```

#### Modification B: `CuiExtractorAgent` Fallback Logic
Replace the `process` function in `CuiExtractorAgent` to add alphanumeric 2-12 fallback:

```swift
class CuiExtractorAgent: AccountingAgent {
    func process(textBlocks: [String], boxes: [OCRBoxItem], result: inout AccountingResult) async {
        // Helper checking if a box represents a buyer
        func isBuyerBox(_ box: OCRBoxItem, medianHeight: CGFloat) -> Bool {
            let text = box.text.uppercased()
            let buyerKeywords = ["CLIENT", "CUMP", "BENEF", "CNP", "C.N.P"]
            
            for kw in buyerKeywords {
                if text.contains(kw) { return true }
            }
            
            let tokens = text.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }
            for token in tokens {
                for kw in buyerKeywords {
                    let tolerance = (kw.count <= 3) ? 0 : 1
                    if token.isFuzzyMatch(kw, tolerance: tolerance) {
                        return true
                    }
                }
            }
            
            for other in boxes {
                if other.x == box.x && other.y == box.y { continue }
                let otherText = other.text.uppercased()
                var hasBuyerKeyword = false
                for kw in buyerKeywords {
                    if otherText.contains(kw) {
                        hasBuyerKeyword = true
                        break
                    }
                }
                if !hasBuyerKeyword { continue }
                
                let dy = box.y - other.y
                let dx = box.x - other.x
                
                if abs(dy) < Double(medianHeight) * 1.5 && dx > 0 && dx < Double(medianHeight) * 12.0 {
                    return true
                }
                if dy > 0 && dy < Double(medianHeight) * 2.5 && abs(dx) < Double(medianHeight) * 6.0 {
                    return true
                }
            }
            return false
        }

        let sortedHeights = boxes.map { $0.h }.sorted()
        let medianHeight = sortedHeights.isEmpty ? 15.0 : CGFloat(sortedHeights[sortedHeights.count / 2])

        // 1. Cautare Spatiala Inteligenta 2D (Fuzzy)
        let cuiKeywords = ["CIF", "CUI", "CODFISCAL", "RO"]
        var candidateBoxes: [OCRBoxItem] = []
        
        for box in boxes {
            let cleanText = box.text.uppercased().replacingOccurrences(of: ".", with: "").replacingOccurrences(of: " ", with: "")
            
            if isBuyerBox(box, medianHeight: medianHeight) {
                continue
            }
            
            if cuiKeywords.contains(where: { cleanText.contains($0) || (cleanText.count <= $0.count + 2 && cleanText.isFuzzyMatch($0, tolerance: 1)) }) {
                candidateBoxes.append(box)
            }
        }
        
        // Verificam textul din interiorul cutiilor gasite (poate CUI-ul e in aceeasi cutie: "CIF RO123456")
        for box in candidateBoxes {
            if box.text.contains("%") { continue }
            let text = box.text.uppercased().replacingOccurrences(of: " ", with: "").replacingOccurrences(of: ".", with: "")
            let numbersOnly = text.filter { $0.isNumber }
            if isValidCUI(cui: numbersOnly) {
                result.cui = numbersOnly
                result.cuiRequiresVerification = false
                await verifyWithANAF(cui: numbersOnly, result: &result)
                result.cui = numbersOnly 
                return
            }
        }
        
        // Cautam cutii la dreapta sau putin mai jos
        for keywordBox in candidateBoxes {
            let nearbyBoxes = boxes.filter {
                ($0.x != keywordBox.x || $0.y != keywordBox.y) && // exclude self
                $0.y >= keywordBox.y - keywordBox.h * 0.8 && $0.y <= keywordBox.y + keywordBox.h * 2.0 &&
                $0.x >= keywordBox.x - keywordBox.w * 0.5
            }.sorted { $0.x < $1.x }
            
            for nb in nearbyBoxes {
                if nb.text.contains("%") { continue }
                let text = nb.text.replacingOccurrences(of: " ", with: "").replacingOccurrences(of: ".", with: "")
                let numbersOnly = text.filter { $0.isNumber }
                if !numbersOnly.isEmpty && isValidCUI(cui: numbersOnly) {
                    result.cui = numbersOnly
                    result.cuiRequiresVerification = false
                    await verifyWithANAF(cui: numbersOnly, result: &result)
                    result.cui = numbersOnly
                    return
                }
            }
        }
        
        // 2. Fallback la Regex-ul clasic
        let fullText = textBlocks.joined(separator: " ").uppercased()
        let fallbackPattern = "\\b([0-9]{2,10})\\b"
        if let regex = try? NSRegularExpression(pattern: fallbackPattern, options: []) {
            let nsString = fullText as NSString
            let results = regex.matches(in: fullText, options: [], range: NSRange(location: 0, length: nsString.length))
            
            for match in results {
                if match.numberOfRanges > 1 {
                    let cuiCandidate = nsString.substring(with: match.range(at: 1))
                    if isValidCUI(cui: cuiCandidate) {
                        result.cui = cuiCandidate
                        result.cuiRequiresVerification = false
                        await verifyWithANAF(cui: cuiCandidate, result: &result)
                        result.cui = cuiCandidate
                        return
                    }
                }
            }
        }
        
        // 3. Fallback: extractia de secvente alfanumerice din vecinatate (lungime 2-12)
        print("[CUI Extraction] No mathematically valid CUI found. Attempting fallback for inaccurate OCR...")
        
        func cleanCandidate(_ rawText: String) -> String? {
            var s = rawText.uppercased().filter { $0.isLetter || $0.isNumber }
            let prefixes = ["CIF", "CUI", "RO", "COD", "FISCAL", "CODFISCAL"]
            var changed = true
            while changed {
                changed = false
                for prefix in prefixes {
                    if s.hasPrefix(prefix) {
                        s = String(s.dropFirst(prefix.count))
                        changed = true
                    }
                }
            }
            if s.count >= 2 && s.count <= 12 && s.contains(where: { $0.isNumber }) {
                return s
            }
            return nil
        }
        
        var fallbackCandidates: [(text: String, distance: Double)] = []
        
        for box in candidateBoxes {
            if let cleaned = cleanCandidate(box.text) {
                fallbackCandidates.append((text: cleaned, distance: 0.0))
            }
        }
        
        for keywordBox in candidateBoxes {
            let nearbyBoxes = boxes.filter {
                ($0.x != keywordBox.x || $0.y != keywordBox.y) &&
                $0.y >= keywordBox.y - keywordBox.h * 1.5 && $0.y <= keywordBox.y + keywordBox.h * 3.0 &&
                $0.x >= keywordBox.x - keywordBox.w * 0.5
            }
            for nb in nearbyBoxes {
                if nb.text.contains("%") { continue }
                if let cleaned = cleanCandidate(nb.text) {
                    let dx = nb.x - keywordBox.x
                    let dy = nb.y - keywordBox.y
                    let dist = sqrt(dx*dx + dy*dy)
                    fallbackCandidates.append((text: cleaned, distance: dist))
                }
            }
        }
        
        if !fallbackCandidates.isEmpty {
            let sortedCandidates = fallbackCandidates.sorted { $0.distance < $1.distance }
            let bestCandidate = sortedCandidates.first!.text
            result.cui = bestCandidate
            result.cuiRequiresVerification = true
            print("[CUI Extraction] Fallback matched candidate: '\(bestCandidate)'")
            return
        }
        
        result.cuiRequiresVerification = true
    }
}
```

#### Modification C: Robust Total/Base Sync inside `FinancialAmountsAgent`
Make sure `baseAmount` is calculated from the sum of breakdowns if `totalAmount` was missing:

```swift
            if !breakdowns.isEmpty {
                result.vatBreakdowns = breakdowns
                let sumVat = breakdowns.map { $0.vatAmount }.reduce(0, +)
                result.vatAmount = (sumVat * 100).rounded() / 100
                result.vatPercentages = breakdowns.map { $0.percentage }.joined(separator: ", ")
                result.vatRequiresVerification = false
                
                if result.totalAmount == nil {
                    let sumBase = breakdowns.map { $0.baseAmount }.reduce(0, +)
                    result.totalAmount = ((sumBase + result.vatAmount!) * 100).rounded() / 100
                    result.baseAmount = sumBase
                } else {
                    result.baseAmount = ((result.totalAmount! - result.vatAmount!) * 100).rounded() / 100
                }
            } else {
                result.vatAmount = 0
                result.vatPercentages = "-"
                result.baseAmount = result.totalAmount
            }
```

---

## 5. Mock Test Verification Script
The proposed Python mock test script simulating the 6 receipts in a 2x3 layout with OCR typo injection is saved in the agent directory at:
`e:\OCR Iphone\.agents\explorer_m1_gen2\proposed_mock_test.py`

### Layout Coordinates & Logic:
- Canvas dimensions: $1000 \times 1500$.
- Grid placement:
  - Columns: $X \in [50, 450]$ and $X \in [550, 950]$.
  - Rows: $Y \in [50, 450]$, $Y \in [550, 950]$, and $Y \in [1050, 1450]$.
- Injecting OCR typos in Receipt 1 CUI (`"R0 12345P"` instead of `"RO 123453"`) and Receipt 5 CUI (`"R0987654A"` instead of `"RO9876544"`).
- Verification checks that:
  - Number of clustered receipts is exactly 6.
  - All CUIs are extracted, with fallback CUI extracted correctly for Receipt 1 (`"12345P"`) and Receipt 5 (`"987654A"`).
  - Receipt 4 is split into 2 accounting rows (one for 19%, one for 9%).
  - Financial values reconcile.
