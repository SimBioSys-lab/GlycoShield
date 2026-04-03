# GlycoShield

Automated HPC pipeline for analyzing glycan shielding on viral glycoproteins (HIV Env BG505, SARS-CoV-2 Spike, etc.). Generates a structural ensemble via AllosMod and runs three parallel analyses to quantify glycan surface exposure, burial depth, and interglycan interactions.

---

## Pipeline Overview

```
AllosMod (GPU)  →  Ensemble Modeling  →  GEF Analysis
                                               ├── Burgly Depth Analysis      (parallel)
                                               └── Madison Adjacency Analysis (parallel)
                                                         └── Upload to Azure + Email
```

---

## Full Pipeline

### Command
```bash
cd /projects/SimBioSys/share/software/GlycoShield
./pipeline.sh <FOLDER_PATH>
```

### Input Structure
```
inputs/
└── <user_id>/                        ← FOLDER_PATH
    ├── metadata.txt
    └── <model_name>/                ← one subfolder per protein
        ├── start.pdb
        ├── align.ali
        ├── glyc.dat
        └── input.dat
```

### File Contents

**`metadata.txt`** — top-level job identity
```
USER_ID=0016a0a1-3279-4f61-b096-0969fd5652f0
EMAIL=user@example.com
JOB_NAME=spike_analysis
NAME=Jane Doe
```
Each model subfolder can also have its own `metadata.txt` for per-model overrides (e.g. `GEF_PROBE_RADIUS`).

**`start.pdb`** — single protomer chain (chain A), standard PDB format
```
CRYST1    0.000    0.000    0.000  90.00  90.00  90.00 P 1           1
ATOM      1  N   GLN A  14     -27.519  56.544  45.544  1.00  0.00
ATOM      2  CA  GLN A  14     -28.769  55.874  45.304  1.00  0.00
...
```

**`align.ali`** — PIR alignment defining the oligomeric state
```
>P1;pm.pdb
sequence:pm.pdb:       : :       : ::: 0:0
QCVNLTTRTQLPPA...NNTVYDPLQPELDS/     ← chain 1, ends with /
QCVNLTTRTQLPPA...NNTVYDPLQPELDS/     ← chain 2, ends with /
QCVNLTTRTQLPPA...NNTVYDPLQPELDS*     ← last chain, ends with *
```
> **Rule:** 2 slashes = trimer (3 chains → CHA/CHB/CHC) | 5 slashes = dimer-of-trimers (6 chains → CHA–CHF)

**`glyc.dat`** — glycan tree definitions in AllosMod format
```
NAG NGLB 4      ← glycan attached to protein residue 4 (Asn); NGLB = N-linked
NAG 14bb 1      ← sugar type, linkage (1-4 beta), parent index in this tree
BMA 14bb 2
MAN 13ab 3
MAN 16ab 3
FUC 16fu 1      ← fucose branch

NAG NGLB 48     ← next glycan, attached to residue 48
...
```
> File contains data for all 3 protomers (3× repeated). Burgly/Madison only read the first third.

**`input.dat`** — AllosMod run settings
```
NRUNS=1              # ensemble size (1–2 for testing, 50–200 for production)
ATTACH_GAPS=True
GEF_PROBE_RADIUS=3   # probe cylinder radius in Angstroms (default: 3)
```

### Output Location
```
outputs/<USER_ID>/<model_name>/
├── ensemble/
│   ├── output.pdb              # raw multi-frame PDB (END-delimited)
│   └── output_aligned.pdb      # backbone-aligned ensemble  ← input to all downstream steps
├── gef/
│   ├── processed_GEF_output.csv
│   └── gef_data_range_*.png
├── burgly/
│   ├── glycan_depth_CAR1.csv
│   ├── glycan_depth_CAR2.csv
│   ├── glycan_depth_CAR3.csv
│   └── glycan_depth_heatmap.png
└── interglycan_interactions/
    ├── aggregated_adjacency_matrix_sum.csv
    └── *.png

logs/<USER_ID>/
├── pipeline/
├── allosmod_run/
├── ensemble_modelling/
├── gef_analysis/
├── burgly_analysis/
└── madison_analysis/
```

---

## Running Individual Steps

> All steps below assume you're in `/projects/SimBioSys/share/software/GlycoShield`.
> If you already have `output_aligned.pdb`, you can skip straight to GEF / Burgly / Madison.

---

### Step 1 — AllosMod (Ensemble Generation)

Generates `NRUNS` glycosylated structural models using MODELLER.

```bash
sbatch run_allosmod_lib.sh <FOLDER_PATH>
```

| | |
|---|---|
| **Needs** | `start.pdb`, `align.ali`, `glyc.dat`, `input.dat` (with `NRUNS=N`), `metadata.txt` |
| **SLURM** | GPU H200, 128G RAM, 8h |
| **Output** | `<model>/pred_dECALCrAS1000/<model>.pdb_{N}/pm.pdb.B99990001.pdb` |

Note: For allosmod outputs are stored under the input FOLDER_PATH/pred_dECALCrAS1000

---

### Step 2 — Ensemble Modeling

Extracts protein + glycan chains from each AllosMod frame, renumbers them, and produces a backbone-aligned multi-frame PDB.

```bash
sbatch \
  --export=ALL \
  --chdir="<model_folder>" \
  --output="logs/<USER_ID>/ensemble_modelling/get_pdb-%j.out" \
  --error="logs/<USER_ID>/ensemble_modelling/get_pdb-%j.err" \
  Ensemble-Modelling/get_pdb.sh <model_folder>
```

| | |
|---|---|
| **Needs** | AllosMod output in `pred_dECALCrAS1000/`, `align.ali`, `metadata.txt` |
| **SLURM** | 8 CPU, 32G RAM, 4h |
| **Output** | `outputs/<USER_ID>/<model>/ensemble/output_aligned.pdb` |

Note: <model_folder> is the same as allosmod output folder FOLDER_PATH/pred_dECALCrAS1000

---

### Step 3 — GEF Analysis

Calculates Geometric Exposure Factor — directional glycan coverage per residue across X/Y/Z axes using VMD probe counting.

```bash
sbatch GEF/run_gef_analysis.slurm \
    <path/to/output_aligned.pdb> \
    [system_type] \
    [probe_radius]
```

```bash
# system_type options: auto (default) | monomer | dimer | trimer
# probe_radius: Angstroms, default 3

# Convenience wrapper (auto-detects system type):
GEF/submit_gef.sh <path/to/output_aligned.pdb> [system_type]
```

| | |
|---|---|
| **Needs** | `output_aligned.pdb` |
| **SLURM** | 4 CPU, 32G RAM, 48h |
| **Output** | `outputs/<USER_ID>/<model>/gef/` |

```
processed_GEF_output.csv    # normalized GEF value (0–1) per residue
gef_data_range_*.png        # visualization plots
```

---

### Step 4 — Burgly Depth Analysis

Measures signed distance of each glycan residue from the protein surface.
- Negative = buried below surface
- Zero = at surface
- Positive = exposed above surface

```bash
sbatch Burgly/run_burgly_analysis.slurm \
    <path/to/output_aligned.pdb> \
    <path/to/glyc.dat>
```

| | |
|---|---|
| **Needs** | `output_aligned.pdb`, `glyc.dat` |
| **SLURM** | 4 CPU, 32G RAM, 24h |
| **Python env** | `pymol3` conda at `/projects/SimBioSys/jkant/miniconda3-jkant/.../envs/pymol3` |
| **Output** | `outputs/<USER_ID>/<model>/burgly/` |

```
glycan_depth_CAR1.csv       # depth per residue, protomer 1
glycan_depth_CAR2.csv       # depth per residue, protomer 2
glycan_depth_CAR3.csv       # depth per residue, protomer 3
glycan_depth_heatmap.png    # 3-panel heatmap: red=buried | white=surface | blue=exposed
```

---

### Step 5 — Madison Adjacency Analysis

Calculates interglycan spatial interactions — which glycans come within 6Å of each other across the full trajectory.

```bash
sbatch Madison_Scripts/run_madison_analysis.slurm \
    <path/to/output_aligned.pdb> \
    <path/to/glyc.dat>
```

| | |
|---|---|
| **Needs** | `output_aligned.pdb`, `glyc.dat` |
| **SLURM** | 8 CPU, 32G RAM, 24h |
| **Output** | `outputs/<USER_ID>/<model>/interglycan_interactions/` |

```
aggregated_adjacency_matrix_sum.csv    # N×N glycan adjacency matrix
CAR1 Intra-Protomer Glycan Closeness.png
CAR2 Intra-Protomer Glycan Closeness.png
CAR3 Intra-Protomer Glycan Closeness.png
Average Intra-Protomer Glycan Closeness.png
# colormap: white → yellow → orange → red → black (low → high interaction)
```

---

## Monitoring Jobs

```bash
# All your running jobs
squeue -u $USER

# Watch pipeline submission log
tail -f logs/<USER_ID>/pipeline/pipeline_<timestamp>.log

# Watch a specific stage
tail -f logs/<USER_ID>/gef_analysis/gef_run_<JOB_ID>.log
tail -f logs/<USER_ID>/burgly_analysis/burgly_run_<JOB_ID>.log

# Check job exit status
sacct -j <JOB_ID> --format=JobID,JobName,State,ExitCode,Elapsed
```

---

## Environment & Dependencies

| Component | Tool | Location |
|-----------|------|----------|
| AllosMod + MODELLER | `allosmod-env` conda | `/projects/SimBioSys/share/software/allosmod-env` |
| VMD | `VMD/1.9.4a55` module | HPC module system |
| GEF Python | mdtraj, pandas, numpy, matplotlib | `allosmod-env` |
| Burgly Python | PyMOL, MDAnalysis, Open3D | `pymol3` conda env |
| Madison Python | MDAnalysis, seaborn, matplotlib | `allosmod-env` |
| PDB tools | pdb_tidy, pdb_reres, pdb_reatom, pdb_selchain | `allosmod-env` |
| Azure SDK | azure-storage-blob 12.19.1 | vendored in `lib/python/` |

Configuration is loaded from `.env` — see `.env.example` for all options.

---

## Project Layout

```
GlycoShield/
├── pipeline.sh                          # main orchestrator
├── run_allosmod_lib.sh                  # Step 1: AllosMod submission
├── send_completion_email_login.sh       # Azure upload + email on completion
├── trigger_email.py                     # SMTP email sender
├── azure_glycoshield.py                 # Azure Blob CRUD
├── generate_azure_index.py              # HTML results browser generator
├── .env / .env.example                  # configuration
├── Ensemble-Modelling/
│   ├── get_pdb.sh                       # Step 2 orchestrator
│   ├── config/defaults.conf
│   └── lib/
│       ├── common.sh                    # logging, modules, env setup
│       ├── alignment_parser.sh          # parse .ali → chain count
│       ├── glycan_calculator.sh         # HETATM range → 3-chain split
│       ├── pdb_processor.sh             # VMD extraction, renumber, concat
│       └── orchestrator.sh             # frame iteration glue
├── GEF/
│   ├── run_gef_analysis.slurm           # Step 3 SLURM job
│   ├── main_script.py                   # GEF core logic
│   └── GEF_probe.tcl                    # VMD directional counting
├── Burgly/
│   ├── run_burgly_analysis.slurm        # Step 4 SLURM job
│   ├── burgly.py                        # surface depth via PyMOL + Open3D
│   └── burgly_heatmap.py                # heatmap generator
└── Madison_Scripts/
    ├── run_madison_analysis.slurm       # Step 5 SLURM job
    ├── create_adj_matrix.py             # MDAnalysis pairwise distances
    └── cleaned_finalized_script.py      # normalize + plot adjacency heatmaps
```
