"""Regression tests: detailed program selections never change model count meanings.

Run: python -m unittest tests.test_apis2022_program_selection_details -v
"""
import unittest

from pydantic import ValidationError
from schemas.assessments import AssessmentCreate


BASE = {
    "household_id": 8,
    "assessment_date": "2026-11-15",
    "age_0_5_count": 0,
    "age_6_17_count": 1,
    "age_18_59_count": 2,
    "age_60_plus_count": 0,
    "senior_citizens_count": 0,
}


class ProgramSelectionContractTests(unittest.TestCase):
    def _assessment(self, counts, selections):
        return AssessmentCreate.model_validate({
            **BASE,
            "apis2022_social_answers": counts,
            "apis2022_program_selections": selections,
        })

    def test_checked_programs_match_existing_model_counts(self):
        record = self._assessment(
            {"G1_CODE1_COUNT": 2, "G5_CODE1_COUNT": 0,
             "G9_CODE1_COUNT": 1, "G11_CODE1_COUNT": 0,
             "H1_CODE1_COUNT": 3},
            {"G1_CODE1_COUNT": [1, 4], "G5_CODE1_COUNT": [],
             "G9_CODE1_COUNT": [3], "G11_CODE1_COUNT": [],
             "H1_CODE1_COUNT": [1, 8, 12]},
        )
        self.assertEqual(record.apis2022_social_answers["G1_CODE1_COUNT"], 2)
        self.assertEqual(record.apis2022_program_selections["G1_CODE1_COUNT"], [1, 4])

    def test_previous_assessments_have_counts_without_fake_checkmarks(self):
        record = self._assessment({"G1_CODE1_COUNT": 2}, {})
        self.assertEqual(record.apis2022_social_answers["G1_CODE1_COUNT"], 2)
        self.assertEqual(record.apis2022_program_selections, {})

    def test_not_verified_does_not_become_zero(self):
        record = self._assessment({}, {})
        self.assertNotIn("G1_CODE1_COUNT", record.apis2022_social_answers)
        self.assertNotIn("G1_CODE1_COUNT", record.apis2022_program_selections)

    def test_zero_requires_explicit_empty_selection_list(self):
        record = self._assessment({"G1_CODE1_COUNT": 0}, {"G1_CODE1_COUNT": []})
        self.assertEqual(record.apis2022_program_selections["G1_CODE1_COUNT"], [])

    def test_wrong_total_is_rejected(self):
        with self.assertRaises(ValidationError):
            self._assessment({"G1_CODE1_COUNT": 1}, {"G1_CODE1_COUNT": [1, 2]})

    def test_bad_or_duplicate_codes_rejected(self):
        for selections in (
            {"G1_CODE1_COUNT": [1, 1]},
            {"G1_CODE1_COUNT": [6]},
            {"G1_CODE1_COUNT": [True]},
            {"UNKNOWN": [1]},
        ):
            with self.subTest(selections=selections):
                with self.assertRaises(ValidationError):
                    self._assessment({"G1_CODE1_COUNT": 1}, selections)


if __name__ == "__main__":
    unittest.main()
