# Scope: Milestone 1 - Codebase Analysis and Test Design

## Architecture
- Swift-based Vapor web server located in `e:\OCR Iphone\OcrServer\VaporServer.swift`.
- Spatial extraction logic resides in `FinancialAmountsAgent` and `CuiExtractorAgent`.
- Target is analyzing how text blocks/boxes are grouped, how vertical tolerance `yTol` is computed or applied dynamically, and how key phrases like "TOTAL" and "TOTAL TVA" are parsed.

## Milestones
| # | Name | Scope | Dependencies | Status |
|---|------|-------|-------------|--------|
| 1 | Spatial Extraction Analysis | Trace spatial grouping logic and recent fixes (dynamic yTol, TOTAL TVA discrimination) in VaporServer.swift | None | DONE |
| 2 | Simulated OCR Test Case Design | Design detailed JSON test scenarios covering happy paths, edge cases, spacing variations, and formatting/lookup timeouts | M1.1 | DONE |

## Interface Contracts
- Input: simulated OCR JSON structure containing text lines and bounding boxes (x, y, w, h).
- Output: parsed CUI, VAT, and Total amounts, with correct validation/lookup.
