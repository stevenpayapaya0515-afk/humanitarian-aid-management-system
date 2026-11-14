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

- `ml_service/datasets/`: local prepared survey records, excluded from Git.
- `ml_service/evaluation/`: model evaluation results and limitations.
- `ml_service/models/`: locally built models, excluded from Git.
- Python training and inference scripts stay directly in `ml_service/`.

The running API still uses the APIS model through `ml_service/predict.py`.
Keep `apis_rules.py` and `build_apis_baseline.py` until the coordinated FIES
assessment/API migration is complete. A fresh GitHub checkout does not include
local model binaries. Rebuild the APIS model from your authorized source ZIP:

```powershell
.\.venv\Scripts\python.exe -m ml_service.build_apis_baseline --zip "PATH_TO_APIS_2019_ZIP"
```

The FIES builder creates an offline research candidate, not the active API model:

```powershell
.\.venv\Scripts\python.exe -m ml_service.build_fies_baseline --zip "PATH_TO_FIES_2025_ZIP" --thresholds "PATH_TO_2025_POVERTY_WORKBOOK"
.\.venv\Scripts\python.exe -m unittest tests.test_fies_baseline -v
```

Review `ml_service/evaluation/fies2025_evaluation.json` for geography exclusions,
holdout metrics, source hashes, and limitations before considering app integration.
The published NCR district mapping is supported; unmatched cities are not guessed.

Authentication uses Google reCAPTCHA via `services/recaptcha.py`.
Numbered SQL migrations, including the former local CAPTCHA migration, remain
as historical schema records. Removing an unused Python helper does not drop tables.
