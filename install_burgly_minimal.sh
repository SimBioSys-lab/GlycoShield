#!/bin/bash
# Install minimal Burgly dependencies (without PyMOL)

set -e

PYTHON_BIN="/projects/SimBioSys/share/software/allosmod-env/bin/python"
PIP_BIN="/projects/SimBioSys/share/software/allosmod-env/bin/pip"

echo "Installing MDAnalysis..."
$PIP_BIN install MDAnalysis

echo ""
echo "Installing Open3D..."
$PIP_BIN install open3d

echo ""
echo "Verifying installations..."
$PYTHON_BIN -c "import MDAnalysis; print('✓ MDAnalysis:', MDAnalysis.__version__)"
$PYTHON_BIN -c "import open3d; print('✓ Open3D:', open3d.__version__)"

echo ""
echo "✓ MDAnalysis and Open3D installed!"
echo "Note: PyMOL not available for Python 3.10"
echo "Will use VMD for surface generation instead"
