# Verification Plan - Challenger 1

## Step 1: Run Existing Python Tests
Run the following test files:
- `test_logic.py`
- `test_spatial_ocr.py`
- `scratch/mock_test.py`
Verify they all execute and pass without error.

## Step 2: Analyze Boundary / Corner Case Coverage
Check the test files and implementation logic for how they handle:
- Rotated layouts (e.g. coordinates altered by rotation or 2D distance alignment).
- Phone numbers (making sure they are not extracted as CUIs, even if mathematically valid CUI check passes or fails).
- Invalid CUIs (correctly identified and flagged).
- Thousands separators (correct parsing of amount formatting like `1.234,56` or `1,234.56`).
- Pre-2025 receipts vs 2026 receipts (checking if there is date-based/version-based logic in CUI or VAT processing, or compliance warnings).

## Step 3: Implement and Run New Test Scenarios
Write a new Python script `scratch/adversarial_tests.py` that imports or mimics the core logic functions and tests them against adversarial scenarios. Examples:
- A box containing a phone number that is mathematically valid as a CUI (e.g. starting with `07`, `02`, `03` but satisfying the CUI Luhn/mod11 checksum).
- Amounts containing thousands separators, spaces, and mixed notations.
- Receipts from 2026 showing new/changed rules if any exist (e.g. VAT limit change/deductibility threshold rules for 2026 receipts).
- Simulated rotated bounding boxes (2D rotation transformation) to check coordinate alignment resilience.
- CUIs with OCR errors and checking whether they are correctly corrected via fallback/ANAF query simulation.

## Step 4: Write Verification Report
Document findings, evidence chain, and conclusions in `handoff.md`.
