import unittest
from ml_service.label_apis2022 import label_row

class RubricTests(unittest.TestCase):
    def base(self):
        return dict(I2="1", I3="01", I4="1", I8="1", WS1="11", WS11A="12")

    def test_no_flags_low(self):
        self.assertEqual(label_row(self.base())["proxy_class"], "Low")

    def test_housing_counted_once(self):
        row = self.base() | dict(I2="7", I3="08", I4="6")
        self.assertEqual(label_row(row)["deprivation_count"], 1)

    def test_two_domains_high(self):
        self.assertEqual(label_row(self.base() | dict(I8="2", WS1="32"))["proxy_class"], "High")

    def test_unknown_never_low(self):
        self.assertEqual(label_row(self.base() | dict(WS11A="71"))["proxy_class"], "Needs review")
        self.assertEqual(label_row(self.base() | dict(I8=""))["proxy_class"], "Needs review")

    def test_alternative_cutoff(self):
        self.assertEqual(label_row(self.base() | dict(I8="2", WS1="32"), 3)["proxy_class"], "Medium")
