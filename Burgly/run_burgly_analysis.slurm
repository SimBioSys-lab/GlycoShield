#!/bin/bash
#SBATCH --partition=short
#SBATCH --time=24:00:00
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=4
#SBATCH --mem=32G
#SBATCH -J burgly_analysis
#SBATCH -o burgly_%j.out
#SBATCH -e burgly_%j.err

# Burgly Analysis Pipeline
# Calculates glycan surface depth and burial patterns using PyMOL for surface generation
# UPDATED: Outputs to burgly/ subfolder (renamed from burgly_analysis)

echo "============================================"
echo "Burgly Analysis Pipeline"
echo "============================================"
echo "Job ID: $SLURM_JOB_ID"
echo "Start time: $(date)"
echo "Running on node: $(hostname)"
echo "============================================"

# Check arguments
if [ $# -lt 2 ]; then
    echo "Usage: sbatch run_burgly_analysis.slurm <aligned_pdb> <glyc_dat>"
    echo "Example: sbatch run_burgly_analysis.slurm /path/to/ensemble/output_aligned.pdb /path/to/glyc.dat"
    exit 1
fi

# Get arguments
ALIGNED_PDB="$1"
GLYC_DAT="$2"

# Convert to absolute paths
ALIGNED_PDB="$(cd "$(dirname "$ALIGNED_PDB")" && pwd)/$(basename "$ALIGNED_PDB")"
GLYC_DAT="$(cd "$(dirname "$GLYC_DAT")" && pwd)/$(basename "$GLYC_DAT")"

# Determine model output directory
PDB_DIR="$(dirname "$ALIGNED_PDB")"

# Check if the PDB is inside ensemble/ subfolder (new structure)
if [[ "$(basename "$PDB_DIR")" == "ensemble" ]]; then
    MODEL_OUTPUT_DIR="$(dirname "$PDB_DIR")"
else
    # Legacy: PDB is directly in model folder
    MODEL_OUTPUT_DIR="$PDB_DIR"
fi

# Create burgly/ subfolder for outputs (renamed from burgly_analysis)
BURGLY_OUTPUT_DIR="${MODEL_OUTPUT_DIR}/burgly"
mkdir -p "$BURGLY_OUTPUT_DIR"

# Set paths
SCRIPT_DIR="/projects/SimBioSys/share/software/GlycoShield/Burgly"
BURGLY_SCRIPT="${SCRIPT_DIR}/burgly.py"
HEATMAP_SCRIPT="${SCRIPT_DIR}/burgly_heatmap.py"

# Use the pymol3 conda environment
CONDA_ENV="/projects/SimBioSys/jkant/miniconda3-jkant/miniconda3-jkant/envs/pymol3"
PYTHON_EXEC="${CONDA_ENV}/bin/python"

# Extract user ID from path for logging (assumes structure: .../outputs/USER_ID/...)
USER_ID=$(echo "$MODEL_OUTPUT_DIR" | grep -oP "outputs/\K[^/]+")
if [ -z "$USER_ID" ]; then
    USER_ID="default_user"
fi

# Set up log directory
LOG_BASE="/projects/SimBioSys/share/software/GlycoShield/logs"
LOG_DIR="${LOG_BASE}/${USER_ID}/burgly_analysis"
mkdir -p "$LOG_DIR"

echo "============================================"
echo "Configuration"
echo "============================================"
echo "Input PDB: $ALIGNED_PDB"
echo "Glyc.dat: $GLYC_DAT"
echo "Model output directory: $MODEL_OUTPUT_DIR"
echo "Burgly output directory: $BURGLY_OUTPUT_DIR"
echo "Python: $PYTHON_EXEC"
echo "User ID: $USER_ID"
echo "Log directory: $LOG_DIR"
echo ""

# Check if scripts exist
if [ ! -f "$BURGLY_SCRIPT" ]; then
    echo "ERROR: Burgly script not found at $BURGLY_SCRIPT"
    exit 1
fi

if [ ! -f "$HEATMAP_SCRIPT" ]; then
    echo "ERROR: Heatmap script not found at $HEATMAP_SCRIPT"
    exit 1
fi

# Check if Python exists
if [ ! -f "$PYTHON_EXEC" ]; then
    echo "ERROR: Python not found at $PYTHON_EXEC"
    exit 1
fi

# Check if input files exist
if [ ! -f "$ALIGNED_PDB" ]; then
    echo "ERROR: Aligned PDB not found at $ALIGNED_PDB"
    exit 1
fi

if [ ! -f "$GLYC_DAT" ]; then
    echo "ERROR: glyc.dat not found at $GLYC_DAT"
    exit 1
fi

# Verify Python dependencies
echo "============================================"
echo "Verifying Python Dependencies"
echo "============================================"

$PYTHON_EXEC -c "import pymol; print('✓ PyMOL available')" || { echo "ERROR: PyMOL not available"; exit 1; }
$PYTHON_EXEC -c "import MDAnalysis; print('✓ MDAnalysis:', MDAnalysis.__version__)" || { echo "ERROR: MDAnalysis not available"; exit 1; }
$PYTHON_EXEC -c "import open3d; print('✓ Open3D:', open3d.__version__)" || { echo "ERROR: Open3D not available"; exit 1; }
$PYTHON_EXEC -c "import numpy; print('✓ NumPy:', numpy.__version__)" || { echo "ERROR: NumPy not available"; exit 1; }
$PYTHON_EXEC -c "import pandas; print('✓ Pandas:', pandas.__version__)" || { echo "ERROR: Pandas not available"; exit 1; }
$PYTHON_EXEC -c "import matplotlib; print('✓ Matplotlib:', matplotlib.__version__)" || { echo "ERROR: Matplotlib not available"; exit 1; }

echo ""
echo "✓ All required dependencies verified"
echo ""

# Record start time
START_TIME=$(date +%s)

echo "============================================"
echo "Step 1: Running Burgly Depth Analysis"
echo "============================================"

# Change to output directory for temporary files
cd "$BURGLY_OUTPUT_DIR"

# Run burgly to calculate residue depths
# The script expects: trajectory.pdb -gly glyc.dat -o outdir --outprefix prefix
$PYTHON_EXEC "$BURGLY_SCRIPT" \
    "$ALIGNED_PDB" \
    --glycan-data "$GLYC_DAT" \
    --outdir "$BURGLY_OUTPUT_DIR" \
    --outprefix "glycan_depth" \
    2>&1 | tee "${LOG_DIR}/burgly_run_${SLURM_JOB_ID}.log"

BURGLY_EXIT=${PIPESTATUS[0]}

if [ $BURGLY_EXIT -ne 0 ]; then
    echo "ERROR: Burgly analysis failed with exit code $BURGLY_EXIT"
    exit 1
fi

echo ""
echo "✓ Burgly depth analysis completed"
echo ""

# Check if CSV files were generated
CAR1_CSV="${BURGLY_OUTPUT_DIR}/glycan_depth_CAR1.csv"
CAR2_CSV="${BURGLY_OUTPUT_DIR}/glycan_depth_CAR2.csv"
CAR3_CSV="${BURGLY_OUTPUT_DIR}/glycan_depth_CAR3.csv"

if [ ! -f "$CAR1_CSV" ] || [ ! -f "$CAR2_CSV" ] || [ ! -f "$CAR3_CSV" ]; then
    echo "ERROR: CSV files not generated by Burgly!"
    echo "Expected files:"
    echo "  $CAR1_CSV"
    echo "  $CAR2_CSV"
    echo "  $CAR3_CSV"
    echo ""
    echo "Directory contents:"
    ls -la "$BURGLY_OUTPUT_DIR"
    exit 1
fi

echo "============================================"
echo "Step 2: Generating Heatmap Visualization"
echo "============================================"

# Generate heatmap from CSV data
$PYTHON_EXEC "$HEATMAP_SCRIPT" \
    "$CAR1_CSV" "$CAR2_CSV" "$CAR3_CSV" \
    --outdir "$BURGLY_OUTPUT_DIR" \
    --outprefix "glycan_depth" \
    --title "Glycan Surface Depth Analysis" \
    2>&1 | tee -a "${LOG_DIR}/burgly_run_${SLURM_JOB_ID}.log"

HEATMAP_EXIT=${PIPESTATUS[0]}

if [ $HEATMAP_EXIT -ne 0 ]; then
    echo "ERROR: Heatmap generation failed with exit code $HEATMAP_EXIT"
    exit 1
fi

echo ""
echo "✓ Heatmap visualization completed"
echo ""

# Calculate runtime
END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))
HOURS=$((DURATION / 3600))
MINUTES=$(((DURATION % 3600) / 60))
SECONDS=$((DURATION % 60))

echo "============================================"
echo "Burgly Analysis Complete!"
echo "============================================"
echo "End time: $(date)"
echo "Total runtime: ${HOURS}h ${MINUTES}m ${SECONDS}s"
echo ""
echo "Output files:"
ls -lh "$BURGLY_OUTPUT_DIR"
echo ""
echo "CSV files:"
echo "  $CAR1_CSV"
echo "  $CAR2_CSV"
echo "  $CAR3_CSV"
echo ""
echo "Heatmap:"
echo "  ${BURGLY_OUTPUT_DIR}/glycan_depth_heatmap.png"
echo ""
echo "============================================"

exit 0
