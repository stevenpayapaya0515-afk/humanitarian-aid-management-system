"""Regression guard: current assessment code must not depend on retired DB columns.
Run: python -m unittest tests.test_assessment_schema_cleanup -v
"""
import unittest
from pathlib import Path
from routes import assessments
from schemas.assessments import AssessmentCreate

ROOT = Path(__file__).resolve().parents[2]
OBSOLETE = ('monthly_income_range',
    'employment_status',
    'livelihood_type',
    'previous_humanitarian_assistance',
    'housing_damage_level',
    'financial_reference_year',
    'financial_single_family',
    'average_family_size',
    'annual_family_income',
    'annual_family_expenditure',
    'annual_food_expenditure',
    'financial_residence_classification',
    'annual_housing_utilities_expenditure',
    'annual_health_expenditure',
    'annual_education_expenditure',
    'annual_transport_expenditure',
)


class AssessmentSchemaCleanupTests(unittest.TestCase):
    def test_no_legacy_columns_in_current_response_query_or_request(self):
        for column in OBSOLETE:
            with self.subTest(column=column):
                self.assertNotIn(column, AssessmentCreate.model_fields)
                self.assertNotIn('a.' + column, assessments.ASSESSMENT_SELECT)

    def test_model_income_and_social_protection_are_still_present(self):
        for column in ('apis2022_monthly_household_income_php',
                       'apis2022_extended_answers', 'apis2022_social_answers',
                       'apis2022_program_selections'):
            with self.subTest(column=column):
                self.assertIn(column, AssessmentCreate.model_fields)
                self.assertIn('a.' + column, assessments.ASSESSMENT_SELECT)

    def test_migration_is_guarded_and_has_no_cascade(self):
        sql = (ROOT / 'database' / '29_remove_unused_assessment_legacy_finance.sql').read_text()
        self.assertIn('LOCK TABLE public.household_assessments', sql)
        self.assertIn('RAISE EXCEPTION', sql)
        self.assertNotIn('DROP TABLE', sql)
        for column in OBSOLETE:
            self.assertIn('DROP COLUMN ' + column, sql)


if __name__ == '__main__':
    unittest.main()
