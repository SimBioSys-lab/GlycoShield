#!/bin/bash
#SBATCH --job-name=glacier_email
#SBATCH --partition=sharing
#SBATCH --time=01:00:00
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=1
#SBATCH --mem=1G
#SBATCH --output=/dev/null
#SBATCH --error=/dev/null

# Completion Monitor SLURM Job
# This job waits for the analysis jobs to complete
# Then triggers email sending via SSH to login node (which has network access)

# Arguments passed via environment
# JOB_IDS: Colon-separated list of job IDs to wait for
# FOLDER_PATH: Path to input folder with metadata.txt
# SCRIPT_DIR: GlycoShield base directory
# LOG_FILE: Path to write log output

# Redirect output to log file
exec > "${LOG_FILE}" 2>&1

echo "============================================"
echo "SLURM Completion Monitor"
echo "============================================"
echo "Job ID: $SLURM_JOB_ID"
echo "Running on: $(hostname)"
echo "Start time: $(date)"
echo "Waiting for jobs: $JOB_IDS"
echo "Folder: $FOLDER_PATH"
echo "============================================"
echo ""

# Convert colon-separated list to array
IFS=':' read -ra JOB_ARRAY <<< "$JOB_IDS"

# Function to check if job is still running
job_running() {
    local job_id="$1"
    squeue -j "$job_id" -h &>/dev/null
}

# Function to get job state
job_state() {
    local job_id="$1"
    sacct -j "$job_id" --format=State --noheader | head -1 | tr -d ' '
}

# Wait for all jobs to complete
echo "Waiting for jobs to complete..."
CHECK_COUNT=0
while true; do
    all_done=true
    running_jobs=0
    
    for job_id in "${JOB_ARRAY[@]}"; do
        if job_running "$job_id"; then
            all_done=false
            ((running_jobs++))
        fi
    done
    
    if [[ "$all_done" == "true" ]]; then
        echo ""
        echo "All jobs completed at $(date)"
        break
    fi
    
    # Status update every 10 checks (10 minutes)
    ((CHECK_COUNT++))
    if [[ $((CHECK_COUNT % 10)) -eq 0 ]]; then
        echo "[$(date)] Still waiting... $running_jobs jobs running"
    fi
    
    sleep 60  # Check every minute
done

echo ""
echo "============================================"
echo "Checking job completion status"
echo "============================================"

any_failed=false
for job_id in "${JOB_ARRAY[@]}"; do
    state=$(job_state "$job_id")
    echo "Job $job_id: $state"
    
    if [[ "$state" != "COMPLETED" ]]; then
        any_failed=true
    fi
done

echo ""
echo "============================================"
echo "Triggering completion email via login node"
echo "============================================"

# Write a marker file that the completion email script can use
MARKER_DIR="${SCRIPT_DIR}/completion_markers"
mkdir -p "$MARKER_DIR"
MARKER_FILE="${MARKER_DIR}/$(basename ${FOLDER_PATH}).ready"

cat > "$MARKER_FILE" << MARKER_EOF
FOLDER_PATH=${FOLDER_PATH}
SCRIPT_DIR=${SCRIPT_DIR}
TIMESTAMP=$(date +%s)
ALL_COMPLETED=true
ANY_FAILED=${any_failed}
MARKER_EOF

echo "Created completion marker: $MARKER_FILE"

# Use SSH to trigger the email script on login node
# This works because compute nodes can SSH to login nodes
LOGIN_NODE="explorer.northeastern.edu"
COMPLETION_SCRIPT="${SCRIPT_DIR}/send_completion_email_login.sh"

echo "Triggering email via SSH to $LOGIN_NODE..."

ssh -o StrictHostKeyChecking=no -o BatchMode=yes "$LOGIN_NODE" \
    "cd ${SCRIPT_DIR} && bash ${COMPLETION_SCRIPT} '${FOLDER_PATH}' '${SCRIPT_DIR}'" 2>&1

if [[ $? -eq 0 ]]; then
    echo "✓ Email triggered successfully"
    # Clean up marker file
    rm -f "$MARKER_FILE"
else
    echo "⚠ SSH to login node failed - email not sent"
    echo "Marker file left at: $MARKER_FILE"
    echo "Run manually: bash ${COMPLETION_SCRIPT} '${FOLDER_PATH}' '${SCRIPT_DIR}'"
fi

echo ""
echo "============================================"
echo "Monitor job completed at $(date)"
echo "============================================"
