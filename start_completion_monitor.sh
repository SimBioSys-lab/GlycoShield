#!/bin/bash
# start_completion_monitor.sh - Start completion monitor as a SLURM job
# This ensures the monitor runs completely independently of the parent SSH session

set -euo pipefail

if [[ $# -ne 4 ]]; then
    echo "Usage: $0 <JOB_IDS> <FOLDER_PATH> <SCRIPT_DIR> <LOG_FILE>"
    exit 1
fi

JOB_IDS="$1"
FOLDER_PATH="$2"
SCRIPT_DIR="$3"
LOG_FILE="$4"

MONITOR_SLURM="${SCRIPT_DIR}/completion_monitor.slurm"

if [[ ! -f "$MONITOR_SLURM" ]]; then
    echo "Error: completion_monitor.slurm not found at $MONITOR_SLURM"
    exit 1
fi

# Submit the monitor job to SLURM's sharing partition
# It will wait for the analysis jobs and then send the email
monitor_job=$(sbatch --parsable \
    --export=JOB_IDS="$JOB_IDS",FOLDER_PATH="$FOLDER_PATH",SCRIPT_DIR="$SCRIPT_DIR",LOG_FILE="$LOG_FILE" \
    "$MONITOR_SLURM")

if [[ -n "$monitor_job" ]]; then
    echo "Completion monitor submitted as SLURM job: $monitor_job"
    echo "Monitor will wait for jobs $JOB_IDS and send email upon completion"
else
    echo "Error: Failed to submit completion monitor job"
    exit 1
fi

exit 0
