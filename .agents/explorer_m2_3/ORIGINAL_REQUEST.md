## 2026-07-02T12:48:53Z

You are an explorer subagent. Your role is: explorer.
Your working directory is: e:\OCR Iphone\.agents\explorer_m2_3
Your parent is: sub_orch_m2

Task:
Analyze the forensic audit report below which has flagged an INTEGRITY VIOLATION in our Python test suite `test_spatial_ocr.py` due to simulation logic divergence from the Swift codebase `OcrServer\VaporServer.swift`.
Recommend a fix strategy for the test suite (`test_spatial_ocr.py`) to align the Python simulation behavior exactly with the actual production Swift codebase. Specifically, remove custom Python features like `sanitize_amount_text` and box-joining code that are absent in the Swift codebase, and update test assertions (like Scenario 5 Sub-case A) to reflect the true behavior of the Swift server.

SCOPE DOCUMENT:
Read scope document at e:\OCR Iphone\.agents\sub_orch_m2\SCOPE.md.

FULL AUDIT EVIDENCE REPORT VERBATIM:
---
# Handoff Report

## Forensic Audit Report

**Work Product**: `e:\OCR Iphone\test_spatial_ocr.py` and simulated Swift parsing agents vs `e:\OCR Iphone\OcrServer\VaporServer.swift`
**Profile**: General Project
**Verdict**: INTEGRITY VIOLATION

### Phase Results
- **Source Code Analysis**: FAIL — Divergence in simulated agent logic. The Python test suite `test_spatial_ocr.py` contains preprocessing and box-joining logic (specifically to pass Scenario 5 Sub-case A) which is completely missing from the actual Swift implementation in `VaporServer.swift`.
- **Behavioral Verification**: FAIL — The test suite validates a simulated Python model of the agents rather than the actual Swift code, and this simulation uses custom logic to pass its own test cases, rendering it a facade.
- **Dependency Audit**: PASS — Core logic is implemented directly rather than delegated to third-party blackbox libraries.

---

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

---

## 2. Logic Chain

1. **Step 1 (Simulation Authenticity)**: A simulated agent suite used for automated testing is only authentic and correct if it faithfully simulates the actual production logic it tests.
2. **Step 2 (Feature Discrepancy)**: The Python code implements two key features — split-box decimal joining and space sanitization — which are absent in the Swift production codebase (`VaporServer.swift`).
3. **Step 3 (Divergence consequence)**: Because of these features, the Python simulation passes Scenario 5 Sub-case A ("Split Decimal Box").
4. **Step 4 (Production Behavior)**: If the identical OCR input from Scenario 5 Sub-case A is sent to the Swift server, it will fail to extract the total amount due to the lack of box joining and sanitization.
5. **Step 5 (Verdict)**: The test suite represents a facade implementation of the Swift parser. It bypasses the real production logic's limitations, verifying a more robust python version of the parser instead. Under Benchmark Mode, this constitutes a facade implementation and a bypass of the logic (INTEGRITY VIOLATION).
---
