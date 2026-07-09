# Original User Request

## Initial Request — 2026-07-09T09:38:17Z

Fix and finalize the iOS OCR server's spatial 2D extraction engine (specifically VaporServer.swift, ReceiptPipelinePatch.swift, and TextRecognizerPlus.swift) to correctly segment, extract, and align CUI, VAT, and totals for images containing multiple receipts (e.g., 6 receipts in one image), and ensure it handles handwriting/receipt overrides (0% VAT, payment accounts, Sumă Plătită) and double validation with ANAF successfully without data mixing.

Working directory: e:\OCR Iphone\OcrServer
Integrity mode: development

## Requirements

### R1. Correct Multi-Receipt Segmentation
The receipt segmenter must split the image into exactly the physical receipts present (e.g. 6 receipts) without horizontal over-segmentation or under-segmentation, relying on a fully working physical rotation of the input image.

### R2. Complete and Aligned Field Extraction
The engine must extract CUI, Series, Number, Date, Base, VAT, and Total for each segment correctly, ensuring fields are not mixed between different receipts.

### R3. Receipt (Chitanță) Selective Processing
When "Chitanță" is selected, the engine must force 0% VAT, base = total, suggest payment accounts (5311 for cash, 5125 for card/POS), and export the amount under "Sumă Plătită" in the Excel sheet.

### R4. Double Validation
The engine must normalize CUI queries to ANAF (stripping leading zeros), fetch the official company name, and fuzzy-match it against the receipt OCR header text to flag mismatches or verify correctness.

## Acceptance Criteria

### Automated & Manual Verification
- [ ] **Automated Verification Script**: Run a mock verification script simulating the 6-receipt OCR coordinate space to assert that 6 separate records are generated with correct CUI, VAT, and Totals.
- [ ] **CUI Normalization**: Verify that leading-zero CUIs successfully match ANAF records and pull company names.
- [ ] **Receipt Mode**: Verify that receipt mode forces VAT to 0 and correctly exports payments to Excel.
- [ ] **Compilation**: The Vapor server compiles and builds successfully in Xcode.
