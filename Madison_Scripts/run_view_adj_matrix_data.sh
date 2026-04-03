#!/bin/bash
#SBATCH --job-name=aggregate-matrices
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=4
#SBATCH --mem=16G
#SBATCH --time=2:00:00
#SBATCH --output=aggregate-%J.log

# Load the Python module
module load python

# Verify which Python is being used
which python
python --version

echo "Starting aggregation at $(date)"
echo "Current directory: $(pwd)"

# List available CSV files
echo "Available CSV files:"
ls -lh *_adjacency_matrix.csv

# Run the aggregation script
echo "Running aggregation and plotting..."
python aggregate_and_plot.py

# Check if outputs were created
echo ""
echo "Checking outputs..."
if [ -f "aggregated_adjacency_matrix_sum.csv" ]; then
    echo "SUCCESS: Aggregated matrix created"
    ls -lh aggregated_adjacency_matrix_sum.csv
else
    echo "ERROR: Aggregated matrix not found!"
fi

if [ -f "glycan_histogram.png" ]; then
    echo "SUCCESS: Histogram created"
    ls -lh glycan_histogram.png
else
    echo "ERROR: Histogram not found!"
fi

echo ""
echo "Aggregation completed at $(date)"