## 2026-07-02T17:25:27Z
You are a worker subagent. Your role is: worker.
Your working directory is: e:\OCR Iphone\.agents\worker_m2_remediate_2

Task:
Remediate the simulation logic divergence in `test_spatial_ocr.py` (located at `e:\OCR Iphone`) to align it exactly with the Swift production codebase (`OcrServer\VaporServer.swift`).
Specifically, perform the following modifications on `test_spatial_ocr.py`:
1. Remove the function `sanitize_amount_text(text: str) -> str` (around lines 125-131).
2. In `FinancialAmountsAgent.process`:
   - Remove the block of code that joins line boxes (around lines 272-283) to match split decimal boxes.
   - The loop over `line_boxes` should only check individual boxes using regex `r"([0-9]+\.[0-9]{2})"`, replacing commas with dots, exactly as Swift does.
   - Replace any occurrences of `sanitized_full_text = sanitize_amount_text(full_text)` and subsequent regex operations with operations directly on `full_text`.
   - Replace any occurrences of `sanitized_line_text = sanitize_amount_text(line_text)` and subsequent regex operations with operations directly on `line_text`.
3. In `run_tests()`, under Scenario 5 Sub-case A (Split Decimal Box), update the assertions to reflect that the Swift-aligned simulation fails to parse the split decimal:
   - Expect/assert `res5a.totalAmount is None` instead of `123.45`.
   - Expect/assert `res5a.totalRequiresVerification` to be `True`.
4. Execute `python test_spatial_ocr.py` from the project root `e:\OCR Iphone` using `run_command` (Cwd: `e:\OCR Iphone`). Wait for the execution and report the full stdout and stderr back to verify that all tests pass.

MANDATORY INTEGRITY WARNING — include this verbatim in the Worker's dispatch prompt:
"DO NOT CHEAT. All implementations must be genuine. DO NOT hardcode test results, create dummy/facade implementations, or circumvent the intended task. A Forensic Auditor will independently verify your work. Integrity violations WILL be detected and your work WILL be rejected."
