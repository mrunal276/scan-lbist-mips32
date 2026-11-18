# generate_plots.py : Generates publication-grade figures directly from Vivado CSV outputs
import os
import pandas as pd
import matplotlib.pyplot as plt
import numpy as np

# Resolve project directories dynamically
BASE_DIR = os.path.dirname(os.path.abspath(__file__))
SIM_DIR = os.path.join(BASE_DIR, "course_project.sim", "sim_1", "behav", "xsim")
DOCS_IMG_DIR = os.path.join(BASE_DIR, "docs", "images")
os.makedirs(DOCS_IMG_DIR, exist_ok=True)

LBIST_CSV = os.path.join(SIM_DIR, "lbist_results.csv")
FAULT_CSV = os.path.join(SIM_DIR, "fault_coverage.csv")

plt.rcParams.update({
    "font.family": "sans-serif",
    "font.size": 10,
    "axes.titlesize": 11,
    "axes.titleweight": "bold",
    "axes.grid": True,
    "grid.alpha": 0.3,
    "figure.dpi": 300
})

# ==============================================================================
# 1. Load & Merge CSV Data Directly
# ==============================================================================
df_lbist = pd.read_csv(LBIST_CSV)
df_fault = pd.read_csv(FAULT_CSV)

# Exclude the repeatability check row from main sweep plots
df = df_lbist[df_lbist["config"] != "TC_T26_repeat"].copy()
df = df.merge(df_fault[["config", "fault_coverage_pct"]], on="config", how="left")

# Calculate dynamic shift power reduction relative to CONVENTIONAL baseline
conv_cell_tog = df.loc[df["config"] == "CONVENTIONAL", "cell_toggle_pct"].values[0]
df["power_red_pct"] = (1.0 - (df["cell_toggle_pct"] / conv_cell_tog)) * 100.0

labels = [c.replace("CONVENTIONAL", "CONV\n(tc_en=0)").replace("_", "\n(") + (")" if "_" in c else "")
          for c in df["config"]]

def save_fig(filename):
    plt.savefig(os.path.join(DOCS_IMG_DIR, filename), bbox_inches="tight")

# ==============================================================================
# Figure 1: Toggle-Rate Control Accuracy & Cell Switching Activity
# ==============================================================================
fig, ax = plt.subplots(figsize=(8, 4.5))
x = np.arange(len(df))
w = 0.22

ax.bar(x - 1.5*w, df["target_pct"],           width=w, label="Target Toggle Rate (T/256)", color="#4A6FE3")
ax.bar(x - 0.5*w, df["scanin_toggle_pct"],    width=w, label="Actual Scan-In Toggle Rate (%)", color="#11A579")
b3 = ax.bar(x + 0.5*w, df["cell_toggle_pct"], width=w, label="Avg Scan Cell Toggle Rate (%)", color="#E68310")
ax.bar(x + 1.5*w, df["peak_cell_toggle_pct"], width=w, label="Peak Cycle Cell Toggle Rate (%)", color="#CF1C90")

ax.set_ylabel("Toggle Activity (% of Transitions / Cycle)")
ax.set_title("Programmable Toggle-Rate Control & Scan Cell Switching Activity")
ax.set_xticks(x)
ax.set_xticklabels(labels)
ax.set_ylim(0, 62)
ax.legend(loc="upper left", frameon=True, fontsize=8.5)

for bar in b3:
    h = bar.get_height()
    ax.text(bar.get_x() + bar.get_width()/2, h + 0.8, f"{h:.1f}%", ha="center", va="bottom", fontsize=7.5)

plt.tight_layout()
save_fig("fig1_toggle_control_accuracy.png")
plt.close()

# ==============================================================================
# Figure 2: Dynamic Shift Power Reduction vs. Stuck-At Fault Coverage
# ==============================================================================
df_tc = df[df["config"] != "CONVENTIONAL"].copy()
tc_labels = [f"{r['config']}\n({r['target_pct']:.1f}%)" for _, r in df_tc.iterrows()]

fig, ax1 = plt.subplots(figsize=(7.5, 4.2))
x2 = np.arange(len(df_tc))

bars = ax1.bar(x2, df_tc["power_red_pct"], width=0.45, color="#1F77B4", alpha=0.88,
               label="Avg Shift Power Reduction (%)")
ax1.set_ylabel("Shift Switching Power Reduction vs. Conv. (%)", color="#1F77B4")
ax1.tick_params(axis="y", labelcolor="#1F77B4")
ax1.set_xticks(x2)
ax1.set_xticklabels(tc_labels)
ax1.set_ylim(0, 105)

for bar in bars:
    h = bar.get_height()
    ax1.text(bar.get_x() + bar.get_width()/2, h + 1.5, f"{h:.1f}%", ha="center", va="bottom",
             fontsize=8.5, fontweight="bold", color="#1F77B4")

ax2 = ax1.twinx()
ax2.plot(x2, df_tc["fault_coverage_pct"], color="#D62728", marker="o", linewidth=2.2,
         markersize=7, label="Stuck-At Fault Coverage (%)")
ax2.set_ylabel("Stuck-At Fault Coverage (%)", color="#D62728")
ax2.tick_params(axis="y", labelcolor="#D62728")
ax2.set_ylim(0, 115)
ax2.grid(False)

plt.title("Dynamic Shift Power Reduction vs. Fault Coverage Across Thresholds (T)")
lines1, labels1 = ax1.get_legend_handles_labels()
lines2, labels2 = ax2.get_legend_handles_labels()
ax1.legend(lines1 + lines2, labels1 + labels2, loc="center right", frameon=True, fontsize=8.5)

plt.tight_layout()
save_fig("fig2_power_vs_coverage.png")
plt.close()

# ==============================================================================
# Figure 3: Hierarchical FPGA Hardware Utilization (Zynq-7000 xc7z010clg400-1)
# ==============================================================================
modules = ["mips_scan_core\n(CUT)", "prpg\n(LFSR + Phase Shifter)", "bist_ctrl\n(FSM)", "misr + tc_gen\n(Compactor + TC)"]
luts    = [2620, 187, 61, 21]
ffs     = [1465,  32, 27, 48]

fig, ax = plt.subplots(figsize=(7.5, 4.0))
x3 = np.arange(len(modules))
w3 = 0.35

r1 = ax.bar(x3 - w3/2, luts, width=w3, label="Slice LUTs (Total: 2,889)", color="#3B528B")
r2 = ax.bar(x3 + w3/2, ffs,  width=w3, label="Slice Flip-Flops (Total: 1,572)", color="#21918C")

ax.set_ylabel("Resource Count (Zynq xc7z010clg400-1)")
ax.set_title("Hierarchical Synthesis Utilization & Hardware Overhead Breakdown")
ax.set_xticks(x3)
ax.set_xticklabels(modules)
ax.set_ylim(0, 2950)
ax.legend(loc="upper right", frameon=True)

for bar in r1:
    h = bar.get_height()
    ax.text(bar.get_x() + bar.get_width()/2, h + 35, str(h), ha="center", va="bottom", fontsize=8)
for bar in r2:
    h = bar.get_height()
    ax.text(bar.get_x() + bar.get_width()/2, h + 35, str(h), ha="center", va="bottom", fontsize=8)

plt.tight_layout()
save_fig("fig3_fpga_area_overhead.png")
plt.close()

print("Successfully generated all 3 PNG charts in docs/images directory.")
