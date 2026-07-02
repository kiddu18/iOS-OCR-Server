# Handoff Report

## 1. Observation

Direct observations and file comparisons between `test_spatial_ocr.py` and `OcrServer\VaporServer.swift`:

### Observation A: Extra Sanitization Helper in Python Simulation
In `test_spatial_ocr.py` (lines 126-131), the helper function `sanitize_amount_text` is defined to remove spaces around dots and commas:
```python
def sanitize_amount_text(text: str) -> str:
    # Remove spaces around dots or commas that are between digits or at boundaries
    text = re.sub(r'(\d+)\s*([.,])\s*(\d+)', r'\1\2\3', text)
    # Handle leading dot: "123 .45" -> "123.45"
    text = re.sub(r'(\d+)\s+(\.\d+)', r'\1\2', text)
    return text
```
This helper is applied multiple times in the Python `FinancialAmountsAgent` implementation (lines 299, 309, 351, 366).
**Swift Counterpart**: No such function or sanitization logic exists anywhere in `OcrServer\VaporServer.swift`.

### Observation B: Divergent Box-Joining Logic in Spatial Loop
In `test_spatial_ocr.py` (lines 272-283) under `FinancialAmountsAgent.process`:
```python
                # Check for split decimal box by joining all boxes text and sanitizing
                joined_line_text = "".join([b.text for b in line_boxes])
                sanitized_line = joined_line_text.replace(",", ".")
                pattern = r"([0-9]+\.[0-9]{2})"
                match = re.search(pattern, sanitized_line)
                if match:
                    val = float(match.group(1))
                    result.totalAmount = val
                    result.totalRequiresVerification = False
                    total_found = True
                    break
```
**Swift Counterpart**: In `VaporServer.swift` (lines 804-817), the spatial total loop only checks each box individually:
```swift
                for lBox in lineBoxes {
                    let sanitized = lBox.text.replacingOccurrences(of: ",", with: ".")
                    let pattern = "([0-9]+[.][0-9]{2})"
                    if let regex = try? NSRegularExpression(pattern: pattern, options: []),
                       let match = regex.firstMatch(in: sanitized, options: [], range: NSRange(location: 0, length: sanitized.utf16.count)) {
                        let matchedString = (sanitized as NSString).substring(with: match.range(at: 1))
                        if let val = Double(matchedString) {
                            result.totalAmount = val
                            result.totalRequiresVerification = false
                            total_found = true
                            break
                        }
                    }
                }
```
There is no code in Swift to join `lineBoxes` text or check for a split decimal box pattern across multiple boxes.

### Observation C: Divergent Scenario Pass/Fail State
Scenario 5 Sub-case A ("Split Decimal Box") in `test_spatial_ocr.py` (lines 645-653) inputs:
```python
    s5a_boxes = [
        OCRBoxItem("TOTAL", 100, 900, 100, 20),
        OCRBoxItem("123", 780, 900, 50, 20),
        OCRBoxItem(".45", 835, 900, 50, 20),
    ]
```
The test asserts that this extracts the total amount `123.45` successfully.
Since `123` and `.45` are separate boxes on the line, the individual box checks in Swift's `FinancialAmountsAgent` will fail, and the fallback regex checks will fail because the line will be joined with a space (e.g. `"TOTAL 123 .45"`), which does not match Swift's pattern `([0-9]+[.,][0-9]{2})`.
Thus, the actual Swift backend will fail to parse this receipt, while the Python test suite falsely certifies that the parser passes this scenario.

## 2. Logic Chain

1. **Step 1 (Simulation Authenticity)**: A simulated agent suite used for automated testing is only authentic and correct if it faithfully simulates the actual production logic it tests.
2. **Step 2 (Feature Discrepancy)**: The Python code implements two key features — split-box decimal joining and space sanitization — which are absent in the Swift production codebase (`VaporServer.swift`).
3. **Step 3 (Divergence consequence)**: Because of these features, the Python simulation passes Scenario 5 Sub-case A ("Split Decimal Box").
4. **Step 4 (Production Behavior)**: If the identical OCR input from Scenario 5 Sub-case A is sent to the Swift server, it will fail to extract the total amount due to the lack of box joining and sanitization.
5. **Step 5 (Verdict)**: The test suite represents a facade implementation of the Swift parser. It bypasses the real production logic's limitations, verifying a more robust python version of the parser instead. Under Benchmark Mode, this constitutes a facade implementation and a bypass of the logic (INTEGRITY VIOLATION).

## 3. Caveats

- We did not modify any code in `OcrServer\VaporServer.swift` since the prompt states that we should align the Python simulation behavior with the Swift production codebase, keeping Swift as the source of truth.
- No other potential behavioral discrepancies between Python and Swift were flagged in the audit, so this recommendation specifically targets the sanitization and box-joining logic in `test_spatial_ocr.py`.

## 4. Conclusion

To fix the integrity violation, we must remove all sanitization logic (`sanitize_amount_text`) and the split decimal box-joining logic from `test_spatial_ocr.py`. This aligns the Python parser simulation exactly with the Swift implementation.
Furthermore, the test assertion in Scenario 5 Sub-case A must be updated to expect `None` for total amount and `True` for manual verification flag, as the Swift production codebase cannot successfully extract split decimal boxes in this configuration.

A complete patch file has been prepared at:
`e:\OCR Iphone\.agents\explorer_m2_1\test_spatial_ocr.patch`

## 5. Verification Method

To verify the alignment:
1. Apply the patch `test_spatial_ocr.patch` using standard patch application:
   ```bash
   git apply .agents/explorer_m2_1/test_spatial_ocr.patch
   ```
2. Run the Python tests:
   ```bash
   python test_spatial_ocr.py
   ```
3. The test suite should pass successfully, confirming that Scenario 5 Sub-case A now expects `None` and passes with the corrected Swift-aligned assertions.
