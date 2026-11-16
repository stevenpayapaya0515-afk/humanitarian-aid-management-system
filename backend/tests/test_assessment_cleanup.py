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

    def test_obsolete_legacy_and_finance_fields_are_removed(self):
        data = AssessmentCreate(**self.base())
        for key in ('monthly_income_range', 'employment_status', 'livelihood_type', 'previous_humanitarian_assistance', 'housing_damage_level',
                    'financial_reference_year', 'annual_family_income',
                    'annual_family_expenditure', 'annual_food_expenditure',
                    'annual_health_expenditure', 'annual_education_expenditure'):
            with self.subTest(column=key):
                self.assertNotIn(key, AssessmentCreate.model_fields)
                self.assertNotIn(key, data.model_dump())

    def test_current_income_and_social_answers_remain_supported(self):
        data = AssessmentCreate(**self.base())
        self.assertIn('apis2022_monthly_household_income_php', data.model_dump())
        self.assertIn('apis2022_social_answers', data.model_dump())
        self.assertIn('apis2022_program_selections', data.model_dump())


if __name__ == '__main__':
    unittest.main()


class HouseholdRegistrationAlignmentTests(unittest.TestCase):
    def test_head_and_member_names_define_household_size(self):
        from schemas.households import (HouseholdCreate, registered_member_count,
                                        registration_matches_size)
        body = dict(household_head="Household Head", barangay="Dos",
                    address="Sample address", household_size=3,
                    household_member=" Member One\r\n\r\n Member Two  ")
        registered = HouseholdCreate(**body)
        self.assertEqual(registered.household_member, "Member One\nMember Two")
        self.assertEqual(registered_member_count(registered.household_member), 2)
        self.assertTrue(registration_matches_size(3, registered.household_member))
        self.assertFalse(registration_matches_size(4, registered.household_member))

    def test_incomplete_household_registration_is_rejected(self):
        from schemas.households import HouseholdCreate
        from pydantic import ValidationError
        with self.assertRaises(ValidationError):
            HouseholdCreate(household_head="Head", barangay="Dos",
                            address="Sample", household_size=4,
                            household_member="Member One\nMember Two")

    def test_single_person_household_has_zero_other_members(self):
        from schemas.households import HouseholdCreate
        record = HouseholdCreate(household_head="Head", barangay="Dos",
                                 address="Sample", household_size=1)
        self.assertEqual(record.household_member, "")
