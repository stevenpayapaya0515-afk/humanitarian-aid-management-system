#!/usr/bin/env python3
"""
AidTrack Random Forest Training Pipeline.

Location: backend/ml_service/train_random_forest.py

Uses synthetic records for preliminary pipeline testing only.
Generated labels are provisional and are not LGU-verified ground truth.
"""

from __future__ import annotations

import argparse
import json
from datetime import datetime, timezone
from pathlib import Path

import joblib
import pandas as pd

from sklearn.compose import ColumnTransformer
from sklearn.ensemble import RandomForestClassifier
from sklearn.feature_selection import SelectFromModel
from sklearn.impute import SimpleImputer

from sklearn.metrics import (
    accuracy_score,
    classification_report,
    confusion_matrix,
    f1_score,
    precision_score,
    recall_score,
)

from sklearn.model_selection import train_test_split
from sklearn.pipeline import Pipeline
from sklearn.preprocessing import OneHotEncoder, StandardScaler


# ==========================================
# DIRECTORY CONFIGURATION
# ==========================================

BACKEND_ROOT = Path(__file__).resolve().parents[1]
ML_SERVICE_DIR = BACKEND_ROOT / "ml_service"

DEFAULT_DATASET = (
    ML_SERVICE_DIR / "datasets" / "aidtrack_ml_training_1000.csv"
)

DEFAULT_OUTPUT = ML_SERVICE_DIR / "models"
EVALUATION_DIR = ML_SERVICE_DIR / "evaluation"


# ==========================================
# FEATURES AND TARGET
# ==========================================

NUMERIC_FEATURES = [
    "household_size",
    "age_0_5_count",
    "age_6_17_count",
    "age_18_59_count",
    "age_60_plus_count",
    "pwd_count",
]

CATEGORICAL_FEATURES = [
    "monthly_income_range",
    "employment_status",
    "livelihood_type",
    "disaster_affected",
    "housing_damage_level",
    "displaced",
]

FEATURES = NUMERIC_FEATURES + CATEGORICAL_FEATURES

TARGET = "vulnerability_class"

CLASS_ORDER = ["Low", "Medium", "High"]


# ==========================================
# RANDOM FOREST PIPELINE
# ==========================================

def build_pipeline() -> Pipeline:

    # Numeric preprocessing
    numeric_pipeline = Pipeline(
        steps=[
            ("imputer", SimpleImputer(strategy="median")),
            ("scaler", StandardScaler()),
        ]
    )

    # Categorical preprocessing
    categorical_pipeline = Pipeline(
        steps=[
            ("imputer", SimpleImputer(strategy="most_frequent")),
            ("onehot", OneHotEncoder(handle_unknown="ignore")),
        ]
    )

    # Combine preprocessing
    preprocessing = ColumnTransformer(
        transformers=[
            ("numeric", numeric_pipeline, NUMERIC_FEATURES),
            ("categorical", categorical_pipeline, CATEGORICAL_FEATURES),
        ],
        remainder="drop",
    )

    # Feature selection using Random Forest importance
    feature_selection = SelectFromModel(
        estimator=RandomForestClassifier(
            n_estimators=200,
            random_state=42,
            class_weight="balanced_subsample",
            n_jobs=-1,
        ),
        threshold="median",
    )

    # Main Random Forest classifier
    classifier = RandomForestClassifier(
        n_estimators=300,
        random_state=42,
        class_weight="balanced_subsample",
        min_samples_leaf=2,
        n_jobs=-1,
    )

    return Pipeline(
        steps=[
            ("preprocessing", preprocessing),
            ("feature_selection", feature_selection),
            ("classifier", classifier),
        ]
    )


# ==========================================
# MAIN TRAINING FUNCTION
# ==========================================

def main() -> None:

    parser = argparse.ArgumentParser(
        description="Train AidTrack Random Forest Classifier."
    )

    parser.add_argument(
        "--dataset",
        default=str(DEFAULT_DATASET)
    )

    parser.add_argument(
        "--output-dir",
        default=str(DEFAULT_OUTPUT)
    )

    args = parser.parse_args()

    dataset_path = Path(args.dataset).expanduser().resolve()
    output_dir = Path(args.output_dir).expanduser().resolve()

    # Create required folders
    output_dir.mkdir(parents=True, exist_ok=True)
    EVALUATION_DIR.mkdir(parents=True, exist_ok=True)

    # ======================================
    # LOAD DATASET
    # ======================================

    if not dataset_path.is_file():
        raise FileNotFoundError(
            f"Dataset not found: {dataset_path}\n"
            "Place aidtrack_ml_training_1000.csv inside "
            "backend/ml_service/datasets/"
        )

    data = pd.read_csv(dataset_path)

    required_columns = FEATURES + [TARGET]

    missing = [
        column
        for column in required_columns
        if column not in data.columns
    ]

    if missing:
        raise ValueError(
            f"CSV is missing required columns: {missing}"
        )

    data = data[required_columns].dropna(
        subset=[TARGET]
    ).copy()

    data[TARGET] = data[TARGET].astype(str).str.strip()

    # ======================================
    # CORRECT MISSING HOUSING VALUES
    # ======================================

    unaffected = (
        data["disaster_affected"]
        .astype(str)
        .str.strip()
        .str.lower()
    )

    # Unaffected households have no housing damage.
    data.loc[
        unaffected == "no",
        "housing_damage_level"
    ] = data.loc[
        unaffected == "no",
        "housing_damage_level"
    ].fillna("None")

    # Affected households with missing damage information
    # should be marked Unknown.
    data.loc[
        (unaffected == "yes")
        & data["housing_damage_level"].isna(),
        "housing_damage_level"
    ] = "Unknown"

    # ======================================
    # VALIDATE CLASS LABELS
    # ======================================

    allowed_labels = {"Low", "Medium", "High"}

    unexpected = sorted(
        set(data[TARGET]) - allowed_labels
    )

    if unexpected:
        raise ValueError(
            f"Unexpected vulnerability labels: {unexpected}"
        )

    if data[TARGET].nunique() != 3:
        raise ValueError(
            "Dataset must contain Low, Medium, and High classes."
        )

    X = data[FEATURES]
    y = data[TARGET]

    # ======================================
    # TRAIN-TEST SPLIT
    # ======================================

    X_train, X_test, y_train, y_test = train_test_split(
        X,
        y,
        test_size=0.20,
        random_state=42,
        stratify=y,
    )

    # ======================================
    # TRAIN RANDOM FOREST
    # ======================================

    model = build_pipeline()

    model.fit(X_train, y_train)

    predictions = model.predict(X_test)

    # ======================================
    # MODEL EVALUATION
    # ======================================

    metrics = {
        "accuracy": round(
            float(accuracy_score(y_test, predictions)), 4
        ),

        "precision_macro": round(
            float(
                precision_score(
                    y_test,
                    predictions,
                    average="macro",
                    zero_division=0,
                )
            ),
            4,
        ),

        "recall_macro": round(
            float(
                recall_score(
                    y_test,
                    predictions,
                    average="macro",
                    zero_division=0,
                )
            ),
            4,
        ),

        "f1_macro": round(
            float(
                f1_score(
                    y_test,
                    predictions,
                    average="macro",
                    zero_division=0,
                )
            ),
            4,
        ),

        "confusion_matrix_labels": CLASS_ORDER,

        "confusion_matrix": confusion_matrix(
            y_test,
            predictions,
            labels=CLASS_ORDER,
        ).tolist(),

        "classification_report": classification_report(
            y_test,
            predictions,
            labels=CLASS_ORDER,
            output_dict=True,
            zero_division=0,
        ),
    }

    # ======================================
    # TRAIN FINAL DEPLOYMENT MODEL
    # ======================================

    deployment_model = build_pipeline()

    deployment_model.fit(X, y)

    # ======================================
    # SAVE MODEL AND EVALUATION REPORT
    # ======================================

    model_path = (
        output_dir / "aidtrack_random_forest.joblib"
    )

    report_path = (
        EVALUATION_DIR / "aidtrack_random_forest_report.json"
    )

    joblib.dump(deployment_model, model_path)

    # ======================================
    # GENERATE EVALUATION REPORT
    # ======================================

    report = {
        "algorithm": "Random Forest Classifier",

        "records_used": int(len(data)),

        "class_distribution": {
            label: int((y == label).sum())
            for label in CLASS_ORDER
        },

        "preprocessing": [
            "Median imputation and standardization for numeric features",
            "Most-frequent imputation and one-hot encoding for categorical features",
        ],

        "feature_selection": (
            "SelectFromModel using Random Forest feature importance, "
            "fitted inside the training pipeline."
        ),

        "split": (
            "80/20 stratified train-test split; random_state=42"
        ),

        "ensemble_prediction": (
            "Multiple decision trees with majority-voting classification."
        ),

        "holdout_metrics": metrics,

        "warning": (
            "Synthetic-only preliminary results. These metrics measure "
            "agreement with provisional synthetic labels, not validated "
            "real-world household vulnerability performance. "
            "Retrain and reevaluate with authorized LGU data."
        ),

        "generated_at_utc": datetime.now(
            timezone.utc
        ).isoformat(),

        "model_file": str(model_path),
    }

    report_path.write_text(
        json.dumps(report, indent=4),
        encoding="utf-8",
    )

    # ======================================
    # DISPLAY RESULTS
    # ======================================

    print("\nAIDTRACK RANDOM FOREST TRAINING")
    print("--------------------------------")

    print(f"Records used: {len(data)}")

    print(
        "Class distribution:",
        report["class_distribution"]
    )

    print("\nHoldout evaluation (20% test set):")

    for key in [
        "accuracy",
        "precision_macro",
        "recall_macro",
        "f1_macro",
    ]:
        print(f"{key}: {metrics[key]:.4f}")

    print("\nConfusion matrix labels:", CLASS_ORDER)

    print("Confusion matrix:")

    for row in metrics["confusion_matrix"]:
        print(row)

    print("\nSaved model:", model_path)

    print("Saved evaluation report:", report_path)

    print(
        "\nNOTE: Synthetic-data results are preliminary only."
    )


if __name__ == "__main__":
    main()