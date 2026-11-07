
from pathlib import Path
import json

import matplotlib.pyplot as plt
import numpy as np

from matplotlib.colors import LinearSegmentedColormap
from matplotlib.patches import Rectangle


# ==========================================
# AIDTRACK THEME COLORS
# ==========================================

PRIMARY_GREEN = "#185C37"
ACCENT_YELLOW = "#FFCA28"

DARK_TEXT = "#26352B"
MUTED_TEXT = "#66736A"
WHITE = "#FFFFFF"


# ==========================================
# FILE PATHS
# ==========================================

backend_dir = Path(__file__).resolve().parents[1]

evaluation_dir = (
    backend_dir / "ml_service" / "evaluation"
)

report_path = (
    evaluation_dir / "aidtrack_random_forest_report.json"
)

output_path = (
    evaluation_dir / "aidtrack_random_forest_confusion_matrix.png"
)


# ==========================================
# LOAD EVALUATION REPORT
# ==========================================

if not report_path.is_file():
    raise FileNotFoundError(
        f"Evaluation report not found: {report_path}. "
        "Run train_random_forest.py first."
    )

report = json.loads(
    report_path.read_text(encoding="utf-8")
)

metrics = report["holdout_metrics"]

labels = metrics["confusion_matrix_labels"]

matrix = np.array(
    metrics["confusion_matrix"],
    dtype=int
)

accuracy = metrics["accuracy"]


if matrix.shape != (len(labels), len(labels)):
    raise ValueError("Invalid confusion matrix dimensions.")


# ==========================================
# CUSTOM AIDTRACK GREEN COLOR GRADIENT
# ==========================================

aidtrack_cmap = LinearSegmentedColormap.from_list(
    "aidtrack_green",
    [
        "#F4F8F5",
        "#DCE9DF",
        "#A9C9B2",
        PRIMARY_GREEN
    ]
)


# ==========================================
# CREATE FIGURE
# ==========================================

fig, ax = plt.subplots(
    figsize=(8, 6.5)
)

fig.patch.set_facecolor(WHITE)
ax.set_facecolor(WHITE)


image = ax.imshow(
    matrix,
    cmap=aidtrack_cmap,
    interpolation="nearest",
    vmin=0,
    vmax=max(1, int(matrix.max()))
)


# ==========================================
# TITLE AND SUBTITLE
# ==========================================

fig.suptitle(
    "AidTrack | Random Forest Confusion Matrix",
    fontsize=15,
    fontweight="bold",
    color=PRIMARY_GREEN,
    y=0.97
)

fig.text(
    0.5,
    0.915,
    (
        f"Synthetic Test Set | "
        f"{int(matrix.sum())} Households | "
        f"Accuracy: {accuracy:.2%}"
    ),
    ha="center",
    fontsize=9,
    color=MUTED_TEXT
)


# ==========================================
# AXIS LABELS
# ==========================================

ax.set_xticks(range(len(labels)))
ax.set_xticklabels(
    labels,
    fontsize=11,
    color=DARK_TEXT,
    fontweight="medium"
)

ax.set_yticks(range(len(labels)))
ax.set_yticklabels(
    labels,
    fontsize=11,
    color=DARK_TEXT,
    fontweight="medium"
)

ax.set_xlabel(
    "Predicted Class",
    fontsize=11,
    fontweight="bold",
    color=PRIMARY_GREEN,
    labelpad=12
)

ax.set_ylabel(
    "Actual Class",
    fontsize=11,
    fontweight="bold",
    color=PRIMARY_GREEN,
    labelpad=12
)


# ==========================================
# CELL VALUES AND HIGHLIGHTS
# ==========================================

threshold = matrix.max() * 0.55

for row in range(matrix.shape[0]):
    for col in range(matrix.shape[1]):

        value = matrix[row, col]

        text_color = (
            WHITE if value >= threshold else DARK_TEXT
        )

        ax.text(
            col,
            row,
            str(value),
            ha="center",
            va="center",
            fontsize=14,
            fontweight="bold",
            color=text_color
        )

        # Highlight correct predictions on diagonal
        if row == col:

            highlight = Rectangle(
                (col - 0.48, row - 0.48),
                0.96,
                0.96,
                fill=False,
                edgecolor=ACCENT_YELLOW,
                linewidth=2.5
            )

            ax.add_patch(highlight)


# ==========================================
# CLEAN GRID AND BORDERS
# ==========================================

ax.set_xticks(
    np.arange(-0.5, len(labels), 1),
    minor=True
)

ax.set_yticks(
    np.arange(-0.5, len(labels), 1),
    minor=True
)

ax.grid(
    which="minor",
    color=WHITE,
    linestyle="-",
    linewidth=3
)

ax.tick_params(
    which="minor",
    bottom=False,
    left=False
)

for spine in ax.spines.values():
    spine.set_visible(False)


# ==========================================
# COLOR BAR
# ==========================================

colorbar = fig.colorbar(
    image,
    ax=ax,
    fraction=0.046,
    pad=0.04
)

colorbar.set_label(
    "Number of Households",
    color=DARK_TEXT,
    fontsize=9
)

colorbar.ax.tick_params(
    colors=MUTED_TEXT,
    labelsize=9
)


# ==========================================
# SAVE IMAGE
# ==========================================

evaluation_dir.mkdir(
    parents=True,
    exist_ok=True
)

fig.subplots_adjust(
    top=0.84,
    bottom=0.15,
    left=0.17,
    right=0.90
)

fig.savefig(
    output_path,
    dpi=300,
    bbox_inches="tight",
    facecolor=WHITE
)

plt.close(fig)


print("\nAidTrack confusion matrix generated successfully!")
print(f"Saved location: {output_path}")
