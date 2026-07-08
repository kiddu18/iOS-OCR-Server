# Romanian CUI Validation, ANAF, Totals, and VAT Extraction Logic Analysis

## Executive Summary
This analysis details the business and mathematical logic of the OCR server in `OcrServer/VaporServer.swift`. While the Romanian CUI Modulo-11 checksum validation is mathematically correct, there are significant logic flaws that lead to false positives (phone numbers and totals extracted as CUIs), architectural weaknesses in the ANAF integration, and a critical bug in the VAT validation agent that silently corrupts historical (pre-2025) receipt data.

---

## 1. Modulo-11 Romanian CUI Checksum Verification

The Modulo-11 checksum logic is implemented in `isValidCUI(cui:)` (lines 1794-1820):

```swift
func isValidCUI(cui: String) -> Bool {
    guard cui.count >= 2 && cui.count <= 10 else { return false }
    guard let _ = Int(cui) else { return false }
    
    let controlKey = "753217532"
    let controlKeyReversed = String(controlKey.reversed())
    let cuiReversed = String(cui.reversed())
    
    var sum = 0
    let cuiArray = Array(cuiReversed)
    let keyArray = Array(controlKeyReversed)
    
    guard let controlDigit = Int(String(cuiArray[0])) else { return false }
    
    for i in 1..<cuiArray.count {
        if i - 1 < keyArray.count {
            if let cNum = Int(String(cuiArray[i])), let kNum = Int(String(keyArray[i - 1])) {
                sum += cNum * kNum
            }
        }
    }
    
    let calcControlDigit = (sum * 10) % 11
    let finalControlDigit = calcControlDigit == 10 ? 0 : calcControlDigit
    
    return finalControlDigit == controlDigit
}
```

### Analysis:
- **Reversal and Alignment**: Reversing the CUI and matching weights from index 1 (the units digit) ensures the weights are applied from right to left, starting with 2, 3, 5, 7, 1, 2, 3, 5, 7, exactly matching the official Romanian CUI specification.
- **Formula**: The formula `(sum * 10) % 11` is mathematically equivalent to computing `11 - (sum % 11)` with the special case where a remainder of 10 maps to 0. 
- **Verdict**: The mathematical logic is **correct and robust** for verifying a valid Romanian CUI.

---

## 2. False Positives & CUI Extraction Gaps

Although the checksum logic is correct, the surrounding extraction workflow in `CuiExtractorAgent` has multiple gaps that introduce a high probability of false positives:

### A. Eager Return (First Match Wins)
In `CuiExtractorAgent.process`, three loops are executed in sequence:
1. Check candidate boxes (boxes matching keywords).
2. Check boxes near candidate boxes.
3. Check **all boxes in the document**.

In all three loops, the first box containing a number that passes `isValidCUI` is immediately assigned as the seller CUI and the method returns:
```swift
if isValidCUI(cui: numbersOnly) {
    result.cui = numbersOnly
    ...
    return
}
```
If a false positive number (like a phone number, total, or card fragment) appears earlier in the OCR box list than the real CUI, it will be extracted, and the actual CUI will be ignored.

### B. Phone Numbers Extracted as CUIs
Romanian mobile and landline numbers (10 digits starting with `07`, `02`, or `03`) have a **~9.1% (1 in 11) probability** of passing the Modulo-11 checksum.
- **Why it fails**: There are no negative filters or length restrictions targeting phone numbers in `CuiExtractorAgent.process`. If the document lists a phone number (e.g. `0212246677`) and it passes the checksum, it will be returned as the CUI.

### C. Totals and Quantities Extracted as CUIs
- **Why it fails**: Decimal numbers are converted to integers by filtering out non-digit characters (`String(text.filter { $0.isNumber })`). A total of `123.45` becomes `12345`. If `12345` passes the checksum, it can be extracted as the CUI.
- **No keyword guard**: The third fallback loop checks **every** box, ignoring whether it is near a keyword like `CIF` or `CUI`.

### D. Overly Generous `"RO"` Keyword Matching
The keyword `"RO"` is included in `cuiKeywords`. The agent does a `.contains` check on the uppercase cleaned text:
`cuiKeywords.contains(where: { cleanText.contains($0) || ... })`
Because `"RO"` is a very common substring in Romanian words (e.g., `RON`, `ROMPETROL`, `PRODUS`, `INTRODUCETI`), almost every box containing these words becomes a CUI keyword candidate, pulling in unrelated nearby numbers.

### E. Gaps in Cluster Anchor Detection
In `clusterBoxes`, the CUI anchor detection uses exact string matching on `"CIF"`, `"C I F"`, or `"CIF:"` to identify receipt bounds. If the OCR engine groups the label and value into a single block (e.g., `"CIF: RO 1234567"`), the box will fail the standalone checks and will **not** be registered as a cluster anchor. This will break splitting logic on multi-receipt images.

---

## 3. ANAF Integration

The ANAF verification logic is located in `verifyWithANAF(cui:result:)` (lines 692-739):

### Request and Payload:
- **Endpoint**: `https://webservicesp.anaf.ro/PlatitorTvaRest/api/v8/ws/tva`
- **Method**: `POST`
- **Body**: JSON array `[{"cui": "123456", "data": "2026-07-08"}]`. The CUI is passed as a string and without the `"RO"` prefix, which is correct.

### Key Gaps:
1. **Synchronous Blocking of HTTP requests**:
   The ANAF API is called using `await` inside the OCR processing chain:
   `await verifyWithANAF(cui: numbersOnly, result: &result)`
   This suspends the Vapor server's request handling while waiting for ANAF. If the ANAF server is down or slow, the Vapor endpoint will block, leading to client timeouts.
2. **Missing Timeout Configuration**:
   The `URLRequest` does not specify a custom timeout, defaulting to the system's **60 seconds**.
3. **Response Parsing**:
   Correctly extracts `denumire` (company name), `adresa` (address), and `scpTVA` (VAT registration status - returns `true` if company is a VAT payer).

---

## 4. Totals and VAT Extraction Analysis

### A. Lack of Thousands Separator Support
In both the spatial extraction and regex fallbacks, the code attempts to parse decimals using patterns like:
- `([0-9]+[.][0-9]{2})`
- `([0-9]+[.,][0-9]{2})`

If a total is `1,234.56` or `1.234,56`:
- Replacing `,` with `.` yields `1.234.56` which fails the regex.
- Failing to match means any total amount greater than or equal to `1,000` that is formatted with thousands separators **cannot** be parsed by these regular expressions, causing a total extraction failure.

### B. The `"REST"` Keyword Risk
The fallback total pattern contains the keyword `REST` (which means "change" in Romanian):
`(?i)(?:TOTAL|SUMA|ACHITAT|REST)\s*(?:LEI)?\s*[:=]*\s*([0-9]+[.,][0-9]{2})`
If a receipt lists `REST 0.00` or `REST 5.00` at the bottom, and the OCR parses it, this regex may match `REST` and extract `0.00` or `5.00` as the total, overwriting the actual purchase total.

### C. Largest Number Fallback Gaps
If no total is found, the agent takes the largest decimal number. This fails if the receipt contains card numbers, invoice/document numbers, or cash paid amounts (e.g. paying with a `500.00` bill for a `119.00` purchase), extracting the larger, unrelated value.

### D. Critical Bug: Silent VAT Recalculation Corruption
The `AccountingValidationAgent` contains a major logical bug regarding historical VAT rates (19% and 5%):

1. **Auto-Correction**:
   ```swift
   if vatPct.contains("19%") {
       // Recalculates with 21%
       result.baseAmount = newBase
       result.vatAmount = newVat
       result.vatPercentages = "21%"
       result.fiscalWarnings.append("Corecție automată: Cota TVA 19% (veche) a fost recalculată la 21% (cota 2026).")
   }
   ```
   This modifies `baseAmount`, `vatAmount`, and `vatPercentages` in-place, overwriting the original 19% values.
2. **Date Check (The Bug)**:
   ```swift
   if let dateStr = result.documentDate {
       let yearPattern = "20(2[0-4])"
       if let regex = try? NSRegularExpression(pattern: yearPattern, options: []),
          regex.firstMatch(in: dateStr, options: [], range: NSRange(location: 0, length: dateStr.utf16.count)) != nil {
           // Bonul e din 2024 sau mai devreme -> cotele vechi (19%, 9%, 5%) erau corecte
           // Stergem warning-urile de corectie automata daca exista
           result.fiscalWarnings = result.fiscalWarnings.filter { !$0.contains("Corecție automată: Cota TVA") }
       }
   }
   ```
   If the document date is 2024 or earlier, the code correctly realizes the old rates were valid and **removes the warning message**, but **fails to revert the recalculated amounts and percentage**.
   - **Result**: Historical documents from 2024 or earlier will have their VAT silently and permanently modified to 21% (from 19%) or 11% (from 5%), corrupting the accounting data output without warning the user.
