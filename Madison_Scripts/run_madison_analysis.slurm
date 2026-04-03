#!/bin/bash
#SBATCH --job-name=madison_analysis
#SBATCH --partition=short
#SBATCH --time=24:00:00
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=8
#SBATCH --mem=32G
#SBATCH -o madison_%j.out
#SBATCH -e madison_%j.err

# Madison Analysis Pipeline - Glycan Adjacency Matrix Analysis
# This script runs the complete Madison workflow:
# 1. Preprocessing (clean PDB, remove H atoms)
# 2. Create adjacency matrices (can be parallelized for large files)
# 3. Aggregate results
# 4. Generate final heatmaps
# UPDATED: Outputs to interglycan_interactions/ subfolder (renamed from madison_analysis)
# UPDATED: Improved cleanup of intermediate files

echo "============================================"
echo "Madison Glycan Adjacency Analysis Pipeline"
echo "============================================"
echo "Job ID: $SLURM_JOB_ID"
echo "Start time: $(date)"
echo "Running on node: $(hostname)"
echo "============================================"

# Check arguments
if [ $# -lt 2 ]; then
    echo "Usage: sbatch run_madison_analysis.slurm <aligned_pdb> <glyc_dat>"
    echo "Example: sbatch run_madison_analysis.slurm /path/to/ensemble/output_aligned.pdb /path/to/glyc.dat"
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

# Create interglycan_interactions/ subfolder for outputs (renamed from madison_analysis)
MADISON_OUTPUT_DIR="${MODEL_OUTPUT_DIR}/interglycan_interactions"
mkdir -p "$MADISON_OUTPUT_DIR"

# Set paths
SCRIPT_DIR="/projects/SimBioSys/share/software/GlycoShield/Madison_Scripts"
PYTHON_EXEC="/projects/SimBioSys/share/software/allosmod-env/bin/python"

# Check inputs
if [ ! -f "$ALIGNED_PDB" ]; then
    echo "ERROR: Aligned PDB not found at $ALIGNED_PDB"
    exit 1
fi

if [ ! -f "$GLYC_DAT" ]; then
    echo "ERROR: glyc.dat not found at $GLYC_DAT"
    exit 1
fi

echo "Input PDB: $ALIGNED_PDB"
echo "Glyc.dat: $GLYC_DAT"
echo "Model output directory: $MODEL_OUTPUT_DIR"
echo "Interglycan output directory: $MADISON_OUTPUT_DIR"
echo "Python: $PYTHON_EXEC"
echo ""

# Change to output directory
cd "$MADISON_OUTPUT_DIR"

# Copy glyc.dat to working directory (scripts expect it locally)
cp "$GLYC_DAT" ./glyc.dat

# Copy the aligned PDB
PDB_BASENAME=$(basename "$ALIGNED_PDB")
cp "$ALIGNED_PDB" "./$PDB_BASENAME"

# Define cleanup function to ensure intermediate files are always removed
cleanup_intermediate_files() {
    echo ""
    echo "============================================"
    echo "Cleanup"
    echo "============================================"
    
    # Clean up intermediate files
    rm -f "clean_${PDB_BASENAME}" 2>/dev/null && echo "  Removed clean_${PDB_BASENAME}"
    rm -f "clean_no_ends_${PDB_BASENAME}" 2>/dev/null && echo "  Removed clean_no_ends_${PDB_BASENAME}"
    rm -f "$PDB_BASENAME" 2>/dev/null && echo "  Removed $PDB_BASENAME"
    rm -f create_adj_matrix.py 2>/dev/null && echo "  Removed create_adj_matrix.py"
    rm -f cleaned_finalized_script.py 2>/dev/null && echo "  Removed cleaned_finalized_script.py"
    rm -f glyc.dat 2>/dev/null && echo "  Removed glyc.dat"
    
    echo "Cleanup complete."
}

# Set trap to run cleanup on exit (success or failure)
trap cleanup_intermediate_files EXIT

echo "============================================"
echo "Step 1: Preprocessing PDB"
echo "============================================"

# Run preprocessing inline (simplified version without splitting for now)
$PYTHON_EXEC << PREPROCESS_EOF
import mdtraj as md
import os

input_file = "$PDB_BASENAME"
print(f"Loading {input_file}...")
traj = md.load(input_file)
print(f"Loaded {traj.n_frames} frames")

# Step 1: Remove hydrogen atoms
print("Removing hydrogen atoms...")
with open(input_file, 'r') as file:
    lines = file.readlines()

clean_file = f"clean_{input_file}"
with open(clean_file, 'w') as new_file:
    for line in lines:
        words = line.split()
        if len(words) < 3:
            new_file.write(line)
        elif 'END' in line:
            new_file.write(line)
        elif not words[2].startswith('H'):
            new_file.write(line)

print(f"Created {clean_file}")

# Step 2: Remove standalone END lines but preserve MODEL/ENDMDL markers
# IMPORTANT: 'END' in line would also match ENDMDL, which breaks multi-model PDBs.
# We only strip lines that are exactly "END" (with optional whitespace), 
# preserving MODEL and ENDMDL so MDAnalysis can properly read the trajectory.
print("Removing standalone END lines (preserving MODEL/ENDMDL markers)...")
no_ends_file = f"clean_no_ends_{input_file}"
with open(clean_file, 'r') as file:
    lines = file.readlines()

with open(no_ends_file, 'w') as new_file:
    for line in lines:
        stripped = line.strip()
        # Only skip standalone "END" lines, NOT "ENDMDL" or "MODEL"
        if stripped == 'END':
            continue
        new_file.write(line)
    new_file.write('END\n')

print(f"Created {no_ends_file}")
print("Preprocessing complete!")
PREPROCESS_EOF

PREPROCESS_EXIT=$?
if [ $PREPROCESS_EXIT -ne 0 ]; then
    echo "ERROR: Preprocessing failed"
    exit 1
fi

echo ""
echo "============================================"
echo "Step 2: Creating Adjacency Matrix"
echo "============================================"

# Copy the adjacency matrix script
cp "$SCRIPT_DIR/create_adj_matrix.py" ./

# Run adjacency matrix calculation on the cleaned PDB
CLEAN_PDB="clean_no_ends_${PDB_BASENAME}"

$PYTHON_EXEC create_adj_matrix.py "$CLEAN_PDB"

ADJ_EXIT=$?
if [ $ADJ_EXIT -ne 0 ]; then
    echo "ERROR: Adjacency matrix calculation failed"
    exit 1
fi

echo ""
echo "============================================"
echo "Step 3: Generating Visualizations"
echo "============================================"

# Check if adjacency matrix was created
ADJ_CSV=$(ls *_adjacency_matrix.csv 2>/dev/null | head -1)
if [ -z "$ADJ_CSV" ]; then
    echo "ERROR: No adjacency matrix CSV found!"
    exit 1
fi

echo "Found adjacency matrix: $ADJ_CSV"

# Rename to expected filename for the finalized script
cp "$ADJ_CSV" aggregated_adjacency_matrix_sum.csv

# Copy and run the visualization script
cp "$SCRIPT_DIR/cleaned_finalized_script.py" ./

$PYTHON_EXEC cleaned_finalized_script.py

VIZ_EXIT=$?
if [ $VIZ_EXIT -ne 0 ]; then
    echo "WARNING: Visualization script had issues (exit code: $VIZ_EXIT)"
    echo "Continuing anyway - adjacency matrix is still valid"
fi

echo ""
echo "============================================"
echo "Summary"
echo "============================================"

# List outputs (before cleanup)
echo "Output files in $MADISON_OUTPUT_DIR:"
ls -lh "$MADISON_OUTPUT_DIR" | grep -v "^total" | grep -v "clean_" | grep -v "create_adj" | grep -v "cleaned_finalized" | grep -v "glyc.dat"

echo ""
echo "============================================"
echo "Interglycan Interactions Analysis Complete!"
echo "============================================"
echo "End time: $(date)"
echo ""
echo "Key outputs:"
echo "  - Adjacency matrix: aggregated_adjacency_matrix_sum.csv"
echo "  - Heatmaps: *.png"
echo ""

# Cleanup will run via EXIT trap
exit 0
