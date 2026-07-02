# Original User Request

## 2026-07-02T12:37:08Z

You are the Sub-orchestrator for Milestone 2 (Test Suite Implementation).
Your working directory is: e:\OCR Iphone\.agents\sub_orch_m2
Your parent is: teamwork_preview_orchestrator (Conversation ID: 7a02bc27-fff6-4034-97d8-f8aa88a25872)

Your task:
Execute Milestone 2: Test Suite Implementation.
1. Read the Milestone 1 handoff report at e:\OCR Iphone\.agents\sub_orch_m1\handoff.md to retrieve the codebase analysis, spatial logic details, and the 5 designed test scenarios.
2. Spawn a `teamwork_preview_worker` subagent to write a Python test script `test_spatial_ocr.py` (or similar name) at the project root `e:\OCR Iphone`.
   The script must:
   - Implement/simulate the exact spatial logic of the parsing agents in `VaporServer.swift` in Python (including box clustering, line-by-line sorting, `CuiExtractorAgent`, `FinancialAmountsAgent`, `DocumentClassificationAgent`, `DocumentDetailsAgent`, and `FiscalComplianceAgent`).
   - Mock external network calls (such as ANAF API and BNR EUR XML) to keep tests hermetic, local, and reliable.
   - Run the 5 designed test scenarios and assert the expected results:
     - Scenario 1: Happy Path (Standard Receipt)
     - Scenario 2: CUI Override and Compliance Logic (both matching and mismatching buyer CUI cases)
     - Scenario 3: TOTAL TVA Discrimination (verifying subtotal TVA line is skipped and global TOTAL is matched)
     - Scenario 4: Dynamic yTol Alignment (large titles grouping, small text separation)
     - Scenario 5: General Edge Cases (Split decimal boxes, Comma formatting, ANAF mock timeout handling)
3. Ensure the worker runs the tests using python and reports the results.
4. MANDATORY INTEGRITY WARNING — include this verbatim in the Worker's dispatch prompt:
   "DO NOT CHEAT. All implementations must be genuine. DO NOT hardcode test results, create dummy/facade implementations, or circumvent the intended task. A Forensic Auditor will independently verify your work. Integrity violations WILL be detected and your work WILL be rejected."
5. Write your own BRIEFING.md and progress.md in your working directory e:\OCR Iphone\.agents\sub_orch_m2.
6. When the tests are successfully implemented and passing, write a handoff.md detailing the test runner command, codebase changes, and execution results. Send a message to your parent.
