#!/bin/bash
#SBATCH --job-name=plot-matrix
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=2
#SBATCH --mem=4G
#SBATCH --time=1:00:00
#SBATCH --output=plot-matrix-%J.log

echo "Running clean_finalized_script.py..."

# Load Python module
module load python

# Install dependencies if needed
pip install --user pandas matplotlib seaborn numpy

# Run the script
python clean_finalized_script.py

echo "Complete!"