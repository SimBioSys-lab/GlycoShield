#!/bin/bash
# Test Burgly Integration with Pipeline

set -e

echo "╔══════════════════════════════════════════════════════════════╗"
echo "║         Burgly Integration Test                              ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""

BASE_DIR="/projects/SimBioSys/share/software/GlycoShield"
cd "$BASE_DIR"

# Test data
ALIGNED_PDB="outputs/4e34e3d3-462c-4255-a7b5-b44b045dd795/spikeD/output_aligned.pdb"
GLYC_DAT="inputs/000f01d0-0f87-434f-b970-12229c904dcf/spikeD/glyc.dat"

echo "Test 1: Verify Pipeline Configuration"
echo "======================================="

if grep -q "BURGLY_ANALYSIS" pipeline.sh; then
    echo "✓ BURGLY_ANALYSIS variable found in pipeline.sh"
else
    echo "✗ BURGLY_ANALYSIS variable NOT found in pipeline.sh"
    exit 1
fi

if grep -q "Step 4.5: Submitting Burgly Analysis Jobs" pipeline.sh; then
    echo "✓ Burgly submission section found in pipeline.sh"
else
    echo "✗ Burgly submission section NOT found"
    exit 1
fi

if grep -q "ALL_GEF_JOBS" pipeline.sh; then
    echo "✓ GEF job tracking found"
else
    echo "✗ GEF job tracking NOT found"
    exit 1
fi

echo ""
echo "Test 2: Verify SLURM Script"
echo "======================================="

SLURM_SCRIPT="Burgly/run_burgly_analysis.slurm"

if [ -f "$SLURM_SCRIPT" ]; then
    echo "✓ SLURM script exists: $SLURM_SCRIPT"
else
    echo "✗ SLURM script NOT found"
    exit 1
fi

if [ -x "$SLURM_SCRIPT" ]; then
    echo "✓ SLURM script is executable"
else
    echo "✗ SLURM script is NOT executable"
    exit 1
fi

echo ""
echo "Test 3: Verify Test Data"
echo "======================================="

if [ -f "$ALIGNED_PDB" ]; then
    echo "✓ Test aligned PDB exists"
    ls -lh "$ALIGNED_PDB"
else
    echo "✗ Test aligned PDB NOT found"
    exit 1
fi

if [ -f "$GLYC_DAT" ]; then
    echo "✓ Test glyc.dat exists"
    wc -l "$GLYC_DAT"
else
    echo "✗ Test glyc.dat NOT found"
    exit 1
fi

echo ""
echo "Test 4: Verify Python Environment"
echo "======================================="

PYTHON="/projects/SimBioSys/share/software/allosmod-env/bin/python"

if [ -f "$PYTHON" ]; then
    echo "✓ Python executable found"
    $PYTHON --version
else
    echo "✗ Python NOT found"
    exit 1
fi

echo ""
echo "Test 5: Check Python Dependencies"
echo "======================================="

echo "Checking numpy..."
if $PYTHON -c "import numpy" 2>/dev/null; then
    $PYTHON -c "import numpy; print('✓ numpy:', numpy.__version__)"
else
    echo "✗ numpy not available"
fi

echo "Checking pandas..."
if $PYTHON -c "import pandas" 2>/dev/null; then
    $PYTHON -c "import pandas; print('✓ pandas:', pandas.__version__)"
else
    echo "✗ pandas not available"
fi

echo "Checking matplotlib..."
if $PYTHON -c "import matplotlib" 2>/dev/null; then
    $PYTHON -c "import matplotlib; print('✓ matplotlib:', matplotlib.__version__)"
else
    echo "✗ matplotlib not available"
fi

echo "Checking MDAnalysis..."
if $PYTHON -c "import MDAnalysis" 2>/dev/null; then
    $PYTHON -c "import MDAnalysis; print('✓ MDAnalysis:', MDAnalysis.__version__)"
else
    echo "✗ MDAnalysis NOT installed - REQUIRED"
    echo "  Install: $PYTHON -m pip install MDAnalysis"
fi

echo "Checking open3d..."
if $PYTHON -c "import open3d" 2>/dev/null; then
    $PYTHON -c "import open3d; print('✓ open3d:', open3d.__version__)"
else
    echo "✗ open3d NOT installed - REQUIRED"
    echo "  Install: $PYTHON -m pip install open3d"
fi

echo "Checking pymol..."
if $PYTHON -c "import pymol" 2>/dev/null; then
    $PYTHON -c "import pymol; print('✓ pymol:', pymol.__version__)"
else
    echo "⚠ pymol NOT available - will use VMD alternative"
fi

echo ""
echo "Test 6: Verify Burgly Scripts"
echo "======================================="

if [ -f "Burgly/burgly.py" ]; then
    echo "✓ burgly.py exists"
    python3 -m py_compile Burgly/burgly.py && echo "✓ burgly.py syntax valid"
else
    echo "✗ burgly.py NOT found"
    exit 1
fi

if [ -f "Burgly/burgly_heatmap.py" ]; then
    echo "✓ burgly_heatmap.py exists"
    python3 -m py_compile Burgly/burgly_heatmap.py && echo "✓ burgly_heatmap.py syntax valid"
else
    echo "✗ burgly_heatmap.py NOT found"
    exit 1
fi

echo ""
echo "Test 7: Verify Log Directories"
echo "======================================="

if grep -q "BURGLY_LOG_DIR" pipeline.sh; then
    echo "✓ BURGLY_LOG_DIR configured in pipeline.sh"
else
    echo "✗ BURGLY_LOG_DIR NOT configured"
fi

echo ""
echo "Test 8: Pipeline Syntax Check"
echo "======================================="

if bash -n pipeline.sh; then
    echo "✓ pipeline.sh syntax valid"
else
    echo "✗ pipeline.sh has syntax errors"
    exit 1
fi

echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║         Integration Test Summary                             ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""
echo "Pipeline Configuration:     ✓ Complete"
echo "SLURM Script:               ✓ Ready"
echo "Test Data:                  ✓ Available"
echo "Python Environment:         ✓ Found"
echo "Burgly Scripts:             ✓ Valid"
echo ""
echo "Next Steps:"
echo "1. Install missing dependencies if any (MDAnalysis, open3d)"
echo "2. Test SLURM submission:"
echo "   sbatch Burgly/run_burgly_analysis.slurm \\"
echo "     $ALIGNED_PDB \\"
echo "     $GLYC_DAT"
echo ""
echo "3. Or run full pipeline test"
echo ""

