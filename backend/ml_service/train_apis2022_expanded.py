"""Offline APIS 2022 expanded proxy agreement experiment (NOT app-ready).

Execute from backend root:
  python -m ml_service.train_apis2022_expanded \
    --csv ml_service/datasets/apis2022_household_indicators.csv \
    --output-dir ml_service

Does not overwrite train_apis2022.py or apis2022_candidate.joblib.
"""
from __future__ import annotations
import argparse
import hashlib
import json
from pathlib import Path
import joblib
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np
import pandas as pd
import sklearn
from sklearn.compose import ColumnTransformer
from sklearn.ensemble import RandomForestClassifier
from sklearn.metrics import (classification_report, confusion_matrix,
                             balanced_accuracy_score)
from sklearn.model_selection import GroupShuffleSplit
from sklearn.pipeline import Pipeline
from sklearn.preprocessing import OneHotEncoder
from .label_apis2022_expanded import (VERSION, INCOME_QUANTILE, HIGH_AT, DOMAINS,
    CATEGORICAL, NUMERIC, FEATURES, add_proxy_labels, check_input, prepare, raw_feature_frame)

MODEL_VERSION = "apis2022-rf-expanded-proxy-research-v1"
CLASSES = ["Low", "Medium", "High"]


def group_split(frame):
    is_caraga = frame["REG"].astype(int).eq(16).to_numpy()
    outside = np.flatnonzero(~is_caraga)
    groups = frame["REG"].astype(str) + ":" + frame["RPSU"].astype(str)
    splitter = GroupShuffleSplit(n_splits=1, test_size=.2, random_state=42)
    ia, ib = next(splitter.split(outside, groups=groups.iloc[outside]))
    train, holdout, caraga = outside[ia], outside[ib], np.flatnonzero(is_caraga)
    if set(groups.iloc[train]) & set(groups.iloc[holdout]):
        raise AssertionError("Cluster leakage between training and non-Caraga holdout")
    assert not is_caraga[train].any() and not is_caraga[holdout].any()
    return train, holdout, caraga


def metrics(y, p):
    return {"records": int(len(y)),
      "classification_report": classification_report(y, p, labels=CLASSES,
                                                        output_dict=True, zero_division=0),
      "balanced_accuracy": float(balanced_accuracy_score(y, p)),
      "confusion_matrix": confusion_matrix(y, p, labels=CLASSES).tolist()}


def selection(labels, indices):
    return np.array([i for i in indices if labels.iloc[i] in CLASSES], dtype=int)


def run(csv_path: Path, output_dir: Path):
    frame = pd.read_csv(csv_path, dtype=str, keep_default_na=False)
    check_input(frame)
    frame = prepare(frame)
    train0, test0, caraga0 = group_split(frame)
    train_incomes = frame.iloc[train0]["K5_PER_CAPITA"].dropna()
    train_incomes = train_incomes[train_incomes >= 0]
    if len(train_incomes) < 100:
        raise ValueError("Insufficient valid non-Caraga training financial values")
    cutoff = float(train_incomes.quantile(INCOME_QUANTILE))
    labelled = add_proxy_labels(frame, cutoff)
    y = labelled["expanded_proxy_class"]
    train, test, caraga = [selection(y, idx) for idx in (train0, test0, caraga0)]
    if not (len(train) and len(test) and len(caraga)):
        raise ValueError("A train or holdout partition contains zero labelled cases")
    if any(set(y.iloc[idx]) != set(CLASSES) for idx in (train, test, caraga)):
        raise ValueError("Each split must contain Low, Medium, High; review rubric")
    x = raw_feature_frame(labelled)
    transform = ColumnTransformer([
        ("coded", OneHotEncoder(handle_unknown="ignore"), CATEGORICAL),
        ("numeric", "passthrough", NUMERIC),
    ])
    pipeline = Pipeline([
        ("prepare", transform),
        ("forest", RandomForestClassifier(n_estimators=160, min_samples_leaf=2,
                  class_weight="balanced_subsample", random_state=42, n_jobs=-1)),
    ])
    pipeline.fit(x.iloc[train], y.iloc[train])
    majority = y.iloc[train].value_counts().idxmax()
    evaluations = {}
    for name, idx in (("non_caraga_holdout", test), ("caraga_holdout", caraga)):
        actual = y.iloc[idx]
        pred = pipeline.predict(x.iloc[idx])
        evaluations[name] = {
            "random_forest": metrics(actual, pred),
            "majority_baseline": metrics(actual, [majority] * len(idx)),
            # The rubric is the source of the targets; this is NOT independent validity.
            "exact_rubric": metrics(actual, actual.to_numpy()),
        }
    # Sensitivity checks: how many classifications depend on expert-chosen cutoffs?
    alternative_high4 = add_proxy_labels(frame, cutoff, high_at=4)["expanded_proxy_class"]
    alternative_income20 = add_proxy_labels(frame,
       float(train_incomes.quantile(.20)))["expanded_proxy_class"]
    alternative_income30 = add_proxy_labels(frame,
       float(train_incomes.quantile(.30)))["expanded_proxy_class"]
    changes = lambda alt: int((y != alt).sum())
    counts = lambda idx: {k: int(v) for k,v in y.iloc[idx].value_counts().to_dict().items()}
    model_output = output_dir / "models" / "apis2022_expanded_candidate.joblib"
    report_output = output_dir / "evaluation" / "apis2022_expanded_training.json"
    chart_output = output_dir / "evaluation" / "apis2022_expanded_confusion_matrix.png"
    label_output = output_dir / "datasets" / "apis2022_household_expanded_proxy_draft.csv"
    report = {
        "model_version": MODEL_VERSION, "label_version": VERSION, "app_ready": False,
        "data_type": "PSA APIS PUF 2022 research survey, NOT real Cabadbaran household registry",
        "label_kind": "researcher_defined_proxy", "independent_ground_truth": False,
        "evaluation_target": "Agreement with revised experimental proxy rubric, not humanitarian validity",
        "source_sha256": hashlib.sha256(csv_path.read_bytes()).hexdigest(),
        "sklearn_version": sklearn.__version__, "random_seed": 42,
        "features": FEATURES, "excluded_model_features": [
            "REG", "HHID", "RPSU", "REP", "RFACT", "MEM_ROSTER_MATCHES_FSIZE",
            "MEM_ROSTER_SHORTFALL", "baseline_proxy_class", "baseline_deprivation_count",
            "baseline_label_version", "expanded_proxy_class", "expanded_proxy_score",
            "all proxy domain flags", "G1/G5/G9/G11/H1 social protection responses",
            "G13_PHEALTH (requires codebook and fairness review)"],
        "total_households": int(len(frame)), "valid_proxy_households": int(y.isin(CLASSES).sum()),
        "needs_review": int(y.eq("Needs review").sum()),
        "all_class_counts": counts(np.arange(len(y))),
        "caraga_total": int(len(caraga0)), "caraga_class_counts": counts(caraga0),
        "training_records": int(len(train)), "non_caraga_holdout_records": int(len(test)),
        "caraga_holdout_records": int(len(caraga)),
        "train_only_income_proxy_cutoff_php_per_person_month": round(cutoff,2),
        "income_cutoff_method": "25th percentile of K5/FSIZE in non-Caraga training groups only; NOT official poverty threshold",
        "proxy_domains": DOMAINS,
        "label_thresholds": {"Low": "0 of 8", "Medium": "1-2 of 8", "High": ">=3 of 8"},
        "conditional_disaster_mappings_assumed": {"1": "yes", "2": "no",
            "G16A/G16B_blank_when_G16_2": "survey skip; NOT a negative answer"},
        "roster_policy": "Incomplete member rosters => Needs review; no silent age-count imputation",
        "split": "Caraga (REG=16) withheld; other REG:RPSU sample groups separated using seed 42",
        "evaluations": evaluations,
        "sensitivity": {
            "changed_if_high_at_4": changes(alternative_high4),
            "changed_if_income_quantile_20": changes(alternative_income20),
            "changed_if_income_quantile_30": changes(alternative_income30),
        },
        "limitations": [
            "All reported RF metrics measure rule reproduction (proxy-label agreement).",
            "No independently verified LGU humanitarian classification labels were supplied.",
            "The revised 8-domain rubric and its cutoffs are experimental and require LGU/instructor review.",
            "Disaster response values assumed 1=yes, 2=no; verify APIS 2022 codebook.",
            "K5 is treated as monthly income following the source preparer's notes; verify official definition.",
            "Member age totals missing some household members; incomplete rosters are not classified.",
            "Assistance received is NOT interpreted as low vulnerability.",
            "Sampling weights not used; metrics are unweighted sample counts, not population estimates.",
            "Caraga regional holdout does not identify Agusan del Norte or Cabadbaran.",
            "Never use experimental proxy alone for eligibility, aid prioritization, or household denial.",
        ],
    }
    model_output.parent.mkdir(parents=True, exist_ok=True)
    report_output.parent.mkdir(parents=True, exist_ok=True)
    label_output.parent.mkdir(parents=True, exist_ok=True)
    joblib.dump({"pipeline": pipeline, "features": FEATURES, "version": MODEL_VERSION,
        "label_version": VERSION, "label_kind": "researcher_defined_proxy",
        "app_ready": False, "income_cutoff": cutoff, "sklearn_version": sklearn.__version__}, model_output)
    report_output.write_text(json.dumps(report, indent=2, allow_nan=False) + "\n", encoding="utf-8")
    # Export only newly derived label fields next to source columns; never overwrite source CSV.
    extra = ["expanded_proxy_score", "expanded_proxy_class", "expanded_label_version"] + [f"proxy_{d}" for d in DOMAINS]
    result = pd.read_csv(csv_path, dtype=str, keep_default_na=False)
    for col in extra:
        result[col] = labelled[col].astype(object).where(labelled[col].notna(), "")
    result.to_csv(label_output, index=False)
    fig, axes = plt.subplots(1,2,figsize=(10.5,4.5),constrained_layout=True)
    for ax,(name,values) in zip(axes,evaluations.items()):
        mat = np.array(values["random_forest"]["confusion_matrix"])
        ax.imshow(mat,cmap="Blues")
        ax.set(xlabel="Random Forest prediction", ylabel="Research proxy label",
               title=name.replace("_"," ").title(),
               xticks=range(3), yticks=range(3), xticklabels=CLASSES, yticklabels=CLASSES)
        for i in range(3):
            for j in range(3):
                ax.text(j,i,str(mat[i,j]),ha="center",va="center",
                        color="white" if mat[i,j] > mat.max()/2 else "black")
    fig.suptitle("APIS 2022: expanded proxy rule agreement (not real-world validation)")
    fig.savefig(chart_output,dpi=150)
    plt.close(fig)
    return report


if __name__ == "__main__":
    ap=argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--csv",type=Path,default=Path(__file__).resolve().parent/"datasets"/"apis2022_household_indicators.csv")
    ap.add_argument("--output-dir",type=Path,default=Path(__file__).resolve().parent)
    args=ap.parse_args()
    report=run(args.csv,args.output_dir)
    for name, evaluation in report["evaluations"].items():
        rf=evaluation["random_forest"]
        print(f"{name}: records={rf['records']}, accuracy={rf['classification_report']['accuracy']:.4f}, "
              f"macro_F1={rf['classification_report']['macro avg']['f1-score']:.4f}")
    print("Expanded offline candidate saved; active application and existing candidate unchanged.")
