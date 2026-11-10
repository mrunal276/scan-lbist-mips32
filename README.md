# Scan-Based Logic Built-In Self-Test (LBIST) for MIPS32

A VHDL implementation of a **STUMPS-style Logic Built-In Self-Test (LBIST)** architecture wrapped around a **5-stage pipelined MIPS32 processor** with full scan insertion — implemented and simulated in **Xilinx Vivado 2025.1**.

---

## 📐 Architecture Overview

```
BIST Controller
     │
     ▼
  PRPG (Pseudo-Random Pattern Generator)
     │
     ├──▶ TC_GEN (Toggle-Control Generator)   ← tc_en=1 for proposed mode
     │
     ▼
  16 × Scan Chains  ──▶  MIPS32 Scan Core (mips_scan_core)
                                │
                                ▼
                           MISR (Multiple-Input Signature Register)
                                │
                                ▼
                           Signature (32-bit)
```

### Key Design Modes
| Mode | `tc_en` | Description |
|------|---------|-------------|
| Conventional LBIST | `0` | Baseline — PRPG drives scan chains directly |
| Proposed Toggle-Control LBIST | `1` | TC_GEN limits toggle rate to `t/256` to reduce power |

---

## 📁 Project Structure

```
course_project/
│
├── course_project.xpr              # Vivado project file (open this in Vivado)
├── tb_lbist_behav.wcfg             # Waveform config for LBIST testbench
│
├── course_project.srcs/            # ← All VHDL source files
│   ├── sources_1/new/              # Design sources
│   │   ├── mips_pkg.vhd            # Package: types & constants for MIPS32
│   │   ├── lbist_pkg.vhd           # Package: LBIST parameters (N_CHAINS, N_CELLS, etc.)
│   │   ├── alu.vhd                 # Arithmetic Logic Unit
│   │   ├── regfile.vhd             # 32×32 Register File
│   │   ├── mips_comb.vhd           # Combinational datapath
│   │   ├── mips32.vhd              # 5-stage pipelined MIPS32 core (IF→ID→EX→MEM→WB)
│   │   ├── mips_scan_core.vhd      # MIPS32 with 16 scan chains inserted
│   │   ├── prpg.vhd                # LFSR-based Pseudo-Random Pattern Generator
│   │   ├── misr.vhd                # Multiple-Input Signature Register
│   │   ├── tc_gen.vhd              # Toggle-Control Generator
│   │   ├── bist_ctrl.vhd           # BIST FSM Controller
│   │   └── lbist_top.vhd           # Top-level: STUMPS LBIST wrapping full-scan MIPS32
│   │
│   └── sim_1/new/                  # Testbenches
│       ├── tb_mips32.vhd           # Testbench: functional verification of MIPS32
│       ├── tb_mips32_scan.vhd      # Testbench: scan insertion correctness check
│       └── tb_lbist.vhd            # Testbench: full LBIST run (conventional + toggle-control)
│
├── course_project.sim/             # ← Simulation outputs (logs, waveforms, results)
│   └── sim_1/behav/xsim/
│       ├── simulate.log            # Simulation console output
│       ├── elaborate.log           # Elaboration log
│       ├── lbist_results.csv       # LBIST metrics: toggle%, coverage%, MISR signature
│       ├── tb_lbist_behav.wdb      # Waveform database (open in Vivado)
│       ├── tb_mips32_behav.wdb     # Waveform database for MIPS32 functional sim
│       ├── compile.bat             # Vivado xvhdl compile script
│       ├── elaborate.bat           # Vivado xelab elaboration script
│       └── simulate.bat            # Vivado xsim simulation script
│
├── course_project.hw/              # Hardware manager state
└── course_project.cache/           # Vivado compile cache
```

---

## 🧩 Source File Descriptions

### Design Sources (`sources_1/new/`)

| File | Description |
|------|-------------|
| `mips_pkg.vhd` | Shared types (`word_t`, `reg_t`), constants, and subprogram declarations for the MIPS32 |
| `lbist_pkg.vhd` | LBIST constants: `N_CHAINS` (scan chains), `N_CELLS` (flip-flops), `N_PS` (PRPG size) |
| `alu.vhd` | 32-bit ALU: ADD, SUB, AND, OR, XOR, NOR, SLT, SLL, SRL |
| `regfile.vhd` | 32 × 32-bit register file with dual read ports and one write port |
| `mips_comb.vhd` | Combinational decode, forwarding MUXes, and hazard logic |
| `mips32.vhd` | Full 5-stage pipeline (IF/ID/EX/MEM/WB) with forwarding & hazard detection |
| `mips_scan_core.vhd` | Scan-instrumented MIPS32: flip-flops replaced with scan flip-flops in 16 chains |
| `prpg.vhd` | 32-bit LFSR (primitive polynomial) acting as pattern generator |
| `misr.vhd` | 32-bit MISR for compacting scan chain outputs into a signature |
| `tc_gen.vhd` | Toggle-Control: limits scan-in toggle rate to reduce dynamic power during BIST |
| `bist_ctrl.vhd` | FSM: IDLE → LOAD → SHIFT → CAPTURE → DONE, drives scan_en and pattern count |
| `lbist_top.vhd` | Top-level integrating all LBIST components around `mips_scan_core` |

### Testbenches (`sim_1/new/`)

| File | What it verifies |
|------|-----------------|
| `tb_mips32.vhd` | Functional correctness of the MIPS32 pipeline (instruction execution) |
| `tb_mips32_scan.vhd` | Scan insertion correctness — confirms scan core produces identical results to original |
| `tb_lbist.vhd` | End-to-end LBIST: runs conventional and toggle-control modes, logs metrics to `lbist_results.csv` |

---

## ✅ Simulation Results

### Scan Insertion Check
```
Note: SCAN-CORE functional test PASSED (scan insertion preserved behaviour)
Time: 1022 ns
```
> The scan-instrumented core (`mips_scan_core`) is functionally equivalent to the original `mips32` — scan insertion did **not** alter behaviour.

### LBIST Simulation Output (`lbist_results.csv`)
| Column | Description |
|--------|-------------|
| `config` | `conv` (conventional) or `tc` (toggle-control) |
| `target_pct` | Target toggle rate percentage (tc mode only) |
| `scanin_toggle_pct` | Actual scan-in toggle rate achieved |
| `cell_toggle_pct` | Cell (flip-flop) toggle rate |
| `cycles` | Clock cycles consumed |
| `misr` | 32-bit MISR signature (hex) |

### Simulation Logs
- **`elaborate.log`** — Vivado xelab elaboration; confirms no errors, used cached compiled objects
- **`simulate.log`** — Vivado xsim runtime output; shows test PASS/FAIL messages and timing

---

## 🛠 How to Open & Re-run Simulations

### Prerequisites
- **Xilinx Vivado 2025.1** (or compatible version)

### Steps
1. Open Vivado → **File → Open Project** → select `course_project.xpr`
2. In the **Sources** panel, select a testbench under `Simulation Sources / sim_1`
3. Click **Run Simulation → Run Behavioral Simulation**
4. View waveforms in the `.wdb` file or via the Vivado waveform viewer using the `.wcfg` config

### Re-running from command line (Windows)
```bat
cd course_project.sim\sim_1\behav\xsim
compile.bat
elaborate.bat
simulate.bat
```

---

## 🔑 Key Concepts

| Term | Meaning |
|------|---------|
| **DFT** | Design for Testability |
| **LBIST** | Logic Built-In Self-Test |
| **STUMPS** | Self-Test Using MISR and Parallel Shift Register Sequence |
| **PRPG** | Pseudo-Random Pattern Generator (LFSR-based) |
| **MISR** | Multiple-Input Signature Register (compact output compressor) |
| **Scan Chain** | Flip-flops connected in series for serial shift-in/out during test |
| **Toggle Rate** | % of flip-flops that toggle per clock cycle (↑ = ↑ power consumption) |
| **TC (Toggle Control)** | Proposed enhancement to cap toggle rate → reduce test power |

---

## 📋 Project Roadmap

| Step | Work | Output | Status |
|------|------|--------|--------|
| 1 | Architecture & specification (block diagram, parameters, metrics) | Spec | ✅ Done |
| 2 | VHDL MIPS32 core (5-stage pipeline, subset ISA) | `mips32.vhd` + functional testbench | ✅ Done |
| 3 | Scan insertion (scan flops, chain partitioning, scan-enable) | Scan-ready CUT | ✅ Done |
| 4 | Baseline LBIST in VHDL (LFSR, phase shifter, MISR, controller) | Conventional STUMPS | ✅ Done |
| 5 | TC-PRPG design in VHDL (threshold comparator, T-flops, programmable T) | Proposed generator | ✅ Done |
| 6 | Measurement tooling: toggle rate & WSA counters, fault simulator (stuck-at) | Testbench & scripts | ✅ Done |
| 7 | Simulation experiments: toggle rate vs. T, coverage vs. patterns, power proxy, MISR signature check | Results & plots | 🔄 In Progress |
| 8 | Performance analysis: power reduction, coverage, test time, area overhead, comparison to baselines | Analysis | ⬜ Pending |
| 9 | Final report assembly (Word/PDF) | Report | ⬜ Pending |

---

## 👥 Team

> Add your names here

---

## 📌 Tool & Version Info
- **Tool**: Xilinx Vivado 2025.1.0
- **Simulator**: Vivado Simulator (xsim)
- **Language**: VHDL (IEEE 1076-2008)
- **Target Device**: Not constrained (behavioural simulation only)

