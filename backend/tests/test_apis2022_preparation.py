import tempfile
import unittest
from pathlib import Path
import pandas as pd
from ml_service.prepare_apis2022 import read_table, require_unique, KEY


class PreparationTests(unittest.TestCase):
    def test_identifiers_and_unknowns_preserved(self):
        with tempfile.TemporaryDirectory() as tmp:
            p = Path(tmp) / "sample.csv"
            p.write_text("REG,HHID,I8\n16,00001,\n")
            frame = read_table(p)
            self.assertEqual(frame.iloc[0]["HHID"], "00001")
            self.assertEqual(frame.iloc[0]["I8"], "")

    def test_duplicate_household_rejected(self):
        frame = pd.DataFrame({"REG": ["16", "16"], "HHID": ["1", "1"]})
        with self.assertRaises(ValueError):
            require_unique(frame, KEY, "housing")

    def test_repeated_records_need_record_key(self):
        frame = pd.DataFrame({"REG": ["16", "16"], "HHID": ["1", "1"], "code": ["1", "2"]})
        require_unique(frame, KEY + ["code"], "assistance")
        with self.assertRaises(ValueError):
            require_unique(frame, KEY, "assistance")

    def test_blank_identifier_rejected(self):
        with tempfile.TemporaryDirectory() as tmp:
            p = Path(tmp) / "sample.csv"
            p.write_text("REG,HHID\n16,\n")
            with self.assertRaises(ValueError):
                read_table(p)


if __name__ == "__main__":
    unittest.main()
