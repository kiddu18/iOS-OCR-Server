# Analysis Report: OCR Server Codebase and Requirements Investigation

This report provides a detailed read-only codebase analysis of the Vapor OCR Server project, focusing on requirements R1-R4, build systems, and test scripts.

---

## 1. Key Components Overview

The core OCR extraction pipeline consists of the following key Swift files located in `e:\OCR Iphone\OcrServer`:
- **`VaporServer.swift`**: Sets up the HTTP server using the Vapor framework (listening on the configured port, e.g., 8000). Handles `/ping`, `/upload`, `/docOCR`, and `/debug_boxes` routes. It defines the main `AccountingResult` structure, the `AccountingAgent` protocol, all individual extraction agents, and the `AccountingOrchestrator` which coordinates the agent execution.
- **`TextRecognizerPlus.swift`**: Extends the default text recognizer. Performs rapid orientation probing, word-level box extraction (reversing Vision's default bottom-left coordinate origin to top-left), and cropped segment enhancement (grayscale, contrast scaling, luminance sharpening, and upscale) to improve low-contrast thermal print OCR.
- **`ReceiptPipelinePatch.swift`**: Implements helper modules for the refined receipt extraction pipeline:
  - `ReceiptSegmenter`: Implements recursive XY-cut, segment merging, and header-based semantic splits.
  - `CUI`: Functions to validate CUI checksums (Romanian checksum), clean OCR digits, and scan lines for potential seller CUI candidates while avoiding buyer context.
  - `ANAF`: Connects to ANAF v9 API for batch CUI verification and computes name fuzzy matching scores.
  - `RomanianVAT`: Determines applicable VAT rates (date-aware) based on the document date, in accordance with Legea 141/2025.
  - `FinancialExtraction`: Matches currency amounts using regular expressions and mathematical reconciliation rules.
  - `AccountSuggestion`: Classifies receipt content into standard expense accounts (Class 6).

---

## 2. Multi-Receipt Spatial 2D Extraction Engine & Physical Rotation (R1)

### Physical Image Rotation
Before segmenting or performing detailed OCR, the input image is analyzed for correct orientation in `TextRecognizerPlus.normalizedCGImage(from:)`:
1. It probes four candidate orientations: `.up`, `.right`, `.down`, and `.left`.
2. For each orientation, it applies a fast rotation and executes a `.fast` OCR pass.
3. It evaluates candidate horizontal text lines (defined as boxes where width > height * 1.2).
4. A score is computed as `Double(c.string.count) * Double(c.confidence)`.
5. The orientation yielding the highest score is selected.
6. The image is physically rotated using `CIImage.oriented(orientation)` and converted into a normalized `CGImage`.

### Spatial 2D Extraction Engine
The codebase uses two different segmentation approaches depending on the input type:
1. **For Images (Camera Uploads)**:
   - Uses `ReceiptSegmenter.segment(_ words:)` running on global word-level boxes.
   - **Recursive XY-cut**: Divides boxes along horizontal or vertical axes where the gap between text blocks exceeds a threshold proportional to the median text height (`mh * 1.0` for X-gap, `mh * 1.5` for Y-gap).
   - **Merge Fragments**: Combines vertically adjacent fragments (`mergeFragments`) if they overlap horizontally (>45%) and have a vertical gap `< 7 * mh`, unless both pieces contain distinct receipt headers.
   - **Semantic Split by Header Anchors**: Scans the text for keywords like `NUMAR BON` or `COD FISCAL`. If a single cluster contains more than one header, it splits the cluster vertically at the header boundaries to ensure one receipt per segment.
   - **Crop & Re-OCR**: Once segmented, each receipt bounding box is cropped from the rotated image, processed with `enhanceForThermalPrint` (grayscale, contrast = 1.35, brightness = 0.02, sharpness = 0.4, 2x upscale if width < 900px), and OCR-ed a second time using `.accurate` settings to yield cleaner text.
2. **For PDFs**:
   - Uses `AccountingOrchestrator.shared.clusterBoxes(_:)`.
   - Identifies seller CUI anchors (containing `CODFISCAL`, etc.) and performs recursive bisection (`recursiveSplit` / `findBestGapSplit`) along the axis with the largest gap between anchors.

---

## 3. Completeness & Alignment of Fields (R2)

The extraction agents in `VaporServer.swift` align and validate the fields as follows:
- **CUI (Seller)**: Extracted by `CuiExtractorAgent` calling `CUI.candidates`. It uses a regular expression to locate CUI candidates (excluding lines containing buyer keywords like `CLIENT`, `CUMPARATOR`, `CNP`, or the buyer's own CUI). OCR errors are corrected (e.g., `O -> 0`, `I -> 1`, `S -> 5`). Valid candidates are checked via the Romanian CUI checksum. Unverified but structurally valid numbers are verified in a single batch query to the ANAF v9 API.
- **Series**: Extracted in `DocumentDetailsAgent` using:
  `(?:SERIA|SERIE|SERIA:|CHITANTA\\s*SERIA)\\s*([A-Z]{1,5})` on the full text.
- **Number**: Extracted in `DocumentDetailsAgent` using:
  `(?:NR\\.?|NUMAR|BON\\s*NR\\.?|FACTURA\\s*NR\\.?|CHITANTA\\s*NR\\.?|BF\\.?)\\s*[:]*\\s*([0-9]{1,10})` on the full text.
- **Date**: Extracted in `DocumentDetailsAgent` using:
  `(?:DATA\\s*[:]*\\s*)?([0-3][0-9][\\.\\-\\/][0-1][0-9][\\.\\-\\/]20[0-9]{2})` on the full text.
- **Base, VAT, Total**:
  - `FinancialAmountsAgent` searches for total-related keywords (`TOTAL`, `SUMA`, `ACHITAT`) and locates the nearest decimal box (excluding common VAT rates or "TOTAL TVA"). A fallback regex `(?:TOTAL|SUMA|ACHITAT|REST)...([0-9]+[.,][0-9]{2})` is applied if keyword proximity fails.
  - Active VAT rates are selected based on the document date according to Romanian tax regulations (`RomanianVAT.validRates`). For documents after August 1, 2025, standard 21% and reduced 11% apply (9% is valid only for housing transit until July 31, 2026).
  - The engine matches VAT and Base amounts by testing if any extracted number corresponds to the expected VAT calculated from the total (Method A) or by searching for pairs where `VAT = Base * rate / 100` (Method B).
  - **Mathematical Reconciliation**: `FinancialExtraction.reconcile` validates the amounts. If the values are inconsistent, the agent attempts to correct them (e.g., recalculating the total from the VAT and matching it with numbers on the receipt). If a significant mismatch remains, it flags the fields for manual verification.

---

## 4. Receipt (Chitanță) Selective Processing (R3)

- **Forcing 0% VAT and Base = Total**: Implemented.
  In `VaporServer.swift` (`FinancialAmountsAgent.process` and `AccountingOrchestrator.processOcrResult`), if the document is classified as a receipt (`Chitanță de mână` or `Chitanță POS`), the engine forces the VAT rate to `0%` (`vatAmount = 0`, `vatPercentages = "-"`), sets `baseAmount = totalAmount`, and clears any VAT breakdown objects.
- **Suggesting Payment Accounts (5311/5125)**: **GAP IDENTIFIED.**
  The Swift code does **not** implement account suggestions for receipts. In `AccountingValidationAgent.process`, the engine calls `AccountSuggestion.suggest` which returns expense accounts (e.g., 6022, 623, 628, 604, 303) based on keywords in the text. It does not inspect the document type to suggest the cash account `5311` (for `Chitanță de mână`) or the card account `5125` (for `Chitanță POS`).
- **Sumă Plătită in Excel Export**: Implemented.
  In `e:\OCR Iphone\WebClient\app.js` (lines 296-307 and 322-339), if the document type is `Chitanță de mână` or `Chitanță POS`, the Excel exporter writes the total amount under the column header `"Sumă Plătită"` instead of the mapped total column header, and leaves the base, VAT, and VAT percentage columns blank.

---

## 5. Double Validation (R4)

- **ANAF Normalization**: Implemented.
  In `VaporServer.swift` line 450:
  `let cleanCui = String(Int(cui) ?? 0)`
  This converts the extracted CUI to an integer and back to a string, effectively stripping any leading zeros to match the key returned by the ANAF v9 API batch response.
- **Company Name Fuzzy Matching**: Implemented.
  In `ANAF.nameMatchScore` (`ReceiptPipelinePatch.swift`), the ANAF official name (`date_generale.denumire`) and the OCR header text are tokenized by removing non-alphanumeric characters, splitting by space, and filtering out short words (<= 2 chars) and corporate suffixes like "SRL" or "THE". The fuzzy similarity score is calculated as:
  `Score = IntersectionTokens / Min(TokensANAF, TokensOCR)`
- **Flagging Mismatches**: Implemented.
  If the fuzzy match score is `>= 0.35`, the CUI is marked verified (`cuiRequiresVerification = false`). If the score falls below `0.35`, it flags the mismatch by keeping `cuiRequiresVerification = true` and appending a fiscal warning:
  `"⚠️ Nume necorelat: Firma înregistrată la CUI-ul [CUI] ([Official Name]) nu a fost confirmată în antetul bonului (scor: [Score]%)."`

---

## 6. Xcode Build & Compilation

The project uses a standard native iOS application workspace:
- **Xcode Project File**: `e:\OCR Iphone\OcrServer.xcodeproj` (which contains `project.pbxproj` and `project.xcworkspace`).
- **Build Configurations**: `Debug` and `Release`.
- **Target SDK**: iOS (`iphoneos` / `iphonesimulator`).
- **Minimum iOS Target**: iOS `18.4`.
- **Swift Version**: `5.0`.
- **Package Manager Integration**: Swift Package Manager is used to resolve and fetch the Vapor dependency:
  - Repository: `https://github.com/vapor/vapor.git`
  - Requirement: `upToNextMajorVersion` from `4.115.1`.
- **Command Line Build Instruction**:
  The application can be compiled from the command line using `xcodebuild`:
  `xcodebuild -project OcrServer.xcodeproj -scheme OcrServer -sdk iphoneos -configuration Release`

---

## 7. Verification & Mock Test Scripts

A comprehensive set of Python/Swift test and mock scripts is located in `e:\OCR Iphone`:
- **`test_logic.py`**: A Python mock implementation of the core classification, CUI extraction, and XY-cut recursive segmentation algorithms.
- **`test_spatial_ocr.py`**: Simulates the full spatial OCR engine, including clustering, classification, VAT extraction, and mathematical reconciliation on mock data.
- **`test_adversarial_challenger.py`**: A comprehensive Python unit test harness containing mock datasets (OCR bounding boxes) representing adversarial receipts. It validates edge cases, math corrections, classifications, and CUI checks.
- **`test_regex.swift`**: A small Swift script to test regex matches for CUI, VAT, and fallback patterns on sample receipt strings.
- **`poc_pipeline.py`**: A complete Python command-line utility implementing the XY-cut segmentation, crop-and-re-OCR simulation, ANAF v9 queries, and accounting suggestions. Run command:
  `python3 poc_pipeline.py <path_to_image>`
