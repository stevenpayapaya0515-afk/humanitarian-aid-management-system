# AidTrack — APIS PUF 2022 expanded household dataset

**Status:** Prepared and cross-joined; **not model-ready**, and **not an LGU-verified vulnerability-label dataset**. Prepared from the 11 original APIS PUF 2022 CSV extracts provided for this project. No new/synthetic household records were generated.

## Files

- `datasets/apis2022_household_indicators.csv` — **43,517 household rows; 85 columns** (features, identifiers, survey fields and quality checks). Recommended file for reviewing the expanded candidate features.
- `datasets/apis2022_household_indicators_draft_labels.csv` — **43,517 household rows; 88 columns**. Same columns plus three `baseline_*` columns copied, unchanged, from the user's existing Astra draft proxy label file. Use **only for comparison/experimental rule-agreement modeling**, NOT as validated humanitarian outcomes.
- `metadata/feature_dictionary.csv` — every exported column, source, purpose, and model-use caution.
- `metadata/quality_report.json` — row counts, key checks, Caraga record counts, original file hashes, and quality flags.
- `build_apis2022_expanded.py` — reproducible Python standard-library builder. The original 11 source files are *not* bundled because the derived dataset is already provided; keep them locally if you want to re-run the builder.

## Source data included

All 11 original CSV sources are used. One output row equals one original household (`REG` + `HHID`):

1. **Household Record:** household size, age/sex/education code of household reference person, child fields, sample metadata.
2. **Member Record:** aggregates of available member rows by age bracket and counts of `D44_DISEASE` response code 1. The raw member rows are not duplicated in the household-level dataset.
3. **RTG1 Social Insurance:** full category response values, and number of response-code-1 categories.
4. **RTG2 Social Assistance:** full category responses and code-1 count.
5. **RTG3 Labor Market Intervention:** full category responses and code-1 count.
6. **RTG4 Government Feeding Programs:** full category responses and code-1 count.
7. **RTG5 PhilHealth and Disaster:** `G13_PHEALTH`, `G13A_ASSISTANCE`, `G14_AWARE`, `G14A_CONSULT`, `G15_KIT`, `G15A_TYPE`, `G16_NAT_DISAS`, `G16A_EVAC`, `G16B_RECOV`, `G16C_HELP`.
8. **RTH Government Services:** full category responses and code-1 count.
9. **RTI Housing:** `I1`–`I8`.
10. **RTJ Water/Sanitation:** `WS1`, `WS11A`, `WS14`, `WS15`.
11. **RTK Other Relevant Information:** `K4`, `K5` (retain their source names and values; **verify their exact definitions before calling them income or expenditure**).

**Caution on social protection:** `G1_CODE1_COUNT`, `G5_CODE1_COUNT`, `G9_CODE1_COUNT`, `G11_CODE1_COUNT`, and `H1_CODE1_COUNT` count responses **literally coded `1`**, without assuming the response code means “yes” until verified against the questionnaire/codebook. Receiving assistance is not by itself evidence of low vulnerability.

## Important validation results

- 43,517 distinct households, unique (`REG`, `HHID`).
- All eleven sources map to **exactly** the same household keys. Repeated-category files are pivoted to one row per household, rather than naively joined.
- 2,126 Caraga households (`REG=16`), of which the **inherited** draft labels include 1,551 Low, 453 Medium, 102 High, and 20 Needs review.
- In **2,411 households**, `MEMBER_ROWS` is *smaller than* `FSIZE` (household size). The member-level source and household-level size therefore do **not** always describe an identical roster count. `MEM_ROSTER_MATCHES_FSIZE` and `MEM_ROSTER_SHORTFALL` expose this discrepancy. **Do not treat derived age bracket counts as a complete household dependency census without investigating**.
- Raw empty coded values remain empty rather than automatically filled or guessed; conditional questions (e.g. evacuation when no disaster) commonly have empty values.
- All values are from the PUF except the clearly named member aggregate counts, response-code counts, and QA flags. The baseline proxy labels are copied from the existing draft, not independently validated or recalculated.
- Source file `RTK` contains two lines with an extra *empty* trailing field; the builder strictly tolerates only an empty extra field and rejects a nonempty one.

## Use in your local AidTrack project

**Do not overwrite Astra's existing dataset or joblib file yet.** The safe route is to put the new dataset files next to the existing APIS datasets:

`C:\VS Code\humanitarian-aid-management-system\backend\ml_service\datasets\`

1. Download the ZIP archive supplied in the ChatGPT response.
2. Extract it to `C:\VS Code\humanitarian-aid-management-system\backend\ml_service\`. It adds new filenames in `datasets/`, and the `metadata/` folder, plus this README and the build script. Existing `apis2022_proxy_draft.csv`, `apis2022_households_unlabelled.csv`, and `apis2022_candidate.joblib` do not need replacement.
3. Inspect the 85-column unlabelled file first. **Do not simply point `train_apis2022.py` at the 88-column baseline-labelled file and claim validation.** The inherited labels do not reflect the newly added criteria.
4. Review the official APIS PUF 2022 questionnaire/data dictionary for response meanings, nonresponse codes, conditional responses, and the definitions of `K4/K5` before engineering risk scores.
5. Define and obtain approval for the **expanded AidTrack humanitarian vulnerability rubric** (or, preferably, acquire independently verified household-level assessment labels). Only then train a new versioned candidate with strict feature selection and regional/group-based holdouts.
6. Keep `REG`, `HHID`, `RPSU`, `REP`, `RFACT`, member-roster QA flags, and any original baseline target columns out of the actual predictive features; survey weights are for survey inference, not default model features. Review potentially sensitive fields and fair-treatment implications before use.

## Why there is no new “High / Medium / Low” label column

The previous labels were constructed using a *living-conditions rule*. Newly adding social protection, age, and disaster columns does **not** automatically change what the target means. A model trained on inherited labels may report excellent accuracy while merely reproducing the old six-variable rubric. Fabricating new vulnerability labels without an explicit reviewed rubric would be misleading for an LGU humanitarian aid workflow.

## Rebuild example (optional)

Place the 11 original CSV files in a separate folder, and your existing baseline labelled CSV in any accessible path:

```powershell
.\.venv\Scripts\python.exe .\build_apis2022_expanded.py `
  --input-dir "C:\path\to\original-apis-puf-2022" `
  --labels "C:\path\to\apis2022_proxy_draft.csv" `
  --output-dir ".\datasets"
```

The script uses only Python's standard library; no new dependencies are needed.

## Provenance and limitations

This is a derivation of **APIS PUF 2022 survey data**, not a Cabadbaran City household registry. Region code 16 represents Caraga only: the regional public-use file does not identify individual Agusan del Norte/Cabadbaran households. Do not import PUF households as real LGU beneficiaries. Use for exploratory model development and research, subject to the source dataset's reuse terms.
