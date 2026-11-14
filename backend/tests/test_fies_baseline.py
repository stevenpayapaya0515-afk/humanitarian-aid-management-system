"""Boundary tests for FIES financial categories; no database needed."""
import unittest
from ml_service.build_fies_baseline import classify_income, FEATURES, threshold_area, NCR_DISTRICTS, choose_candidate, validation_split


class FiesLabelTests(unittest.TestCase):
    def test_documented_ncr_districts(self):
        self.assertEqual(len(NCR_DISTRICTS), 17)
        self.assertEqual(threshold_area(806, "CITY OF MANILA", 13), "1st District")
        self.assertEqual(threshold_area(813, "QUEZON CITY", 13), "2nd District")
        self.assertEqual(threshold_area(801, "CITY OF CALOOCAN", 13), "3rd District")
        self.assertEqual(threshold_area(815, "CITY OF TAGUIG", 13), "4th District")

    def test_region_mismatch_rejected(self):
        with self.assertRaises(ValueError):
            threshold_area(806, "CITY OF MANILA", 16)

    def test_unmapped_city_not_guessed(self):
        self.assertEqual(threshold_area(304, "City of Butuan", 16), "City of Butuan")
        self.assertEqual(threshold_area(2, "Agusan del Norte", 16), "Agusan del Norte")

    def test_selection_rejects_recall_collapse(self):
        def result(name, f1, high, medium):
            return {"name": name, "metrics": {"macro_f1": f1,
                    "classification_report": {"High": {"recall": high},
                                              "Medium": {"recall": medium}}}}
        rows = [result("baseline", .60, .80, .70),
                result("misleading_f1", .90, .50, .70),
                result("improvement", .65, .78, .65)]
        chosen, rule = choose_candidate(rows)
        self.assertEqual(chosen["name"], "improvement")
        self.assertNotIn("misleading_f1", rule["eligible_candidates"])

    def test_validation_keeps_groups_together(self):
        import pandas as pd
        rows = [{"sample_group": str(g), "proxy_class": label}
                for g in range(30) for label in ["Low", "Medium", "High"]]
        data = pd.DataFrame(rows)
        fit, validation = validation_split(data)
        self.assertFalse(set(fit.sample_group) & set(validation.sample_group))
        self.assertEqual(len(fit) + len(validation), len(data))

    def test_threshold_boundaries(self):
        self.assertEqual(classify_income(99, 100, 150), "High")
        self.assertEqual(classify_income(100, 100, 150), "Medium")
        self.assertEqual(classify_income(149, 100, 150), "Medium")
        self.assertEqual(classify_income(150, 100, 150), "Low")

    def test_negative_net_income(self):
        self.assertEqual(classify_income(-1, 100, 150), "High")

    def test_invalid_thresholds_and_missing_income(self):
        for args in [(1, 150, 100), (1, 0, 100), (float("nan"), 100, 150), (float("inf"), 100, 150)]:
            with self.subTest(args=args), self.assertRaises(ValueError):
                classify_income(*args)

    def test_income_and_target_not_predictors(self):
        forbidden = {"TOINC", "PERCAPITA", "WAGES", "NPCINC", "proxy_class", "food_threshold", "poverty_threshold"}
        self.assertFalse(forbidden.intersection(FEATURES))


if __name__ == "__main__":
    unittest.main()
