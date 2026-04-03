#!/bin/bash

# Find all subset files matching the naming convention
FILES=($(ls subset_*_of_*.pdb 2>/dev/null))

# Check if any files were found
if [ ${#FILES[@]} -eq 0 ]; then
    echo "No subset files found matching pattern: subset_*_of_*.pdb"
    exit 1
fi

echo "Found ${#FILES[@]} subset files to process"
echo "-----------------------------------"

# Submit each file as a separate job
for FILE in "${FILES[@]}"; do
    echo "Submitting job for $FILE..."
    sbatch run_job_for_subset.sh "$FILE"
done

echo "-----------------------------------"
echo "All jobs submitted!"