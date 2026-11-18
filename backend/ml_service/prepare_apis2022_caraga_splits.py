"""Export and verify the exact historical APIS 2022 CARAGA train/test/review sets.
From backend/: python -m ml_service.prepare_apis2022_caraga_splits
"""
from __future__ import annotations

import argparse
import csv
from pathlib import Path

import pandas as pd

from .train_apis2022_vulnerability import (
    DATASET_PATH, ML_DIR, AUDIT_COLUMNS, FEATURES,
    original_caraga_partition, read_dataset,
)

DATASETS_DIR = ML_DIR / "datasets"
LABELS_PATH = DATASETS_DIR / "apis2022_caraga_vulnerability_proxy_labels.csv"
SPLITS_DIR = DATASETS_DIR / "splits"
TRAIN_PATH = SPLITS_DIR / "train2022_caraga_dataset.csv"
TEST_PATH = SPLITS_DIR / "test2022_caraga_dataset.csv"
EXCLUDED_PATH = SPLITS_DIR / "excluded2022_caraga_dataset.csv"
LABEL_COLUMNS = ["proxy_score", "proxy_class"]
PROXY_COLUMNS = ["region_code", "household_id", *LABEL_COLUMNS]


def _score(value: object) -> str:
    return "" if pd.isna(value) else str(int(value))


def _rows(frame: pd.DataFrame, labels: pd.DataFrame, indices, columns: list[str]):
    for i in indices:
        source = frame.iloc[int(i)]
        label = labels.iloc[int(i)]
        row = {
            **source.to_dict(),
            "proxy_score": _score(label["proxy_score"]),
            "proxy_class": str(label["proxy_class"]),
        }
        yield [row[name] for name in columns]


def _write(path: Path, columns: list[str], rows) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8-sig", newline="") as stream:
        writer = csv.writer(stream, lineterminator="\n")
        writer.writerow(columns)
        writer.writerows(rows)


def _verify_file(path: Path, columns: list[str], expected_rows) -> int:
    if not path.is_file():
        raise FileNotFoundError(f"Missing prepared CARAGA file: {path.name}. Run the split exporter.")
    with path.open(encoding="utf-8-sig", newline="") as stream:
        reader = csv.reader(stream)
        if next(reader, None) != columns:
            raise ValueError(f"Unexpected columns in {path.name}")
        count = 0
        for count, expected in enumerate(expected_rows, start=1):
            actual = next(reader, None)
            if actual != expected:
                raise ValueError(f"Saved CARAGA data differs at {path.name}, row {count}")
        if next(reader, None) is not None:
            raise ValueError(f"Extra household rows found in {path.name}")
    return count


def verify_saved_partitions(
    frame: pd.DataFrame,
    labels: pd.DataFrame,
    train_idx,
    test_idx,
    excluded_idx,
) -> dict[str, int]:
    """Refuse mismatched/overlapping splits before training (including proxy targets)."""
    master_columns = frame.columns.tolist()
    if set(master_columns) != set(FEATURES + AUDIT_COLUMNS):
        raise ValueError("CARAGA master CSV feature schema has changed")
    all_indices = range(len(frame))
    plan = (
        (LABELS_PATH, PROXY_COLUMNS, all_indices),
        (TRAIN_PATH, master_columns + LABEL_COLUMNS, train_idx),
        (TEST_PATH, master_columns + LABEL_COLUMNS, test_idx),
        (EXCLUDED_PATH, master_columns + LABEL_COLUMNS, excluded_idx),
    )
    counts = {}
    for path, columns, indices in plan:
        count = _verify_file(path, columns, _rows(frame, labels, indices, columns))
        counts[path.name] = count
    return counts


def export_caraga_splits(master_path: Path = DATASET_PATH) -> dict:
    frame = read_dataset(master_path)
    cutoff, labels, train_idx, test_idx, excluded_idx = original_caraga_partition(frame)
    master_columns = frame.columns.tolist()
    plan = (
        (LABELS_PATH, PROXY_COLUMNS, range(len(frame))),
        (TRAIN_PATH, master_columns + LABEL_COLUMNS, train_idx),
        (TEST_PATH, master_columns + LABEL_COLUMNS, test_idx),
        (EXCLUDED_PATH, master_columns + LABEL_COLUMNS, excluded_idx),
    )
    for path, cols, indices in plan:
        _write(path, cols, _rows(frame, labels, indices, cols))
    counts = verify_saved_partitions(frame, labels, train_idx, test_idx, excluded_idx)
    if counts[TRAIN_PATH.name] + counts[TEST_PATH.name] + counts[EXCLUDED_PATH.name] != len(frame):
        raise ValueError("Prepared CARAGA split sizes do not cover all households")
    return {
        "households": len(frame),
        "train": len(train_idx),
        "test": len(test_idx),
        "excluded": len(excluded_idx),
        "income_cutoff": cutoff,
        "train_classes": labels.iloc[train_idx]["proxy_class"].value_counts().to_dict(),
        "test_classes": labels.iloc[test_idx]["proxy_class"].value_counts().to_dict(),
        "files": counts,
    }


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--master", type=Path, default=DATASET_PATH)
    args = parser.parse_args()
    result = export_caraga_splits(args.master)
    print("CARAGA households:", result["households"])
    print("Training:", result["train"], result["train_classes"])
    print("Testing:", result["test"], result["test_classes"])
    print("Excluded (Needs review):", result["excluded"])
    print("Income cutoff (from raw training portion):", result["income_cutoff"])
    print("PASS: Saved proxy labels and all three splits match the CARAGA master CSV.")
    print("No model was retrained or modified.")


if __name__ == "__main__":
    main()
