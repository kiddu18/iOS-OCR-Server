# Scope: Milestone 2 - Test Suite Implementation

## Architecture
The test suite implements the spatial parsing logic from `VaporServer.swift` in a Python script `test_spatial_ocr.py` located at the project root.
External network dependencies (ANAF API, BNR rates) are mocked.
The 5 designed test scenarios from Milestone 1 are run to verify parsing correctness.

## Milestones
| # | Name | Scope | Dependencies | Status |
|---|------|-------|-------------|--------|
| 1 | Create test_spatial_ocr.py | Implement the parser agents and scenarios in Python | none | PLANNED |
| 2 | Execute tests | Run the Python script and verify output | M1 | PLANNED |
| 3 | Verify integrity | Verify with Forensic Auditor | M2 | PLANNED |
