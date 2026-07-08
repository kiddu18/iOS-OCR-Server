# Original User Request

## 2026-07-03T07:25:19Z

Fix the iOS OCR server's spatial 2D extraction engine (specifically VaporServer.swift) to correctly segment, extract, and align CUI, VAT, and totals for images containing multiple receipts (e.g. 6 receipts in one image), and ensure it splits multiple VAT rates into individual rows properly.

Working directory: e:\OCR Iphone\OcrServer
Integrity mode: development

## Requirements

### R1. Robust Multi-Receipt Clustering
The engine must segment OCR bounding boxes into separate groups corresponding to each physical receipt in the image, using CUI/CIF occurrences as anchors. It must ignore buyer CUI indicators and handle split OCR boxes (e.g. "CIF" and "RO12345" in separate boxes).

### R2. Complete VAT and Total Extraction
For each segmented receipt, the engine must correctly extract the total amount and all VAT (TVA) rates and values, matching the physical receipt's layout and preventing layout shifts from assigning numbers to incorrect receipts.

### R3. VAT Breakdown Splitting
When a receipt contains multiple VAT rates (e.g., 9% and 21%), the engine must split it into multiple `AccountingResult` records (one per VAT rate) with mathematically calculated base amounts (`Base = TVA / Rate`) and specific totals.

## Verification Plan

### Automated Verification
- Run a Python verification script (`test_logic.py`) that uses mock OCR box coordinates representing the 6-receipt image to assert that 6 separate records are generated with the correct CUI, VAT, and Totals.

### Manual Verification
- Rebuild the Vapor server, upload the 6-receipt image, and verify in the WebUI that 6 separate rows appear with correct data.

## Acceptance Criteria

### Extraction Accuracy
- [ ] The algorithm must correctly identify 6 separate receipts from the test boxes.
- [ ] For each receipt, the extracted Seller CUI must match the actual seller, never the buyer CUI.
- [ ] The total amount and VAT amount/rate must be extracted and associated with the correct receipt.
- [ ] Receipts with multiple VAT rates must be split into separate rows in the output.

## Follow-up — 2026-07-03T10:03:25Z

Fix the OCR bounding box clustering logic in `VaporServer.swift` to correctly identify and separate multiple receipts from a single image. The current algorithm fails to separate the receipts and merges them into a single invalid result.

Working directory: e:\OCR Iphone\OcrServer
Integrity mode: development

## Requirements

### R1. Correctly cluster OCR boxes into separate receipts
The system must identify anchor points (e.g., Seller CUI/CIF keywords) and group the corresponding geometric bounding boxes into distinct clusters, one for each receipt present in the image. We know there are exactly 6 receipts in the user's test image.

### R2. Handle OCR text inaccuracies
The anchor detection and clustering logic must be robust to common OCR mistakes, such as misread digits or characters in CUI strings (e.g., "R077454P" instead of "RO7745470"), relying more on reliably read keywords (like "COD FISCAL") and spatial relationships.

### R3. Extract financial amounts per cluster
For each isolated receipt cluster, the system must accurately extract the Total, VAT amount, and Base amount.

## Acceptance Criteria

### Verification Mechanism
- [ ] Programmatic Mock Test: The agent team must create a Python or Swift mock script (in the scratch directory) that simulates the 6 receipts using roughly accurate relative coordinates and the exact text strings provided in the user's OCR results.
- [ ] The algorithm must successfully cluster the mock boxes into exactly 6 distinct groups.
- [ ] The algorithm must extract non-zero, correct Total and VAT amounts for each of the 6 clusters based on the mock data.

## Follow-up — 2026-07-07T21:26:41Z

Fix the Swift Vapor OCR extraction server that currently fails to correctly cluster receipts in a 2D grid and accurately extract CUIs, totals, and VAT amounts. In the latest run, totals were extracted extremely low (e.g. 4.84, 10.39 instead of 188.75, 188.16) because the clustering algorithm broke.

Working directory: e:\OCR Iphone\OcrServer
Integrity mode: development

## Requirements

### R1. Correctly Cluster 2D Receipts
The system must correctly group text boxes belonging to the same receipt when multiple receipts appear in a single image (e.g., a 2x3 grid), regardless of the image's rotation. Ensure the clustering fix doesn't inadvertently break the bounding box assignment for totals and VAT.

### R2. Extract Valid CUIs
The CUI extractor must strictly enforce the official Romanian Modulo-11 checksum to prevent false positives (like extracting totals or phone numbers as CUIs) and correctly verify them using the existing ANAF integration.

### R3. Extract Accurate Totals and VAT
The system must accurately identify the Total amount and the corresponding VAT (TVA), handling cases where the OCR might read the text slightly off or when the values are not perfectly aligned horizontally.

## Verification Resources
- Python mock scripts (`scratch/test_final.py` or similar) are available in the workspace to validate logic against the dataset. Ensure Python and Swift logic remain synchronized.
- You have the ability to run Swift/Vapor from the command line (e.g., via Docker or WSL) to compile and test the code directly.

## Acceptance Criteria

### Extraction Accuracy
- [ ] Processing the provided test image with 6 receipts successfully identifies exactly 6 distinct receipts.
- [ ] No invalid CUIs (e.g., `42553` or `14626`) are extracted.
- [ ] Totals match the visual receipts (e.g., MOL=188.16, Magistral=188.75).
- [ ] VAT amounts are correctly identified even if the word "TVA" and the numerical value are not perfectly adjacent in the OCR output.
