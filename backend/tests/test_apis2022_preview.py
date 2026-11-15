"""Run from backend: python -m unittest tests.test_apis2022_preview -v"""
import unittest
from decimal import Decimal
from unittest.mock import patch
from schemas.vulnerability import APIS2022ResearchPreviewRequest
from ml_service.predict_apis2022_vulnerability import (
    predict_research_preview, ResearchPreviewNeedsReview,
)


def example():
    return dict(I2=1, I3=1, I4=1, I8=1, WS1=11, WS11A=12,
                G15_KIT=1, G16_NAT_DISAS=2,
                G16A_EVAC=None, G16B_RECOV=None,
                MEM_AGE_0_5=0, MEM_AGE_6_11=1,
                MEM_AGE_12_17=1, MEM_AGE_18_59=2,
                MEM_AGE_60_PLUS=0,
                monthly_household_income_php=Decimal('20000.00'))


class ResearchPreviewContractTests(unittest.TestCase):
    ages = dict(age_0_5_count=0, age_6_17_count=2,
                age_18_59_count=2, age_60_plus_count=0)

    def test_request_catches_unknown_codes(self):
        with self.assertRaises(ValueError):
            APIS2022ResearchPreviewRequest(**{**example(), 'I3': 999})

    def test_request_requires_disaster_followups(self):
        with self.assertRaises(ValueError):
            APIS2022ResearchPreviewRequest(**{**example(), 'G16_NAT_DISAS': 1})

    def test_request_rejects_skipped_disaster_answers_as_no(self):
        with self.assertRaises(ValueError):
            APIS2022ResearchPreviewRequest(**{**example(), 'G16A_EVAC': 2})

    def test_rejects_member_ages_that_disagree_with_registration(self):
        with self.assertRaises(ResearchPreviewNeedsReview):
            predict_research_preview(example(), household_size=5, recorded_age_counts=self.ages)

    def test_rejects_member_ages_that_disagree_with_saved_assessment(self):
        with self.assertRaises(ResearchPreviewNeedsReview):
            predict_research_preview(example(), household_size=4, recorded_age_counts={**self.ages,'age_6_17_count':1})

    def test_rejects_missing_monthly_income(self):
        with self.assertRaises(ResearchPreviewNeedsReview):
            predict_research_preview({**example(),'monthly_household_income_php':None}, household_size=4, recorded_age_counts=self.ages)

    def test_pipeline_preview_is_non_persisting(self):
        class StubPipeline:
            classes_ = ['Low','Medium','High']
            def predict(self, frame):
                assert frame.columns.tolist() == [
                    'I2','I3','I4','I8','WS1','WS11A','G15_KIT',
                    'G16_NAT_DISAS','G16A_EVAC','G16B_RECOV',
                    'FSIZE','MEM_AGE_0_5','MEM_AGE_6_11','MEM_AGE_12_17',
                    'MEM_AGE_60_PLUS','K5_PER_CAPITA']
                assert frame.iloc[0]['I3'] == '01'  # APIS zero-padded code
                return ['Low']
            def predict_proba(self, frame):
                return [[.9,.08,.02]]
        bundle={'pipeline':StubPipeline(),'income_cutoff':2500,
                'version':'research-v1','label_version':'proxy-v1'}
        with patch('ml_service.predict_apis2022_vulnerability.load_candidate',return_value=bundle):
            result = predict_research_preview(example(), household_size=4, recorded_age_counts=self.ages)
        self.assertEqual(result['predicted_class'],'Low')
        self.assertTrue(result['preview_only'])
        self.assertFalse(result['app_ready'])
        self.assertTrue(result['requires_staff_review'])
        self.assertEqual(result['proxy_rule_class'],'Medium')


if __name__ == '__main__':
    unittest.main()
