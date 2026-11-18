"""Regression tests for the fixed APIS 2022 CARAGA dataset partition.

Run from backend/: python -m unittest tests.test_apis2022_caraga_splits -v
"""
import csv
import unittest
from pathlib import Path
from tempfile import TemporaryDirectory
from unittest.mock import patch

from ml_service.train_apis2022_vulnerability import (
    DATASET_PATH, original_caraga_partition, read_dataset,
)
from ml_service import prepare_apis2022_caraga_splits as splits


class CaragaDatasetSplitTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.master = read_dataset(DATASET_PATH)
        cls.cutoff, cls.labels, cls.train_idx, cls.test_idx, cls.excluded_idx = (
            original_caraga_partition(cls.master)
        )

    def test_original_counts_and_training_cutoff(self):
        self.assertEqual(len(self.master), 2126)
        self.assertEqual((len(self.train_idx), len(self.test_idx), len(self.excluded_idx)),
                         (1609, 412, 105))
        self.assertAlmostEqual(self.cutoff, 1923.5833335, places=6)
        self.assertEqual(self.labels.iloc[self.excluded_idx]["proxy_class"].unique().tolist(),
                         ["Needs review"])

    def test_no_household_overlap_or_lost_records(self):
        all_ids = set(self.master["household_id"])
        partitions = [set(self.master.iloc[idx]["household_id"])
                      for idx in (self.train_idx, self.test_idx, self.excluded_idx)]
        self.assertTrue(partitions[0].isdisjoint(partitions[1]))
        self.assertTrue(partitions[0].isdisjoint(partitions[2]))
        self.assertTrue(partitions[1].isdisjoint(partitions[2]))
        self.assertEqual(set.union(*partitions), all_ids)
        self.assertTrue(self.master["household_id"].str.match(r"^\d+$").all())

    def test_saved_csvs_match_original_records(self):
        counts = splits.verify_saved_partitions(
            self.master, self.labels, self.train_idx, self.test_idx,
            self.excluded_idx,
        )
        self.assertEqual(counts[splits.TRAIN_PATH.name], 1609)
        self.assertEqual(counts[splits.TEST_PATH.name], 412)
        self.assertEqual(counts[splits.EXCLUDED_PATH.name], 105)
        self.assertEqual(counts[splits.LABELS_PATH.name], 2126)

    def test_mutated_saved_split_is_rejected(self):
        with TemporaryDirectory() as directory:
            fake = Path(directory) / "bad_train.csv"
            with splits.TRAIN_PATH.open(encoding="utf-8-sig", newline="") as f:
                rows = list(csv.reader(f))
            rows[1][1] = "99999"  # household_id must match the master
            with fake.open("w", encoding="utf-8-sig", newline="") as f:
                writer = csv.writer(f)
                writer.writerows(rows)
            with patch.object(splits, "TRAIN_PATH", fake):
                with self.assertRaisesRegex(ValueError, "differs"):
                    splits.verify_saved_partitions(
                        self.master, self.labels, self.train_idx,
                        self.test_idx, self.excluded_idx,
                    )


if __name__ == "__main__":
    unittest.main()
