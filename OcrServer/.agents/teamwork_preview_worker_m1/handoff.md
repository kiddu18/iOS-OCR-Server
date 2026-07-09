# Handoff Report - Test Script Executions

This report details the execution results of the Python test scripts requested under `e:\OCR Iphone`. No source code modifications were performed, following the constraint.

---

## 1. Observation
The following commands were run and outputs were observed:

### A. Run of `test_logic.py`
* **Command**: `python test_logic.py`
* **Result**: SUCCESS (exit code 0)
* **Log Output**:
  ```
  Number of clusters identified: 6
  Cluster 1 results: [{'cui': '123453', 'totalAmount': 119.0, 'vatAmount': 19.0, 'baseAmount': 100.0, 'vatPercentages': '19%'}]
  Cluster 2 results: [{'cui': '1234565', 'totalAmount': 200.0, 'vatAmount': 31.93, 'baseAmount': 168.07, 'vatPercentages': '19%'}]
  Cluster 3 results: [{'cui': '12345674', 'totalAmount': 150.0, 'vatAmount': 12.39, 'baseAmount': 137.61, 'vatPercentages': '9%'}]
  Cluster 4 results: [{'cui': '123456789', 'totalAmount': 119.0, 'vatAmount': 19.0, 'baseAmount': 100.0, 'vatPercentages': '19%'}, {'cui': '123456789', 'totalAmount': 54.5, 'vatAmount': 4.5, 'baseAmount': 50.0, 'vatPercentages': '9%'}]
  Cluster 5 results: [{'cui': '9876544', 'totalAmount': 80.0, 'vatAmount': 3.81, 'baseAmount': 76.19, 'vatPercentages': '5%'}]
  Cluster 6 results: [{'cui': '55553', 'totalAmount': 45.0, 'vatAmount': 0.0, 'baseAmount': 45.0, 'vatPercentages': '-'}]

  Total output rows generated: 7

  ALL TESTS PASSED SUCCESSFULLY!
  ```

### B. Run of `test_spatial_ocr.py`
* **Command 1**: `python test_spatial_ocr.py` (Default environment encoding)
* **Result**: CRASH (exit code 1)
* **Error Log**:
  ```
    Sub-case: Mismatch Case (buyerCui = 2816464)
  Traceback (most recent call last):
    File "E:\OCR Iphone\test_spatial_ocr.py", line 1146, in <module>
      run_tests()
    File "E:\OCR Iphone\test_spatial_ocr.py", line 1047, in run_tests
      print(res2_mismatch)
    File "C:\Program Files\WindowsApps\PythonSoftwareFoundation.Python.3.11_3.11.2544.0_x64__qbz5n2kfra8p0\Lib\encodings\cp1252.py", line 19, in encode
      return codecs.charmap_encode(input,self.errors,encoding_table)[0]
             ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  UnicodeEncodeError: 'charmap' codec can't encode character '\u021b' in position 246: character maps to <undefined>
  ```
* **Command 2**: `$env:PYTHONIOENCODING="utf-8"; python test_spatial_ocr.py`
* **Result**: FAILURE (exit code 1)
* **Log Output / Error**:
  ```
  ============================================================
  RUNNING SPATIAL OCR PARSING SIMULATOR TESTS
  ============================================================

  Scenario 1: Happy Path (Standard Receipt)...
  AccountingResult(type=Necunoscut, typeVerify=True, series=None, number=None, date=None, cui=8609468, cuiVerify=False, name=S.C. MEGA IMAGE S.R.L., total=119.0, totalVerify=False, vat=19.0, vatVerify=False, pct=19%, base=100.0, warnings=[])
  Scenario 1 PASSED.

  Scenario 2: CUI Override and Compliance Logic...
    Sub-case: Match Case (buyerCui = 8609468)
  AccountingResult(type=Bon Fiscal, typeVerify=False, series=None, number=None, date=None, cui=14399840, cuiVerify=False, name=S.C. DANTE INTERNATIONAL S.A., total=100.0, totalVerify=False, vat=0.0, vatVerify=True, pct=-, base=100.0, warnings=[])
    Sub-case: Mismatch Case (buyerCui = 2816464)
  AccountingResult(type=Bon Fiscal, typeVerify=True, series=None, number=None, date=None, cui=14399840, cuiVerify=False, name=S.C. DANTE INTERNATIONAL S.A., total=100.0, totalVerify=False, vat=0.0, vatVerify=True, pct=-, base=100.0, warnings=['Atenție: Bonul fiscal nu conține CUI-ul cumpărătorului (2816464). TVA-ul este complet nedeductibil!'])
  Scenario 2 PASSED.

  Scenario 3: TOTAL TVA Discrimination...
  AccountingResult(type=Necunoscut, typeVerify=True, series=None, number=None, date=None, cui=None, cuiVerify=True, name=None, total=59.5, totalVerify=False, vat=9.5, vatVerify=False, pct=19%, base=50.0, warnings=[])
  Scenario 3 PASSED.

  Scenario 4: Dynamic yTol Alignment...
    Sub-case A: Large Title
  AccountingResult(type=Necunoscut, typeVerify=True, series=None, number=None, date=None, cui=None, cuiVerify=True, name=None, total=350.0, totalVerify=False, vat=0.0, vatVerify=True, pct=-, base=350.0, warnings=[])
  Scenario 4 PASSED.

    Sub-case B: Small Distinct Lines
  AccountingResult(type=Necunoscut, typeVerify=True, series=None, number=None, date=None, cui=8609468, cuiVerify=False, name=S.C. MEGA IMAGE S.R.L., total=8609468.0, totalVerify=True, vat=0.0, vatVerify=True, pct=-, base=8609468.0, warnings=[])
  Traceback (most recent call last):
    File "E:\OCR Iphone\test_spatial_ocr.py", line 1146, in <module>
      run_tests()
    File "E:\OCR Iphone\test_spatial_ocr.py", line 1097, in run_tests
      assert res4b.totalAmount is None, f"Expected total to be None, got {res4b.totalAmount}"
             ^^^^^^^^^^^^^^^^^^^^^^^^^
  AssertionError: Expected total to be None, got 8609468.0
  ```

### C. Run of `test_adversarial_challenger.py`
* **Command**: `$env:PYTHONIOENCODING="utf-8"; python test_adversarial_challenger.py`
* **Result**: FAILURE (exit code 1)
* **Log Output / Error**:
  ```
  ======================================================================
  RUNNING ADVERSARIAL CHALLENGER TESTS ON VAPOR OCR EXTRACTION LOGIC
  ======================================================================

  Test 1: Skew and Rotated Layouts...
  DEBUG: raw_anchors = ['CIF:', '8609468', '19.00']
  DEBUG: cui_anchors = ['CIF:', '19.00']
  DEBUG: components = [['S.C. MEGA IMAGE S.R.L.', 'CIF:', 'RO', '8609468', 'TVA 19%', '100.00', '19.00', 'TOTAL', '119.00']]
  DEBUG: final_clusters = [['S.C. MEGA IMAGE S.R.L.', 'CIF:', 'RO', '8609468', 'TVA 19%', 'TOTAL'], ['100.00', '19.00', '119.00']]
  DEBUG: filtered_clusters = [['S.C. MEGA IMAGE S.R.L.', 'CIF:', 'RO', '8609468', 'TVA 19%', 'TOTAL'], ['100.00', '19.00', '119.00']]
  Traceback (most recent call last):
    File "E:\OCR Iphone\test_adversarial_challenger.py", line 1429, in <module>
      run_adversarial_tests()
    File "E:\OCR Iphone\test_adversarial_challenger.py", line 1200, in run_adversarial_tests
      assert len(clusters) == 1, f"Expected 1 cluster, got {len(clusters)}"
             ^^^^^^^^^^^^^^^^^^
  AssertionError: Expected 1 cluster, got 2
  ```

---

## 2. Logic Chain

1. **`test_logic.py` passes successfully**: This indicates that the clustering post-processing and deterministic logic work as expected when given simulated parser outputs.
2. **`test_spatial_ocr.py` console encoding crash**: The script outputs Romanian characters such as 'ț' (`\u021b`). On Windows, PowerShell consoles default to the `cp1252` encoding, which raises a `UnicodeEncodeError` when trying to print these characters to stdout. By forcing `PYTHONIOENCODING="utf-8"`, the interpreter writes in UTF-8, which resolves the print crash.
3. **`test_spatial_ocr.py` logic assertion failure (Scenario 4, Sub-case B)**: Under Sub-case B, the bounding box of text `TOTAL` (height 12, y=1000) and the bounding box of the CUI `8609468` (height 12, y=1022) have a 10px vertical gap. Because of the legacy clustering/tolerance logic inside the simulator implementation, these two distinct lines are incorrectly clustered together. As a result, the parser extracts `8609468.0` as the `totalAmount` instead of yielding `None` as expected by the assertion on line 1097.
4. **`test_adversarial_challenger.py` clustering failure (Test 1)**: For skew and rotated layouts, the parser implementation in `test_adversarial_challenger.py` expects a single clustered receipt object. However, due to coordinate thresholds/clustering logic limitations, it segments them into 2 clusters instead of 1, violating the assertion `assert len(clusters) == 1` on line 1200.

---

## 3. Caveats
* **No code modifications were performed**: In compliance with the user constraint ("Do not modify any source code files"), no fixes were applied to resolve the logical failures in `test_spatial_ocr.py` or `test_adversarial_challenger.py`.
* **Environment details**: The scripts were executed under Python 3.11 on Windows. The encoding-related error is specific to platforms where standard output encoding does not default to UTF-8.

---

## 4. Conclusion
* `test_logic.py` is fully **functional / success**.
* `test_spatial_ocr.py` is **broken / fails** due to:
  1. Default Unicode printing crash (`UnicodeEncodeError`) under `cp1252`.
  2. Legacy alignment/tolerance logic failing to separate small distinct lines (Scenario 4, Sub-case B).
* `test_adversarial_challenger.py` is **broken / fails** due to:
  1. Rotated layout clustering failing to consolidate rotated OCR bounding boxes into a single receipt (Test 1).

---

## 5. Verification Method
To independently verify the test executions and outcomes, run the following commands in the PowerShell shell at `e:\OCR Iphone`:
1. `python test_logic.py`
2. `$env:PYTHONIOENCODING="utf-8"; python test_spatial_ocr.py`
3. `$env:PYTHONIOENCODING="utf-8"; python test_adversarial_challenger.py`
Verify that the output matches the results and logs cited in Section 1.
