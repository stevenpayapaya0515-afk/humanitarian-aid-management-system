"""Boundary tests for FIES financial categories; no database needed."""
import unittest
from ml_service.build_fies_baseline import classify_income, FEATURES


class FiesLabelTests(unittest.TestCase):
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
