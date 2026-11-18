# AidTrack backend

FastAPI and PostgreSQL API for LGU Administrator and LGU Staff.

From this directory, install dependencies into your existing virtual environment:

```powershell
.\.venv\Scripts\python.exe -m pip install -r requirements.txt
.\.venv\Scripts\python.exe -m uvicorn main:app --reload
```

Use your existing local `.env` and Gmail credentials. They are intentionally excluded
from Git. Database migrations live in `../database/`; do not rerun old migrations
or reset records when installing a code update.

## ML organization

- `ml_service/datasets/`: CARAGA source, proxy labels, and fixed dataset splits.
- `ml_service/datasets/apis2022_caraga_household_records.csv`: original 2,126 households / 51 source and audit columns (46 model inputs).
- `ml_service/datasets/apis2022_caraga_vulnerability_proxy_labels.csv`: researcher-defined proxy labels for all households.
- `ml_service/datasets/splits/`: 1,609 training, 412 testing, 105 excluded household CSVs.
- `ml_service/evaluation/`: model evaluation results and limitations.
- `ml_service/models/`: locally built models, excluded from Git.
- Python training and inference scripts stay directly in `ml_service/`.

The prediction endpoint uses `ml_service/predict_apis2022_vulnerability.py`.
Run migration `24_connect_apis2022_predictions.sql` after migration 23.
`POST /vulnerability/assessments/{id}/predict` now requires an
`APIS2022PredictionRequest` JSON body (see authenticated Swagger at `/docs`).
It records the original answers, household size, saved age counts, recorder,
label version, income cutoff, and rule/model disagreement in `proxy_details`.
Historical classifications remain readable. New results are always preliminary.
Manual beneficiary review and delivery confirmation remain required.

Flutter Review & Classify opens the APIS 2022 answer form and sends the explicit
request body. Missing/unsupported answers remain blocked. Failed requests retain
the form values. An old request without answers receives 422 and saves nothing.
The separate `/preview-apis2022` endpoint remains read-only.

Local model binaries are excluded from Git. Use your existing locally trained
`models/apis2022_caraga46_random_forest.joblib`. If it is missing or incompatible,
rebuild with the current prepared APIS 2022 dataset in the backend environment:

```powershell
.\.venv\Scripts\python.exe -m ml_service.prepare_apis2022_caraga_splits
.\.venv\Scripts\python.exe -m ml_service.train_apis2022_vulnerability
```

Preparation reproduces the historical random-state-42 split and the original
training-only income cutoff *before* excluding the 105 Needs review records.
Training validates the exported split CSVs against the master and reference labels
before fitting. Renaming/exporting CSV files alone does not retrain the saved model.
**Do not retrain unless you intend to re-evaluate and update research results.**
The proxy classifications are researcher-defined, not PSA/LGU verified labels.

This is survey-based Random Forest research with researcher-defined proxy labels,
not a validated PSA/LGU aid eligibility model. `app_ready=False` remains recorded.
No APIS 2019 or FIES predictor is used by this endpoint.

Authentication uses email/password followed by email OTP verification.
JWT access tokens are issued only after successful OTP verification.
The Web and Android login flows no longer require reCAPTCHA.

Historical numbered SQL migrations remain for reference.
The legacy login_captchas and ip_blocks tables were removed from the
local development database. OTP records remain in login_otps.

## Current assessment flow

Migration 22 makes the four former socioeconomic/status answers optional.
Their database columns remain for historical records; the Flutter form no longer
asks for them. Beneficiary approval belongs to Beneficiary Management.

Financial fields are stored for staff review. They do not yet drive the active
APIS prediction. The FIES candidate and evaluation files support research and
future integration; do not describe the current API as FIES-powered.

Keep tests, numbered SQL migrations, training builders, requirements files and
evaluation reports: these are maintenance/reproducibility files even when they
are not imported by main.py. The root fix_assessment_form.py was a one-time
source updater; its changes are already applied and it is no longer needed.
