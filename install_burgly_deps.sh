#!/bin/bash
# Install Burgly dependencies in allosmod-env

set -e

echo "============================================"
echo "Installing Burgly Dependencies"
echo "Target: allosmod-env"
echo "============================================"
echo ""

PYTHON_BIN="/projects/SimBioSys/share/software/allosmod-env/bin/python"
PIP_BIN="/projects/SimBioSys/share/software/allosmod-env/bin/pip"

echo "Python version:"
$PYTHON_BIN --version

echo ""
echo "Pip version:"
$PIP_BIN --version

echo ""
echo "============================================"
echo "Installing PyMOL (this may take a few minutes)"
echo "============================================"
$PIP_BIN install pymol-open-source

echo ""
echo "============================================"
echo "Installing MDAnalysis"
echo "============================================"
$PIP_BIN install MDAnalysis

echo ""
echo "============================================"
echo "Installing Open3D"
echo "============================================"
$PIP_BIN install open3d

echo ""
echo "============================================"
echo "Verifying installations"
echo "============================================"

$PYTHON_BIN -c "import pymol; print('✓ PyMOL version:', pymol.__version__)"
$PYTHON_BIN -c "import MDAnalysis; print('✓ MDAnalysis version:', MDAnalysis.__version__)"
$PYTHON_BIN -c "import open3d; print('✓ Open3D version:', open3d.__version__)"

echo ""
echo "✅ Installation Complete!"
echo ""
