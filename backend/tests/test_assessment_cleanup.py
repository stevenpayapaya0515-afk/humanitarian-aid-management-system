"""Run from backend with PYTHONPATH set to backend: python -m unittest tests.test_assessment_cleanup"""
import unittest
from schemas.assessments import AssessmentCreate


class AssessmentCleanupTests(unittest.TestCase):
    def base(self):
        return {
            'household_id': 1,
            'assessment_date': '2026-11-14',
            'age_0_5_count': 1,
            'age_6_17_count': 0,
            'age_18_59_count': 2,
            'age_60_plus_count': 0,
            'senior_citizens_count': 0,
            'pwd_count': 0,
            'previous_humanitarian_assistance': False,
            'disaster_affected': False,
            'housing_damage_level': 'None',
            'displaced': False,
        }

    def test_new_form_no_synthetic_era_fields_required(self):
        a = AssessmentCreate(**self.base())
        for key in ('monthly_income_range', 'employment_status',
                    'livelihood_type', 'beneficiary_status'):
            self.assertIsNone(getattr(a, key))

    def test_old_saved_fields_remain_readable(self):
        a = AssessmentCreate(**self.base(), monthly_income_range='5000-9999',
                             employment_status='Employed',
                             livelihood_type='Farming', beneficiary_status='Pending')
        self.assertEqual(a.livelihood_type, 'Farming')

    def test_new_financials_remain_available(self):
        a = AssessmentCreate(**self.base(), financial_reference_year=2025,
                             financial_single_family=True, average_family_size='3',
                             annual_family_expenditure='1000', annual_food_expenditure='400',
                             annual_housing_utilities_expenditure='200',
                             annual_health_expenditure='0', annual_transport_expenditure='100',
                             financial_residence_classification='Rural')
        self.assertEqual(a.annual_family_expenditure, 1000)
        self.assertIsNone(a.annual_education_expenditure)


if __name__ == '__main__':
    unittest.main()
