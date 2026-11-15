import unittest
import pandas as pd
from ml_service.train_apis2022 import FEATURES, split_indices, validate_source
from ml_service.label_apis2022 import VERSION

class TrainingTests(unittest.TestCase):
    def test_sampling_groups_and_caraga_separate(self):
        f = pd.DataFrame([dict(REG=str(reg), HHID=str(i), RPSU=str(i//2))
                          for reg in (1, 16) for i in range(20)])
        a,b,c = split_indices(f)
        groups = f.REG + ":" + f.RPSU
        self.assertFalse(set(groups.iloc[a]) & set(groups.iloc[b]))
        self.assertTrue(f.iloc[c].REG.eq("16").all())
        self.assertTrue(f.iloc[a].REG.ne("16").all())
        self.assertEqual(len(a)+len(b)+len(c),len(f))

    def test_rejects_tampered_labels(self):
        row = dict(REG="1", HHID="0001", RPSU="1", label_version=VERSION,
                   I2="1", I3="01", I4="1", I8="1", WS1="11", WS11A="12", proxy_class="High")
        with self.assertRaises(ValueError):
            validate_source(pd.DataFrame([row]))
        row["proxy_class"] = "Low"
        self.assertEqual(len(validate_source(pd.DataFrame([row]))), 1)

    def test_target_and_identifiers_not_predictors(self):
        self.assertEqual(set(FEATURES), {"I2","I3","I4","I8","WS1","WS11A"})
