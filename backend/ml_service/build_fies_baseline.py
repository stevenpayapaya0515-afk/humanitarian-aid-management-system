"""Build an offline FIES 2025 financial proxy; never modifies the app or database.
Run: python -m ml_service.build_fies_baseline --zip PATH --thresholds PATH
Only exact province matches, documented spelling aliases, and the published NCR district mapping are accepted.
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

VERSION = "fies2025-financial-proxy-v3"
CLASSES = ["Low", "Medium", "High"]
# No income, income components, deciles, survey weights or identifiers as predictors.
FEATURES = ["average_family_size", "food_per_person", "nonfood_per_person"]
ALIASES = {"Mountain Province": "Mt. Province", "Samar (Western)": "Samar",
           "Compostela Valley": "Davao de Oro", "North Cotabato": "Cotabato",
           "Dinagat Island": "Dinagat Islands", "City of Isabela": "Isabela City"}


# PSA threshold workbook tab16, footnote a/: NCR cities grouped into districts.
# Codes are from the supplied FIES 2025 W_PROV_VS21 dictionary, not PSGC IDs.
NCR_DISTRICTS = {
    806: "1st District",
    805: "2nd District", 807: "2nd District", 812: "2nd District",
    813: "2nd District", 814: "2nd District",
    801: "3rd District", 804: "3rd District", 809: "3rd District", 816: "3rd District",
    802: "4th District", 803: "4th District", 808: "4th District", 810: "4th District",
    811: "4th District", 817: "4th District", 815: "4th District",
}


def threshold_area(province_code, province_name, region_code):
    if province_code in NCR_DISTRICTS:
        if region_code != 13:
            raise ValueError("NCR province code conflicts with region code")
        return NCR_DISTRICTS[province_code]
    return ALIASES.get(province_name, province_name)


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
    frame["threshold_area"] = [threshold_area(p, n, r) for p, n, r in zip(frame.W_PROV, frame.province_name, frame.W_REGN)]
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



# Fixed before examining v3 holdouts. These compare class weighting only.
CANDIDATES = [
    ("balanced_baseline", "balanced_subsample"),
    ("moderate_weights", {"Low": 1, "Medium": 2, "High": 4}),
    ("unweighted", None),
]


def validation_split(train):
    splitter = GroupShuffleSplit(n_splits=1, test_size=.2, random_state=17)
    fit_ids, validation_ids = next(splitter.split(train, groups=train.sample_group))
    fit, validation = train.iloc[fit_ids], train.iloc[validation_ids]
    if set(fit.proxy_class) != set(CLASSES) or set(validation.proxy_class) != set(CLASSES):
        raise ValueError("All classes must occur in fitting and validation partitions")
    if set(fit.sample_group) & set(validation.sample_group):
        raise ValueError("PSU overlap between fitting and validation")
    return fit, validation


def choose_candidate(results):
    # Keep sensitivity close to the balanced baseline on validation data only.
    # These are research comparison tolerances, not operational acceptance criteria.
    reference = results[0]["metrics"]["classification_report"]
    high_floor = max(0.0, reference["High"]["recall"] - .05)
    medium_floor = max(0.0, reference["Medium"]["recall"] - .10)
    eligible = [item for item in results
                if item["metrics"]["classification_report"]["High"]["recall"] >= high_floor
                and item["metrics"]["classification_report"]["Medium"]["recall"] >= medium_floor]
    return max(eligible, key=lambda item: item["metrics"]["macro_f1"]), {
        "high_recall_floor": high_floor, "medium_recall_floor": medium_floor,
        "criterion": "Highest validation macro F1 subject to recall floors relative to balanced baseline; ties retain earlier candidate.",
        "eligible_candidates": [item["name"] for item in eligible],
    }


def select_model(train):
    fit, validation = validation_split(train)
    results = []
    for name, weights in CANDIDATES:
        print("Validation candidate:", name, flush=True)
        candidate = RandomForestClassifier(n_estimators=200, min_samples_leaf=10,
                                            class_weight=weights, random_state=42, n_jobs=2)
        candidate.fit(fit[FEATURES], fit.proxy_class)
        metrics = evaluate(candidate, validation)
        results.append({"name": name, "class_weight": weights, "metrics": metrics})
        print("  macro F1:", round(metrics["macro_f1"], 4), flush=True)
    selected, rule = choose_candidate(results)
    print("Selected using validation only:", selected["name"], flush=True)
    model = RandomForestClassifier(n_estimators=200, min_samples_leaf=10,
                                    class_weight=selected["class_weight"], random_state=42, n_jobs=2)
    # Refit only on the original training partition, never test or Caraga rows.
    model.fit(train[FEATURES], train.proxy_class)
    return model, {
        "fit_records": len(fit), "validation_records": len(validation),
        "group_split_seed": 17, "candidates": results,
        "selected_candidate": selected["name"], "selection_rule": rule,
        "refit_records": len(train),
        "note": "Validation is a subset of the original training partition; its score is not a test score.",
    }, validation.index


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
    model, selection, validation_ids = select_model(train)
    frame["selection_partition"] = "not_used"
    frame.loc[train.index, "selection_partition"] = "fit"
    frame.loc[validation_ids, "selection_partition"] = "validation"
    dummy = DummyClassifier(strategy="most_frequent").fit(train[FEATURES], train.proxy_class)
    excluded = frame[~frame.exclusion_reason.eq("")]
    report = {"version": VERSION, "status": "offline research candidate; not connected to app",
              "source": "PSA FIES 2025 Volume 1 PUF", "threshold_source": "2025 official poverty workbook, tab16 including NCR footnote a/",
              "geographic_mapping_version": "province-aliases-and-ncr-districts-v2",
              "source_sha256": hashlib.sha256(args.zip.read_bytes()).hexdigest(),
              "threshold_sha256": hashlib.sha256(args.thresholds.read_bytes()).hexdigest(),
              "records_total": len(frame), "records_usable": len(usable), "training_records": len(train), "model_selection": selection,
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
                  "All Caraga records are withheld from training and candidate selection. No final refit on holdouts.",
                  "Caraga and non-Caraga holdouts were inspected during earlier baseline development; these are reused development holdouts, not a fresh external validation.",
                  "Annual monetary values are in 2025 pesos; current-period values require separate validation.",
                  "FIES PUF contains 170916 rows; the supplied report describes 170914 completed samples. Source difference unresolved.",
                  "No expert humanitarian labels, disaster outcomes, temporal validation, or automatic approval."]}
    root = args.output_root
    for directory in ("datasets", "evaluation", "models"):
        (root / directory).mkdir(parents=True, exist_ok=True)
    keep = ["W_REGN", "W_PROV", "SEQNO", "URBAN", "province_name", "threshold_area", "threshold_sheet_row", "FSIZE", "TOINC", "PERCAPITA", "TOTEX", "FOOD", "RFACT", "food_threshold", "poverty_threshold", *FEATURES, "proxy_class", "exclusion_reason", "sample_group", "split", "selection_partition"]
    frame[keep].to_csv(root / "datasets/fies2025_prepared.csv", index=False)
    (root / "evaluation/fies2025_evaluation.json").write_text(json.dumps(report, indent=2), encoding="utf-8")
    joblib.dump({"pipeline": model, "version": VERSION, "features": FEATURES,
                 "label_kind": "financial_threshold_proxy", "reference_year": 2025,
                 "geographic_mapping_version": "province-aliases-and-ncr-districts-v2",
                 "selected_candidate": selection["selected_candidate"],
                 "app_ready": False}, root / "models/fies2025_candidate.joblib", compress=3)
    print(json.dumps({k: report[k] for k in ("records_total", "records_usable", "excluded_records", "class_distribution")}, indent=2))
    for name in ("holdout_non_caraga", "holdout_caraga", "holdout_agusan_del_norte_excluding_butuan"):
        print(name, "macro F1", round(report[name]["macro_f1"], 4), "balanced accuracy", round(report[name]["balanced_accuracy"], 4))
    print("Offline candidate saved. Running application and database were not changed.")


if __name__ == "__main__":
    main()
