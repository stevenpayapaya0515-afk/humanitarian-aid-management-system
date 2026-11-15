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

    def test_preview_still_writes_nothing(self):
        response, calls = self.call(answers(), path="preview-apis2022")
        self.assertEqual(response.status_code, 200, response.text)
        self.assertTrue(response.json()["preview_only"])
        self.assertFalse(any("INSERT" in sql for sql, args in calls))

    def test_missing_and_invalid_answers_rejected_before_database(self):
        for payload in [None, {}, dict(answers(), I3=999), dict(answers(), MEM_AGE_0_5=True)]:
            response, calls = self.call(payload)
            self.assertEqual(response.status_code, 422, response.text)
            self.assertEqual(calls, [])

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


if __name__ == "__main__": unittest.main()
