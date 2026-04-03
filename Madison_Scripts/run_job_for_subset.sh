#!/bin/bash
#SBATCH --job-name=adj-matrix
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=10
#SBATCH --mem=16G
#SBATCH --time=24:00:00
#SBATCH --output=adj-matrix-%J-%x.log

# Get the input file from command line argument
FILE=$1

if [ -z "$FILE" ]; then
    echo "Error: No input file provided"
    exit 1
fi

echo "Processing $FILE..."

# Load the Python module
module load python

# Verify which Python is being used
which python
python --version

# Install MDAnalysis using pip (since conda is not available)
echo "Installing MDAnalysis via pip..."
pip install --user mdanalysis mdtraj numpy scipy pandas matplotlib seaborn

# Verify installation
python -c "import MDAnalysis; print('MDAnalysis version:', MDAnalysis.__version__)"

# Run the Python script
python create_adj_matrix.py "$FILE"

echo "Completed $FILE"