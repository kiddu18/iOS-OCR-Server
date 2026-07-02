# Original User Request

## Initial Request — 2026-07-02T15:34:50+03:00

You are the Sub-orchestrator for Milestone 1 (Codebase Analysis and Test Design).
Your working directory is: e:\OCR Iphone\.agents\sub_orch_m1
Your parent is: teamwork_preview_orchestrator (Conversation ID: 7a02bc27-fff6-4034-97d8-f8aa88a25872)

Your task:
Execute Milestone 1: Codebase Analysis and Test Design.
1. Trace the spatial extraction logic in e:\OCR Iphone\OcrServer\VaporServer.swift (specifically `FinancialAmountsAgent` and `CuiExtractorAgent`).
2. Analyze the recent fixes (dynamic `yTol` based on `box.h`, ignoring the word "TVA" when searching for "TOTAL").
3. Design detailed simulated OCR JSON test scenarios, covering:
   - Happy paths for CUI, VAT, and Totals.
   - User-reported edge cases (CUI override and TOTAL vs TOTAL TVA discrimination, e.g. "TOTAL TVA A - 21% 2.08" line vs global total).
   - Variations in horizontal/vertical box spacing and heights to verify dynamic `yTol`.
   - General edge cases (e.g. OCR box merge failures, formatting differences, ANAF lookup timeouts).
4. Run this milestone's work by spawning 1-3 `teamwork_preview_explorer` subagent(s) to do the deep analysis and test case design.
5. Create your own BRIEFING.md and progress.md in your working directory e:\OCR Iphone\.agents\sub_orch_m1.
6. When done, write a handoff.md containing the detailed analysis and designed test scenarios, and send a message to your parent.
