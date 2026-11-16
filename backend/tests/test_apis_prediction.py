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

class APIS2022AssessmentTests(unittest.TestCase):
    def test_saved_apis2022_inputs_validate_and_do_not_infer_missing(self):
        from pydantic import ValidationError
        base = dict(household_id=2, assessment_date='2026-11-15',
                    age_0_5_count=0, age_6_17_count=2, age_18_59_count=2,
                    age_60_plus_count=0, senior_citizens_count=0, pwd_count=0,
                    previous_humanitarian_assistance=False, disaster_affected=False,
                    housing_damage_level='None', displaced=False)
        raw = dict(apis_single_family=True, apis2022_i2=1, apis2022_i3=1,
                   apis2022_i4=1, apis2022_i8=1, apis2022_ws1=11,
                   apis2022_ws11a=12, apis2022_g15_kit=1,
                   apis2022_g16_nat_disas=2, apis2022_mem_age_6_11=1,
                   apis2022_mem_age_12_17=1,
                   apis2022_monthly_household_income_php='10000.00')
        saved = AssessmentCreate(**base, **raw)
        self.assertEqual(saved.apis2022_mem_age_12_17, 1)
        self.assertEqual(str(saved.apis2022_monthly_household_income_php), '10000.00')
        self.assertIsNone(AssessmentCreate(**base).apis2022_i2)
        for changes in [dict(apis2022_i3=9), dict(apis2022_i2=None),
                        dict(apis2022_mem_age_12_17=0),
                        dict(apis2022_g16_nat_disas=1),
                        dict(apis_single_family=False)]:
            with self.subTest(changes=changes), self.assertRaises(ValidationError):
                AssessmentCreate(**base, **(raw | changes))


class APIS2022OnlyFormTests(unittest.TestCase):
    def test_legacy_context_can_remain_unknown(self):
        assessment = AssessmentCreate.model_validate({
            "household_id": 1,
            "assessment_date": "2026-11-15",
            "age_0_5_count": 1,
            "age_6_17_count": 2,
            "age_18_59_count": 1,
            "age_60_plus_count": 0,
            "senior_citizens_count": 0,
            "data_origin": "lgu_authorized",
        })
        self.assertIsNone(assessment.pwd_count)
        self.assertNotIn('previous_humanitarian_assistance', AssessmentCreate.model_fields)
        self.assertIsNone(assessment.disaster_affected)
        self.assertNotIn('housing_damage_level', AssessmentCreate.model_fields)
        self.assertIsNone(assessment.displaced)


class CurrentIncomeContractTests(unittest.TestCase):
    """Current model income is independent of removed annual finance history."""

    def test_monthly_income_is_preserved_without_annual_history(self):
        data = AssessmentCreate(
            household_id=1, assessment_date='2026-11-14',
            age_0_5_count=0, age_6_17_count=0,
            age_18_59_count=2, age_60_plus_count=0,
            senior_citizens_count=0,
        )
        self.assertIsNone(data.apis2022_monthly_household_income_php)
        self.assertNotIn('annual_family_income', data.model_dump())


if __name__ == '__main__':
    unittest.main()
