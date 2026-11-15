"""Isolated API integration tests; no production database or model is loaded."""
import os
os.environ.setdefault("JWT_SECRET_KEY", "isolated-test-key")
import unittest
from datetime import datetime, timezone
from unittest.mock import patch
from fastapi import FastAPI
from fastapi.testclient import TestClient
from routes import vulnerability as api
from schemas.vulnerability import APIS2022PredictionRequest, VulnerabilityPredictionResponse
from ml_service import predict_apis2022_vulnerability as predictor


def answers():
    return dict(I2=1, I3=1, I4=1, I8=1, WS1=11, WS11A=12,
                G15_KIT=1, G16_NAT_DISAS=2, G16A_EVAC=None, G16B_RECOV=None,
                MEM_AGE_0_5=0, MEM_AGE_6_11=1, MEM_AGE_12_17=1,
                MEM_AGE_18_59=2, MEM_AGE_60_PLUS=0,
                monthly_household_income_php="20000.00")


class Pipeline:
    classes_ = ["Low", "Medium", "High"]
    def predict(self, frame): return ["Low"]
    def predict_proba(self, frame): return [[.9, .08, .02]]


class Cursor:
    def __init__(self, assessment):
        self.assessment = assessment
        self.calls = []
    def __enter__(self): return self
    def __exit__(self, *args): pass
    def execute(self, sql, args=()):
        assert sql.count("%s") == len(args)
        self.calls.append((sql, args))
    def fetchone(self):
        sql, args = self.calls[-1]
        if "INSERT INTO" not in sql: return self.assessment
        names = ["assessment_id", "predicted_class", "predicted_class_score",
                 "class_scores", "model_version", "model_training_data_origin",
                 "assessment_data_origin", "prediction_status", "proxy_details"]
        row = dict(zip(names, [getattr(x, "obj", x) for x in args]))
        return dict(row, classification_id=9, created_at=datetime.now(timezone.utc))


class Connection:
    def __init__(self, cursor): self.value = cursor
    def __enter__(self): return self
    def __exit__(self, *args): pass
    def cursor(self, **kwargs): return self.value


class IntegrationTests(unittest.TestCase):
    def setUp(self):
        self.assessment = dict(assessment_id=1, household_id=2, household_size=4,
            age_0_5_count=0, age_6_17_count=2, age_18_59_count=2,
            age_60_plus_count=0, assessment_data_origin="lgu_authorized")
        self.bundle = dict(pipeline=Pipeline(), income_cutoff=2500,
            version=predictor.MODEL_VERSION, label_version=predictor.VERSION)
        app = FastAPI()
        app.include_router(api.router)
        app.dependency_overrides[api.get_current_user] = lambda: {"role": "Staff", "user_id": 3}
        self.app = app
        self.client = TestClient(app)

    def call(self, payload=None, assessment=True, failure=None, path="predict"):
        cursor = Cursor(self.assessment if assessment else None)
        with patch.object(api, "get_connection", return_value=Connection(cursor)), patch.object(
            predictor, "load_candidate", return_value=self.bundle, side_effect=failure
        ):
            response = self.client.post(f"/vulnerability/assessments/1/{path}", json=payload)
        return response, cursor.calls

    def test_saved_result_keeps_original_answers_and_disagreement(self):
        response, calls = self.call(answers())
        self.assertEqual(response.status_code, 201, response.text)
        result = VulnerabilityPredictionResponse(**response.json())
        self.assertEqual(result.model_training_data_origin, "psa_apis2022")
        self.assertEqual(result.prediction_status, "preliminary")
        self.assertEqual(result.proxy_details["raw_answers"], answers())
        self.assertEqual(result.proxy_details["recorded_by"], 3)
        self.assertEqual(result.proxy_details["household_size"], 4)
        self.assertTrue(result.proxy_details["rule_model_disagreement"])
        self.assertFalse(result.proxy_details["app_ready"])
        writes = [sql for sql, args in calls if "INSERT" in sql or "UPDATE public" in sql]
        self.assertEqual(len(writes), 1)
        self.assertIn("vulnerability_classifications", writes[0])

    def test_saved_apis2022_answers_predict_without_reentry(self):
        self.assessment.update({
            "apis2022_i2": 1, "apis2022_i3": 1, "apis2022_i4": 1,
            "apis2022_i8": 1, "apis2022_ws1": 11, "apis2022_ws11a": 12,
            "apis2022_g15_kit": 1, "apis2022_g16_nat_disas": 2,
            "apis2022_g16a_evac": None, "apis2022_g16b_recov": None,
            "apis2022_mem_age_6_11": 1, "apis2022_mem_age_12_17": 1,
            "apis2022_monthly_household_income_php": 20000,
        })
        # 16-field saved assessments must not silently use the older model.
        response, calls = self.call(None)
        self.assertEqual(response.status_code, 422, response.text)
        self.assertFalse(any("INSERT" in sql for sql, _ in calls))
        response, calls = self.call(answers())
        self.assertEqual(response.status_code, 409, response.text)
        self.assertFalse(any("INSERT" in sql for sql, _ in calls))

    def test_preview_still_writes_nothing(self):
        response, calls = self.call(answers(), path="preview-apis2022")
        self.assertEqual(response.status_code, 200, response.text)
        self.assertTrue(response.json()["preview_only"])
        self.assertFalse(any("INSERT" in sql for sql, args in calls))

    def test_missing_and_invalid_answers_rejected_before_database(self):
        for payload in [{}, dict(answers(), I3=999), dict(answers(), MEM_AGE_0_5=True)]:
            response, calls = self.call(payload)
            self.assertEqual(response.status_code, 422, response.text)
            self.assertEqual(calls, [])
        response, calls = self.call(None)
        self.assertEqual(response.status_code, 422, response.text)
        self.assertFalse(any("INSERT" in sql for sql, _ in calls))

    def test_age_mismatch_saves_nothing(self):
        response, calls = self.call(dict(answers(), MEM_AGE_18_59=3))
        self.assertEqual(response.status_code, 422)
        self.assertFalse(any("INSERT" in sql for sql, args in calls))

    def test_missing_assessment_returns_404(self):
        response, _ = self.call(answers(), assessment=False)
        self.assertEqual(response.status_code, 404)

    def test_missing_or_incompatible_model_saves_nothing(self):
        for error in [FileNotFoundError(), RuntimeError()]:
            response, calls = self.call(answers(), failure=error)
            self.assertEqual(response.status_code, 503)
            self.assertFalse(any("INSERT" in sql for sql, args in calls))

    def test_admin_cannot_generate(self):
        self.app.dependency_overrides[api.get_current_user] = lambda: {"role": "Admin", "user_id": 3}
        response, calls = self.call(answers())
        self.assertEqual(response.status_code, 403)
        self.assertEqual(calls, [])

    def test_unauthenticated_cannot_generate(self):
        self.app.dependency_overrides.clear()
        response, calls = self.call(answers())
        self.assertIn(response.status_code, [401, 403])
        self.assertEqual(calls, [])

    def test_old_origins_remain_readable(self):
        response, _ = self.call(answers())
        for origin in ["synthetic", "psa_apis2019", "lgu_authorized"]:
            result = VulnerabilityPredictionResponse(**dict(response.json(), model_training_data_origin=origin))
            self.assertEqual(result.model_training_data_origin, origin)



class APIS2022ExpandedContractTests(unittest.TestCase):
    def test_catalog_covers_exact_focused_model_inputs(self):
        from schemas.assessments import (
            APIS2022_CATALOG, APIS2022_SOCIAL_KEYS, APIS2022_ASSESSMENT_KEYS,
        )
        from ml_service.label_apis2022_vulnerability import V2_FEATURES
        baseline = {"I2", "I3", "I4", "I8", "WS1", "WS11A", "G15_KIT", "G16_NAT_DISAS",
                    "G16A_EVAC", "G16B_RECOV", "FSIZE", "MEM_AGE_0_5", "MEM_AGE_6_11",
                    "MEM_AGE_12_17", "MEM_AGE_60_PLUS", "K5_PER_CAPITA"}
        self.assertEqual(set(APIS2022_CATALOG) | baseline, set(V2_FEATURES))
        self.assertEqual(len(APIS2022_ASSESSMENT_KEYS), 24)
        self.assertEqual(len(APIS2022_SOCIAL_KEYS), 9)

    def test_extended_validation_preserves_unknowns_and_rejects_invention(self):
        from schemas.assessments import validate_apis2022_group, APIS2022_ASSESSMENT_KEYS
        values = validate_apis2022_group({"I9A": "1", "I7": 2, "I9B": ""}, APIS2022_ASSESSMENT_KEYS)
        self.assertEqual(values, {"I9A": "1", "I7": 2})
        for wrong in ({"I9A": "4"}, {"REG": "16"}, {"I7": -1}, {"I7": 1.3},
                      {"WS14": "1"}, {"I7": "NaN"}):
            with self.subTest(wrong=wrong), self.assertRaises(ValueError):
                validate_apis2022_group(wrong, APIS2022_ASSESSMENT_KEYS)

    def test_expanded_model_accepts_saved_survey_answer_shape(self):
        import csv
        from pathlib import Path
        from ml_service import predict_apis2022_vulnerability as model
        from schemas.assessments import (
            validate_apis2022_group, APIS2022_ASSESSMENT_KEYS, APIS2022_SOCIAL_KEYS,
        )
        from ml_service.label_apis2022_vulnerability import V2_FEATURES
        path = Path(__file__).resolve().parents[1] / "ml_service/datasets/apis2022_vulnerability_proxy_labels.csv"
        with path.open(encoding="utf-8", newline="") as f:
            row = next(r for r in csv.DictReader(f) if r["v2_proxy_class"] in ("Low", "Medium", "High"))
        saved = {
            "household_size": int(row["FSIZE"]),
            "age_0_5_count": int(row["MEM_AGE_0_5"]),
            "age_6_17_count": int(row["MEM_AGE_6_11"]) + int(row["MEM_AGE_12_17"]),
            "age_18_59_count": int(row["MEM_AGE_18_59"]),
            "age_60_plus_count": int(row["MEM_AGE_60_PLUS"]),
            "apis_single_family": True,
            "apis2022_mem_age_6_11": int(row["MEM_AGE_6_11"]),
            "apis2022_mem_age_12_17": int(row["MEM_AGE_12_17"]),
            "apis2022_monthly_household_income_php": float(row["K5"]),
            "apis2022_extended_answers": validate_apis2022_group(
                {k: row[k] for k in APIS2022_ASSESSMENT_KEYS}, APIS2022_ASSESSMENT_KEYS),
            "apis2022_social_answers": validate_apis2022_group(
                {k: row[k] for k in APIS2022_SOCIAL_KEYS}, APIS2022_SOCIAL_KEYS),
        }
        for name in model.CODE_KEYS:
            saved["apis2022_" + name.lower()] = int(row[name]) if row[name] else None

        class Pipeline:
            classes_ = ["Low", "Medium", "High"]
            def predict(self, df):
                self.checked = list(df.columns) == V2_FEATURES
                return ["Medium"]
            def predict_proba(self, df): return [[0.1, 0.8, 0.1]]
        pipeline = Pipeline()
        bundle = {"pipeline": pipeline, "income_cutoff": 2500, "version": "test-v2",
                  "label_version": "test-v2"}
        with patch.object(model, "load_expanded_candidate", return_value=bundle):
            result = model.predict_expanded_saved_assessment(saved, recorded_by=3)
        self.assertTrue(pipeline.checked)
        self.assertEqual(result["proxy_details"]["feature_count"], len(V2_FEATURES))
        self.assertTrue(result["proxy_details"]["requires_staff_review"])
        self.assertFalse(result["proxy_details"]["app_ready"])
        self.assertEqual(result["predicted_class_score"], 0.8)

    def test_social_inputs_never_silently_fill_missing_counts(self):
        from schemas.vulnerability import APIS2022SocialInputs
        from pydantic import ValidationError
        self.assertEqual(APIS2022SocialInputs(answers={"G1_CODE1_COUNT": 0}).answers,
                         {"G1_CODE1_COUNT": 0})
        for wrong in ({"G1_CODE1_COUNT": 6}, {"G13_PHEALTH": 9}, {"I9A": "1"}):
            with self.subTest(wrong=wrong), self.assertRaises(ValidationError):
                APIS2022SocialInputs(answers=wrong)


if __name__ == "__main__": unittest.main()
