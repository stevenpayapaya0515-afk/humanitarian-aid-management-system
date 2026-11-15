"""Run from backend: python -m unittest discover -s tests -p test_apis_prediction.py"""
import unittest
from unittest.mock import patch
from schemas.assessments import AssessmentCreate
from pydantic import ValidationError

class HistoricalAssessmentTests(unittest.TestCase):
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

class FinancialAssessmentTests(unittest.TestCase):
    def setUp(self):
        self.base = dict(household_id=1, assessment_date='2026-11-14',
            age_0_5_count=0, age_6_17_count=1, age_18_59_count=2, age_60_plus_count=0,
            senior_citizens_count=0, pwd_count=0, monthly_income_range='Below 5000',
            employment_status='Employed', livelihood_type='Salaried employment',
            previous_humanitarian_assistance=False, beneficiary_status='Pending',
            disaster_affected=False, housing_damage_level='None', displaced=False)
        self.finance = dict(financial_reference_year=2025, financial_single_family=True,
            average_family_size='3.50', annual_family_income='100000.25',
            annual_family_expenditure='120000', annual_food_expenditure='50000')

    def test_legacy_and_unknown_amounts_remain_null(self):
        self.assertIsNone(AssessmentCreate(**self.base).annual_family_income)
        record = AssessmentCreate(**self.base, **(self.finance | {'annual_family_income': None}))
        self.assertIsNone(record.annual_family_income)
        self.assertEqual(str(record.average_family_size), '3.50')

    def test_zero_and_negative_net_income_preserved(self):
        for amount in ['0', '-100.25']:
            record = AssessmentCreate(**self.base, **(self.finance | {'annual_family_income': amount}))
            self.assertEqual(str(record.annual_family_income), amount)

    def test_invalid_financial_history_rejected(self):
        cases = [dict(financial_reference_year=2026), dict(financial_reference_year=None),
            dict(financial_reference_year=True), dict(financial_single_family=False),
            dict(financial_single_family=None), dict(average_family_size=None),
            dict(average_family_size=0), dict(annual_family_income='NaN'),
            dict(annual_family_expenditure='Infinity'), dict(annual_food_expenditure=-1),
            dict(annual_food_expenditure='120000.01'), dict(annual_family_income='1.123'),
            dict(annual_family_income=None, annual_family_expenditure=None, annual_food_expenditure=None)]
        for change in cases:
            with self.subTest(change=change), self.assertRaises(ValidationError):
                AssessmentCreate(**self.base, **(self.finance | change))

    def test_detailed_finance_preserves_unknown_and_zero(self):
        data = AssessmentCreate(**self.base, **self.finance,
            financial_residence_classification="Rural", annual_health_expenditure="0",
            annual_housing_utilities_expenditure="20000", annual_transport_expenditure="10000")
        self.assertEqual(str(data.annual_health_expenditure), "0")
        self.assertIsNone(data.annual_education_expenditure)
        self.assertIsNone(AssessmentCreate(**self.base).financial_residence_classification)

    def test_detailed_expense_totals_and_context(self):
        changes = [
            {"annual_health_expenditure": "-1"},
            {"annual_health_expenditure": "NaN"},
            {"annual_health_expenditure": "Infinity"},
            {"annual_health_expenditure": "1.123"},
            {"annual_health_expenditure": "1", "annual_family_expenditure": None},
            {"annual_housing_utilities_expenditure": "60000", "annual_transport_expenditure": "10000.01"},
            {"financial_residence_classification": "Unknown"},
            {"financial_residence_classification": 1},
            {"financial_residence_classification": "Urban", "financial_reference_year": None},
        ]
        for change in changes:
            with self.subTest(change=change), self.assertRaises(ValidationError):
                AssessmentCreate(**self.base, **(self.finance | change))
        # Exact boundary: known components add to the total, not beyond it.
        AssessmentCreate(**self.base, **self.finance,
            annual_housing_utilities_expenditure="60000", annual_transport_expenditure="10000")
        with self.assertRaises(ValidationError):
            AssessmentCreate(**self.base, annual_health_expenditure="0")

    def test_response_reads_legacy_and_new_fields(self):
        from schemas.assessments import AssessmentResponse
        metadata = dict(assessment_id=1, household_head="Test", barangay="Test",
                        recorded_by=1, created_at="2026-11-14T00:00:00Z")
        legacy = AssessmentResponse(**self.base, **metadata)
        self.assertIsNone(legacy.annual_transport_expenditure)
        updated = AssessmentResponse(**self.base, **metadata, **self.finance,
                                     financial_residence_classification="Urban",
                                     annual_transport_expenditure="10.25")
        self.assertEqual(str(updated.annual_transport_expenditure), "10.25")

if __name__ == '__main__':
    unittest.main()
