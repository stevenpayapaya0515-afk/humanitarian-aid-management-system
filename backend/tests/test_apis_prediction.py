"""Run from backend: python -m unittest discover -s tests -p test_apis_prediction.py"""
import unittest
from unittest.mock import patch
from ml_service import predict
from schemas.assessments import AssessmentCreate
from pydantic import ValidationError

class Model:
    classes_ = ['High', 'Low', 'Medium']
    def predict(self, frame):
        assert list(frame.columns) == predict.FEATURES
        return ['Medium']
    def predict_proba(self, frame):
        return [[0.1, 0.2, 0.7]]

class APISPredictionTests(unittest.TestCase):
    def setUp(self):
        self.answers = dict(roof_material=1, wall_material=1, electricity=1,
            drinking_water_source=11, toilet_facility=12, working_adult_present=1,
            apis_single_family=True)

    def test_unknown_or_legacy_requires_review_before_loading_model(self):
        for bad in [None, True, '1', 99]:
            with self.subTest(value=bad), patch.object(predict, 'load_model') as loader:
                with self.assertRaises(predict.AssessmentNeedsReview):
                    predict.predict_vulnerability({**self.answers, 'electricity': bad})
                loader.assert_not_called()
        with self.assertRaises(predict.AssessmentNeedsReview):
            predict.predict_vulnerability({})

    def test_multi_family_is_not_silently_classified(self):
        with self.assertRaises(predict.AssessmentNeedsReview):
            predict.predict_vulnerability({**self.answers, 'apis_single_family': False})

    def test_actual_model_output_and_rule_disagreement_are_preserved(self):
        with patch.object(predict, 'load_model', return_value=Model()):
            result = predict.predict_vulnerability(self.answers)
        self.assertEqual(result['predicted_class'], 'Medium')
        self.assertEqual(result['predicted_class_score'], .7)
        self.assertEqual(result['proxy_details']['rule_class'], 'Low')
        self.assertFalse(result['proxy_details']['model_agrees_with_rules'])
        self.assertEqual(result['model_training_data_origin'], 'psa_apis2019')

    def test_schema_rejects_invalid_code_and_impossible_working_adult(self):
        base = dict(household_id=1, assessment_date='2026-11-13', age_0_5_count=1,
            age_6_17_count=0, age_18_59_count=0, age_60_plus_count=0,
            senior_citizens_count=0, pwd_count=0, monthly_income_range='Below 5000',
            employment_status='Other', livelihood_type='Other',
            previous_humanitarian_assistance=False, beneficiary_status='Pending',
            disaster_affected=False, housing_damage_level='None', displaced=False)
        AssessmentCreate(**base)  # old records still readable
        for extra in [dict(electricity=True), dict(electricity=99), dict(working_adult_present=1)]:
            with self.subTest(extra=extra), self.assertRaises(ValidationError):
                AssessmentCreate(**base, **extra)

if __name__ == '__main__':
    unittest.main()
