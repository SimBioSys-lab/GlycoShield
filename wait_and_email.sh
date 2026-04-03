#!/bin/bash
# wait_and_email.sh - Monitor jobs and send email upon completion
# This runs on the login node and can send emails

set -euo pipefail

# Parse arguments
if [[ $# -ne 3 ]]; then
  echo "Usage: $0 <JOB_IDS> <FOLDER_PATH> <SCRIPT_DIR>"
  echo ""
  echo "JOB_IDS: Colon-separated list of SLURM job IDs to wait for"
  echo "FOLDER_PATH: Path to folder with metadata.txt"
  echo "SCRIPT_DIR: GlycoShield base directory"
  exit 1
fi

JOB_IDS="$1"
FOLDER_PATH="$2"
SCRIPT_DIR="$3"

# Convert colon-separated list to array
IFS=':' read -ra JOB_ARRAY <<< "$JOB_IDS"

echo "============================================"
echo "Job Completion Monitor"
echo "============================================"
echo "Start time: $(date)"
echo "Monitoring ${#JOB_ARRAY[@]} jobs: ${JOB_IDS}"
echo "Will send completion email when all jobs finish"
echo "============================================"
echo ""

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
echo "Check time: $(date)"

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

# Check if any jobs failed
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
echo "Triggering completion email & Azure upload"
echo "============================================"

# Call the completion email script (runs on login node, can send emails)
COMPLETION_SCRIPT="${SCRIPT_DIR}/send_completion_email_login.sh"

if [[ -f "$COMPLETION_SCRIPT" ]]; then
  echo "Calling completion script..."
  bash "$COMPLETION_SCRIPT" "$FOLDER_PATH" "$SCRIPT_DIR"
  
  if [[ $? -eq 0 ]]; then
    echo "✓ Completion processing successful"
  else
    echo "⚠ Completion processing had issues"
  fi
else
  echo "⚠ Completion script not found: $COMPLETION_SCRIPT"
  echo "Attempting direct email send..."
  
  # Fallback: try to call trigger_email.py directly
  TRIGGER_EMAIL="${SCRIPT_DIR}/trigger_email.py"
  METADATA_FILE="${FOLDER_PATH}/metadata.txt"
  
  if [[ -f "$TRIGGER_EMAIL" ]] && [[ -f "$METADATA_FILE" ]]; then
    read_metadata() {
      local key="$1"
      grep "^${key}=" "$METADATA_FILE" | cut -d'=' -f2- | tr -d '\r\n' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//'
    }
    
    EMAIL=$(read_metadata "EMAIL")
    JOB_NAME=$(read_metadata "JOB_NAME")
    
    if [[ -n "$EMAIL" ]]; then
      python3 "$TRIGGER_EMAIL" completion "$EMAIL" "$(read_metadata USER_ID)" "$JOB_NAME" "$EMAIL" 2>&1
    fi
  fi
fi

echo ""
echo "============================================"
echo "Completion monitoring finished"
echo "End time: $(date)"
echo "============================================"

exit 0
