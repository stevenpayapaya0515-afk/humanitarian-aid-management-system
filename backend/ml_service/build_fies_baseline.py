"""Build an offline FIES 2025 financial proxy; never modifies the app or database.
Run: python -m ml_service.build_fies_baseline --zip PATH --thresholds PATH
Only exact province matches and documented spelling aliases are accepted.
HUCs and other unmatched domains are excluded and listed, never silently guessed.
"""
import argparse
import hashlib
import io
import json
from pathlib import Path
import zipfile

import joblib
import numpy as np
import openpyxl
import pandas as pd
import sklearn
from sklearn.ensemble import RandomForestClassifier
from sklearn.dummy import DummyClassifier
from sklearn.metrics import classification_report, confusion_matrix, balanced_accuracy_score
from sklearn.model_selection import GroupShuffleSplit

VERSION = "fies2025-financial-proxy-v1"
CLASSES = ["Low", "Medium", "High"]
# No income, income components, deciles, survey weights or identifiers as predictors.
FEATURES = ["average_family_size", "food_per_person", "nonfood_per_person"]
ALIASES = {"Mountain Province": "Mt. Province", "Samar (Western)": "Samar",
           "Compostela Valley": "Davao de Oro", "North Cotabato": "Cotabato",
           "Dinagat Island": "Dinagat Islands", "City of Isabela": "Isabela City"}


def classify_income(income, food, poverty):
    if not (np.isfinite([income, food, poverty]).all() and 0 < food < poverty):
        raise ValueError("Invalid income or thresholds")
    return "High" if income < food else "Medium" if income < poverty else "Low"


def prepare(zip_path, threshold_path):
    with zipfile.ZipFile(zip_path) as archive:
        csv_names = [n for n in archive.namelist() if n.endswith("FIES_PUF_2025_Volume1.CSV")]
        dictionaries = [n for n in archive.namelist() if n.endswith("fies_2025_vol1_metadata(dictionary).xlsx")]
        if len(csv_names) != 1 or len(dictionaries) != 1:
            raise ValueError("Expected the FIES 2025 Volume 1 PUF ZIP and dictionary")
        frame = pd.read_csv(io.BytesIO(archive.read(csv_names[0])), dtype=str)
        book = openpyxl.load_workbook(io.BytesIO(archive.read(dictionaries[0])), read_only=True, data_only=True)
        names = {}; active = False
        for row in book.worksheets[1].values:
            if row[0]:
                active = row[0] == "W_PROV_VS21"
            if active and row[2] is not None and row[3] is not None:
                names[int(row[3])] = str(row[2]).strip()
        book.close()
    frame = frame.apply(lambda column: column.str.strip())
    numeric = ["W_PROV", "W_REGN", "URBAN", "FSIZE", "TOINC", "PERCAPITA", "TOTEX", "FOOD", "RFACT"]
    for col in numeric:
        frame[col] = pd.to_numeric(frame[col], errors="raise")
    if frame[["W_REGN", "W_PROV", "SEQNO"]].duplicated().any():
        raise ValueError("Duplicate survey record identifiers")
    if frame[["RPSU", "SEQNO"]].isna().any().any():
        raise ValueError("Missing sample identifiers")
    book = openpyxl.load_workbook(threshold_path, read_only=True, data_only=True)
    sheet = book["tab16"]
    if "2025" not in str(sheet.cell(1, 1).value) or any(sheet.cell(5, c).value != 2025 for c in (4, 7, 10, 13)):
        raise ValueError("Unexpected Table 16 layout or threshold year")
    thresholds = {}
    for number, row in enumerate(sheet.values, 1):
        if number < 7 or not row[0]:
            continue
        for urban, fidx, pidx in [(1, 3, 9), (2, 6, 12)]:
            if isinstance(row[fidx], (float, int)) and isinstance(row[pidx], (float, int)):
                thresholds[(str(row[0]).strip(), urban)] = (float(row[fidx]), float(row[pidx]), number)
    book.close()
    frame["province_name"] = frame.W_PROV.map(names)
    frame["threshold_area"] = frame.province_name.replace(ALIASES)
    matched = [thresholds.get((name, urban)) for name, urban in zip(frame.threshold_area, frame.URBAN)]
    frame["food_threshold"] = [t[0] if t else np.nan for t in matched]
    frame["poverty_threshold"] = [t[1] if t else np.nan for t in matched]
    frame["threshold_sheet_row"] = [t[2] if t else np.nan for t in matched]
    frame["exclusion_reason"] = ""
    missing = frame.food_threshold.isna()
    frame.loc[missing, "exclusion_reason"] = "No verified province/urban-rural threshold mapping"
    valid = np.isfinite(frame[numeric]).all(axis=1) & (frame.FSIZE >= 1) & (frame.FOOD >= 0) & (frame.TOTEX >= frame.FOOD) & (frame.RFACT > 0)
    frame.loc[~valid, "exclusion_reason"] = "Invalid or missing financial values"
    # Released income can be rounded; allow at most one peso difference per person.
    difference = (frame.TOINC / frame.FSIZE - frame.PERCAPITA).abs()
    frame.loc[difference > 1, "exclusion_reason"] = "Per-capita income does not reconcile within PHP 1"
    frame["proxy_class"] = "Needs review"
    usable = frame.exclusion_reason.eq("")
    frame.loc[usable, "proxy_class"] = [classify_income(i, f, p) for i, f, p in zip(frame.loc[usable, "PERCAPITA"], frame.loc[usable, "food_threshold"], frame.loc[usable, "poverty_threshold"])]
    frame["average_family_size"] = frame.FSIZE
    frame["food_per_person"] = frame.FOOD / frame.FSIZE
    frame["nonfood_per_person"] = (frame.TOTEX - frame.FOOD) / frame.FSIZE
    # Keep whole PSUs together; location prefixes prevent cross-province code collisions.
    frame["sample_group"] = frame.W_REGN.astype(str) + ":" + frame.W_PROV.astype(str) + ":" + frame.RPSU
    return frame


def evaluate(model, frame):
    if frame.empty:
        return {"records": 0}
    truth = frame.proxy_class
    pred = model.predict(frame[FEATURES])
    report = classification_report(truth, pred, labels=CLASSES, output_dict=True, zero_division=0)
    return {"records": len(frame), "class_counts": truth.value_counts().to_dict(),
            "balanced_accuracy": float(balanced_accuracy_score(truth, pred)),
            "macro_f1": report["macro avg"]["f1-score"], "classification_report": report,
            "confusion_matrix_order": CLASSES,
            "confusion_matrix": confusion_matrix(truth, pred, labels=CLASSES).tolist()}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--zip", type=Path, required=True)
    parser.add_argument("--thresholds", type=Path, required=True)
    parser.add_argument("--output-root", type=Path, default=Path(__file__).resolve().parent)
    args = parser.parse_args()
    frame = prepare(args.zip, args.thresholds)
    usable = frame[frame.exclusion_reason.eq("")].copy()
    rest = usable[usable.W_REGN != 16]
    caraga = usable[usable.W_REGN == 16]
    split = GroupShuffleSplit(n_splits=1, test_size=.2, random_state=42)
    train_indices, test_indices = next(split.split(rest, groups=rest.sample_group))
    train, test = rest.iloc[train_indices], rest.iloc[test_indices]
    if set(train.proxy_class) != set(CLASSES) or set(test.proxy_class) != set(CLASSES):
        raise ValueError("All three classes must occur in training and holdout")
    assert not set(train.sample_group) & set(test.sample_group)
    frame["split"] = "excluded"
    frame.loc[train.index, "split"] = "train"
    frame.loc[test.index, "split"] = "test_non_caraga"
    frame.loc[caraga.index, "split"] = "test_caraga"
    model = RandomForestClassifier(n_estimators=200, min_samples_leaf=10,
                                   class_weight="balanced_subsample", random_state=42, n_jobs=2)
    model.fit(train[FEATURES], train.proxy_class)
    dummy = DummyClassifier(strategy="most_frequent").fit(train[FEATURES], train.proxy_class)
    excluded = frame[~frame.exclusion_reason.eq("")]
    report = {"version": VERSION, "status": "offline research candidate; not connected to app",
              "source": "PSA FIES 2025 Volume 1 PUF", "threshold_source": "2025 official poverty workbook, tab16",
              "source_sha256": hashlib.sha256(args.zip.read_bytes()).hexdigest(),
              "threshold_sha256": hashlib.sha256(args.thresholds.read_bytes()).hexdigest(),
              "records_total": len(frame), "records_usable": len(usable), "training_records": len(train),
              "excluded_records": len(excluded),
              "excluded_domains": excluded.groupby(["W_PROV", "province_name", "exclusion_reason"], dropna=False).size().reset_index(name="records").to_dict("records"),
              "features": FEATURES, "class_distribution": usable.proxy_class.value_counts().to_dict(),
              "label_definition": {"High": "income per person < food threshold", "Medium": "food threshold <= income per person < poverty threshold", "Low": "income per person >= poverty threshold"},
              "holdout_non_caraga": evaluate(model, test), "holdout_caraga": evaluate(model, caraga),
              "holdout_agusan_del_norte_excluding_butuan": evaluate(model, caraga[caraga.W_PROV == 2]),
              "majority_baseline_non_caraga": evaluate(dummy, test), "majority_baseline_caraga": evaluate(dummy, caraga),
              "feature_importance": dict(zip(FEATURES, model.feature_importances_.tolist())),
              "versions": {"sklearn": sklearn.__version__, "pandas": pd.__version__},
              "limitations": [
                  "Low/Medium/High are researcher-defined financial categories, not official humanitarian vulnerability or aid eligibility.",
                  "Unmapped HUCs and other domains are excluded, including Butuan; national coverage is incomplete pending verified mapping.",
                  "Known income directly determines the threshold category; RF is only an expenditure-based proxy for unknown income.",
                  "No income, income components, per-capita income, deciles, target thresholds, or identifiers are predictors.",
                  "Family size is a shared denominator in income labels and expenditure predictors; association is not causal validation.",
                  "Metrics are unweighted sample-level results, not population poverty prevalence estimates.",
                  "All Caraga records are withheld from training. No final refit on holdouts.",
                  "Annual monetary values are in 2025 pesos; current-period values require separate validation.",
                  "FIES PUF contains 170916 rows; the supplied report describes 170914 completed samples. Source difference unresolved.",
                  "No expert humanitarian labels, disaster outcomes, temporal validation, or automatic approval."]}
    root = args.output_root
    for directory in ("datasets", "evaluation", "models"):
        (root / directory).mkdir(parents=True, exist_ok=True)
    keep = ["W_REGN", "W_PROV", "SEQNO", "URBAN", "province_name", "threshold_area", "threshold_sheet_row", "FSIZE", "TOINC", "PERCAPITA", "TOTEX", "FOOD", "RFACT", "food_threshold", "poverty_threshold", *FEATURES, "proxy_class", "exclusion_reason", "sample_group", "split"]
    frame[keep].to_csv(root / "datasets/fies2025_prepared.csv", index=False)
    (root / "evaluation/fies2025_evaluation.json").write_text(json.dumps(report, indent=2), encoding="utf-8")
    joblib.dump({"pipeline": model, "version": VERSION, "features": FEATURES,
                 "label_kind": "financial_threshold_proxy", "reference_year": 2025,
                 "app_ready": False}, root / "models/fies2025_candidate.joblib", compress=3)
    print(json.dumps({k: report[k] for k in ("records_total", "records_usable", "excluded_records", "class_distribution")}, indent=2))
    for name in ("holdout_non_caraga", "holdout_caraga", "holdout_agusan_del_norte_excluding_butuan"):
        print(name, "macro F1", round(report[name]["macro_f1"], 4), "balanced accuracy", round(report[name]["balanced_accuracy"], 4))
    print("Offline candidate saved. Running application and database were not changed.")


if __name__ == "__main__":
    main()
