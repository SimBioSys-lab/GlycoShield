#!/bin/bash
#SBATCH --job-name=preprocess
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=4
#SBATCH --mem=8G
#SBATCH --time=4:00:00
#SBATCH --output=preprocess-%J.log

# Get the input file from command line argument
FILE=$1

if [ -z "$FILE" ]; then
    echo "Error: No input file provided"
    echo "Usage: sbatch run_preprocessing.sh <input_file.pdb>"
    exit 1
fi

echo "Preprocessing $FILE..."

# Load Python module
module load python

# Install dependencies if needed
pip install --user mdtraj numpy

# Run the preprocessing script
python pre_processing.py "$FILE"

echo "Preprocessing complete for $FILE"