import unittest
from unittest.mock import patch
from ml_service.predict_apis2022 import prepare_answers, predict_candidate, NeedsReview, FEATURES

class AdapterTests(unittest.TestCase):
    def answers(self):
        return dict(survey_version="APIS2022", single_family=True,
                    I2=1, I3=1, I4=1, I8=1, WS1=11, WS11A=12)

    def test_legacy_codes_not_implicitly_accepted(self):
        with self.assertRaises(NeedsReview):
            prepare_answers(self.answers() | {"survey_version": "APIS2019"})

    def test_unknown_bool_and_text_rejected(self):
        for bad in [None, True, "1", 8]:
            with self.subTest(bad=bad), self.assertRaises(NeedsReview):
                prepare_answers(self.answers() | {"I2": bad})

    def test_multiple_families_require_review(self):
        with self.assertRaises(NeedsReview):
            prepare_answers(self.answers() | {"single_family": False})

    def test_invalid_answers_do_not_load_model(self):
        with patch("ml_service.predict_apis2022.load_model") as loader:
            with self.assertRaises(NeedsReview):
                predict_candidate(self.answers() | {"WS11A": 96})
            loader.assert_not_called()

    def test_disagreement_and_review_preserved(self):
        class Fake:
            classes_ = ["High", "Low", "Medium"]
            def predict(self, frame):
                assert list(frame.columns) == FEATURES
                assert frame.iloc[0]["I3"] == "1"
                return ["Medium"]
            def predict_proba(self, frame):
                return [[.1, .2, .7]]
        with patch("ml_service.predict_apis2022.load_model", return_value=Fake()):
            result = predict_candidate(self.answers())
        self.assertEqual(result["rule_class"], "Low")
        self.assertFalse(result["model_agrees_with_rules"])
        self.assertTrue(result["requires_staff_review"])
        self.assertEqual(result["predicted_class_score"], .7)
