"""Offline RF rule-agreement experiment; never an aid eligibility decision."""
import argparse
import hashlib
import json
from pathlib import Path
import joblib
import numpy as np
import pandas as pd
import sklearn
from sklearn.ensemble import RandomForestClassifier
from sklearn.metrics import classification_report, confusion_matrix, balanced_accuracy_score
from sklearn.model_selection import GroupShuffleSplit
from sklearn.pipeline import Pipeline
from sklearn.preprocessing import OneHotEncoder
from .label_apis2022 import CODES, VERSION, label_row
FEATURES = list(CODES)
CLASSES = ["Low", "Medium", "High"]

def validate_source(frame):
    required = {"REG", "HHID", "RPSU", "proxy_class", "label_version", *FEATURES}
    if not required.issubset(frame.columns):
        raise ValueError("Missing training columns")
    if frame.duplicated(["REG", "HHID"]).any():
        raise ValueError("Duplicate households")
    if frame[["REG", "HHID", "RPSU"]].eq("").any().any():
        raise ValueError("Missing household/sampling identifiers")
    if not frame["label_version"].eq(VERSION).all():
        raise ValueError("Unexpected label version")
    expected = [label_row(row)["proxy_class"] for row in frame.to_dict("records")]
    if expected != frame.proxy_class.tolist():
        raise ValueError("Stored labels disagree with the versioned rubric")
    return frame.loc[frame.proxy_class.isin(CLASSES)].copy()

def split_indices(frame):
    caraga = frame.REG.astype(int).eq(16).to_numpy()
    outside = np.flatnonzero(~caraga)
    groups = frame.REG + ":" + frame.RPSU
    splitter = GroupShuffleSplit(n_splits=1, test_size=.2, random_state=42)
    a, b = next(splitter.split(outside, groups=groups.iloc[outside]))
    train, test = outside[a], outside[b]
    if set(groups.iloc[train]) & set(groups.iloc[test]):
        raise AssertionError("Sampling groups crossed partitions")
    return train, test, np.flatnonzero(caraga)

def metrics(y, prediction):
    return {"records": len(y),
            "classification_report": classification_report(y, prediction, labels=CLASSES, output_dict=True, zero_division=0),
            "balanced_accuracy": float(balanced_accuracy_score(y, prediction)),
            "confusion_matrix": confusion_matrix(y, prediction, labels=CLASSES).tolist()}

def train(source, output):
    raw = pd.read_csv(source, dtype=str, keep_default_na=False)
    frame = validate_source(raw).reset_index(drop=True)
    train_idx, test_idx, caraga_idx = split_indices(frame)
    for name, idx in [("training", train_idx), ("non_caraga", test_idx), ("caraga", caraga_idx)]:
        if set(frame.iloc[idx].proxy_class) != set(CLASSES):
            raise ValueError(f"{name} does not contain all three classes")
    x = frame[FEATURES].apply(lambda col: col.astype(int).astype(str))
    y = frame.proxy_class
    pipeline = Pipeline([
        ("categories", OneHotEncoder(handle_unknown="ignore")),
        ("forest", RandomForestClassifier(n_estimators=200, min_samples_leaf=2,
                 class_weight="balanced_subsample", random_state=42, n_jobs=-1)),
    ])
    pipeline.fit(x.iloc[train_idx], y.iloc[train_idx])
    evaluations = {}
    majority = y.iloc[train_idx].value_counts().idxmax()
    for name, idx in [("non_caraga_holdout", test_idx), ("caraga_holdout", caraga_idx)]:
        actual = y.iloc[idx]
        rules = [label_row(row)["proxy_class"] for row in frame.iloc[idx].to_dict("records")]
        evaluations[name] = {
            "random_forest": metrics(actual, pipeline.predict(x.iloc[idx])),
            "exact_rubric": metrics(actual, rules),
            "majority_baseline": metrics(actual, [majority] * len(idx)),
        }
    report = {
        "model_version": "apis2022-rf-rule-agreement-v1", "label_version": VERSION,
        "app_ready": False, "features": FEATURES, "classes": CLASSES,
        "source_sha256": hashlib.sha256(source.read_bytes()).hexdigest(),
        "sklearn_version": sklearn.__version__, "random_seed": 42,
        "total_records": len(raw), "labelled_records": len(frame),
        "excluded_needs_review": len(raw)-len(frame), "training_records": len(train_idx),
        "split": "Caraga withheld; remaining REG:RPSU groups split 80/20 with seed 42",
        "tuning": "Fixed parameters; no model selection using either holdout",
        "hyperparameters": {"n_estimators": 200, "min_samples_leaf": 2, "class_weight": "balanced_subsample"},
        "evaluations": evaluations,
        "interpretation": [
            "Measures rule agreement, not independent humanitarian validity.",
            "Exact rubric is perfect by construction and is the authoritative rule baseline.",
            "Metrics are unweighted sample results, not population/provincial estimates.",
            "Caraga is regional; this PUF cannot identify Agusan del Norte.",
            "Unknown answers excluded, not imputed. Active APIS 2019 API unchanged.",
        ],
    }
    (output/"models").mkdir(parents=True, exist_ok=True)
    (output/"evaluation").mkdir(parents=True, exist_ok=True)
    joblib.dump({"pipeline": pipeline, "features": FEATURES, "version": report["model_version"],
                 "label_version": VERSION, "label_kind": "researcher_defined_proxy",
                 "app_ready": False, "sklearn_version": sklearn.__version__},
                output/"models/apis2022_candidate.joblib")
    (output/"evaluation/apis2022_training.json").write_text(json.dumps(report, indent=2)+"\n")
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt
    fig, axes = plt.subplots(1, 2, figsize=(10, 4.5), constrained_layout=True)
    for ax, (name, values) in zip(axes, evaluations.items()):
        matrix = np.array(values["random_forest"]["confusion_matrix"])
        ax.imshow(matrix, cmap="Greens")
        ax.set(xticks=range(3), yticks=range(3), xticklabels=CLASSES, yticklabels=CLASSES,
               xlabel="RF prediction", ylabel="Draft rule label", title=name.replace("_", " ").title())
        for i in range(3):
            for j in range(3):
                ax.text(j, i, str(matrix[i,j]), ha="center", va="center",
                        color="white" if matrix[i,j] > matrix.max()/2 else "#183c2b")
    fig.suptitle("APIS 2022: agreement with draft rules (unweighted counts)")
    fig.savefig(output/"evaluation/apis2022_confusion_matrices.png", dpi=160)
    plt.close(fig)
    return report

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--csv", type=Path, default=Path(__file__).resolve().parent/"datasets/apis2022_proxy_draft.csv")
    parser.add_argument("--output-dir", type=Path, default=Path(__file__).resolve().parent)
    args = parser.parse_args()
    report = train(args.csv, args.output_dir)
    for name, result in report["evaluations"].items():
        print(name, "macro F1:", round(result["random_forest"]["classification_report"]["macro avg"]["f1-score"], 4))
    print("Offline candidate saved. Active application unchanged.")
