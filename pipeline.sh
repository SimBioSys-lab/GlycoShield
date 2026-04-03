#!/usr/bin/env bash
set -euo pipefail

# ============================================================================
# GlycoShield Pipeline - Main Orchestrator with Metadata-Driven Configuration
# ============================================================================

# Usage
if [[ $# -ne 1 ]]; then
  echo "Usage: $0 <FOLDER_PATH>"
  echo ""
  echo "The FOLDER_PATH must contain a metadata.txt file with:"
  echo "  USER_ID=<user_identifier>"
  echo "  EMAIL=<user_email>"
  echo "  JOB_NAME=<job_name>"
  echo ""
  echo "Example metadata.txt:"
  echo "  USER_ID=rajagopalmohanraj.n"
  echo "  EMAIL=user@example.com"
  echo "  JOB_NAME=spike_protein_analysis"
  exit 1
fi

FOLDER_PATH="$1"

# Resolve script dir
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"

# ============================================================================
# METADATA LOADING
# ============================================================================

METADATA_FILE="${FOLDER_PATH}/metadata.txt"

if [[ ! -f "$METADATA_FILE" ]]; then
  echo "Error: metadata.txt not found in $FOLDER_PATH"
  echo ""
  echo "Please create a metadata.txt file with the following format:"
  echo "  USER_ID=<user_identifier>"
  echo "  EMAIL=<user_email>"
  echo "  JOB_NAME=<job_name>"
  exit 1
fi

# Function to read metadata
read_metadata() {
  local key="$1"
  local value=$(grep "^${key}=" "$METADATA_FILE" | cut -d'=' -f2- | tr -d '\r\n' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
  echo "$value"
}

# Load metadata
USER_ID=$(read_metadata "USER_ID")
EMAIL=$(read_metadata "EMAIL")
NAME=$(read_metadata "JOB_NAME")

# Validate metadata
if [[ -z "$USER_ID" ]]; then
  echo "Error: USER_ID not found in metadata.txt"
  exit 1
fi

if [[ -z "$NAME" ]]; then
  echo "Error: JOB_NAME not found in metadata.txt"
  exit 1
fi

# ============================================================================
# LOGGING SETUP
# ============================================================================

# Create timestamp for this run
RUN_TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
RUN_ID="${USER_ID}_${RUN_TIMESTAMP}"

# Setup base log directories
BASE_LOG_ROOT="${LOG_DIR:-${LOG_ROOT:-"$SCRIPT_DIR/logs"}}"
USER_LOG_ROOT="${BASE_LOG_ROOT%/}/${USER_ID}"
PIPELINE_LOG_DIR="${USER_LOG_ROOT}/pipeline"

# Create log directories
mkdir -p "$PIPELINE_LOG_DIR"

# Main pipeline log file with timestamp
MAIN_LOG="${PIPELINE_LOG_DIR}/pipeline_${RUN_TIMESTAMP}.log"
STATUS_LOG="${PIPELINE_LOG_DIR}/pipeline_${RUN_TIMESTAMP}_status.log"
ERROR_LOG="${PIPELINE_LOG_DIR}/pipeline_${RUN_TIMESTAMP}_errors.log"

# Function to log with timestamp
log_msg() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date +"%Y-%m-%d %H:%M:%S")
    echo "[$timestamp] [$level] $message" | tee -a "$MAIN_LOG"
    
    # Also write to status log for INFO/SUCCESS/WARNING
    if [[ "$level" == "INFO" ]] || [[ "$level" == "SUCCESS" ]] || [[ "$level" == "WARNING" ]]; then
        echo "[$timestamp] [$level] $message" >> "$STATUS_LOG"
    fi
    
    # Write errors to error log
    if [[ "$level" == "ERROR" ]] || [[ "$level" == "FATAL" ]]; then
        echo "[$timestamp] [$level] $message" >> "$ERROR_LOG"
    fi
}

# Function to log command execution
log_exec() {
    local cmd="$*"
    log_msg "EXEC" "Running: $cmd"
    if eval "$cmd" 2>&1 | tee -a "$MAIN_LOG"; then
        log_msg "SUCCESS" "Command completed: $cmd"
        return 0
    else
        local rc=$?
        log_msg "ERROR" "Command failed with exit code $rc: $cmd"
        return $rc
    fi
}

# Function to check and log file existence
check_file() {
    local file="$1"
    local description="${2:-File}"
    if [[ -f "$file" ]]; then
        log_msg "CHECK" "✓ $description exists: $file"
        return 0
    else
        log_msg "ERROR" "✗ $description not found: $file"
        return 1
    fi
}

# Function to check and log directory existence
check_dir() {
    local dir="$1"
    local description="${2:-Directory}"
    if [[ -d "$dir" ]]; then
        log_msg "CHECK" "✓ $description exists: $dir"
        return 0
    else
        log_msg "ERROR" "✗ $description not found: $dir"
        return 1
    fi
}

# Trap errors and log them
trap 'log_msg "FATAL" "Pipeline failed at line $LINENO with exit code $?"' ERR

# ============================================================================
# START PIPELINE EXECUTION
# ============================================================================

log_msg "INFO" "============================================================"
log_msg "INFO" "GlycoShield Pipeline Started (Metadata-Driven Mode)"
log_msg "INFO" "============================================================"
log_msg "INFO" "Run ID: $RUN_ID"
log_msg "INFO" "Timestamp: $RUN_TIMESTAMP"
log_msg "INFO" "Metadata File: $METADATA_FILE"
log_msg "INFO" "User ID: $USER_ID"
log_msg "INFO" "Email: $EMAIL"
log_msg "INFO" "Job Name: $NAME"
log_msg "INFO" "Input Folder: $FOLDER_PATH"
log_msg "INFO" "Script Directory: $SCRIPT_DIR"
log_msg "INFO" "Main Log: $MAIN_LOG"
log_msg "INFO" "Status Log: $STATUS_LOG"
log_msg "INFO" "Error Log: $ERROR_LOG"
log_msg "INFO" "============================================================"

# ============================================================================
# ENVIRONMENT CONFIGURATION
# ============================================================================

log_msg "INFO" "Loading environment configuration..."

# Function to try loading .env file
try_source_env() {
  local envfile="$1"
  if [[ -f "$envfile" ]]; then
    set -a
    # shellcheck disable=SC1090
    . "$envfile"
    set +a
    log_msg "SUCCESS" "Loaded .env from: $envfile"
    return 0
  else
    log_msg "DEBUG" "No .env file at: $envfile"
    return 1
  fi
}

# Try loading .env files from multiple locations
ENV_CANDIDATES=(
  ".env"
  "$SCRIPT_DIR/.env"
  "$FOLDER_PATH/.env"
  "$(dirname "$FOLDER_PATH")/.env"
)

env_loaded=false
for cand in "${ENV_CANDIDATES[@]}"; do
  if try_source_env "$cand"; then
    env_loaded=true
    break
  fi
done

if [[ "$env_loaded" == "false" ]]; then
  log_msg "WARNING" "No .env file found in any expected location"
fi

# ============================================================================
# TOOL PATH CONFIGURATION
# ============================================================================

log_msg "INFO" "Configuring tool paths..."

# Set tool paths (overridable by env)
RUN_ALLOSMOD="${RUN_ALLOSMOD:-${SCRIPT_DIR}/run_allosmod_lib.sh}"
GET_PDB="${GET_PDB:-${SCRIPT_DIR}/Ensemble-Modelling/get_pdb.sh}"
GEF_ANALYSIS="${GEF_ANALYSIS:-${SCRIPT_DIR}/GEF/run_gef_analysis.slurm}"
SEND_COMPLETION="${SEND_COMPLETION:-${SCRIPT_DIR}/send_completion_email.sh}"
BURGLY_ANALYSIS="${BURGLY_ANALYSIS:-${SCRIPT_DIR}/Burgly/run_burgly_analysis.slurm}"
MADISON_ANALYSIS="${MADISON_ANALYSIS:-${SCRIPT_DIR}/Madison_Scripts/run_madison_analysis.slurm}"

# Compute and export ENSEMBLE_SCRIPTS_DIR
GET_PDB_DIR="$(cd -- "$(dirname -- "$GET_PDB")" >/dev/null 2>&1 && pwd)"
export ENSEMBLE_SCRIPTS_DIR="$GET_PDB_DIR"

log_msg "CONFIG" "RUN_ALLOSMOD: $RUN_ALLOSMOD"
log_msg "CONFIG" "GET_PDB: $GET_PDB"
log_msg "CONFIG" "GEF_ANALYSIS: $GEF_ANALYSIS"
log_msg "CONFIG" "SEND_COMPLETION: $SEND_COMPLETION"
log_msg "CONFIG" "BURGLY_ANALYSIS: $BURGLY_ANALYSIS"
log_msg "CONFIG" "MADISON_ANALYSIS: $MADISON_ANALYSIS"
log_msg "CONFIG" "ENSEMBLE_SCRIPTS_DIR: $ENSEMBLE_SCRIPTS_DIR"

# ============================================================================
# DIRECTORY SETUP
# ============================================================================

log_msg "INFO" "Setting up directory structure..."

# Create all necessary log directories
ALLOSMOD_LOG_DIR="${USER_LOG_ROOT}/allosmod_run"
ENSEMBLE_LOG_DIR="${USER_LOG_ROOT}/ensemble_modelling"
GEF_LOG_DIR="${USER_LOG_ROOT}/gef_analysis"
BURGLY_LOG_DIR="${USER_LOG_ROOT}/burgly_analysis"
MADISON_LOG_DIR="${USER_LOG_ROOT}/madison_analysis"

for dir in "$PIPELINE_LOG_DIR" "$ALLOSMOD_LOG_DIR" "$ENSEMBLE_LOG_DIR" "$GEF_LOG_DIR" "$BURGLY_LOG_DIR" "$MADISON_LOG_DIR"; do
  mkdir -p "$dir"
  log_msg "SUCCESS" "Created/verified directory: $dir"
done

# ============================================================================
# SANITY CHECKS
# ============================================================================

log_msg "INFO" "Performing sanity checks..."

# Check required files
check_file "$RUN_ALLOSMOD" "AllosMod script" || exit 1
check_file "$GET_PDB" "get_pdb.sh script" || exit 1
check_dir "$FOLDER_PATH" "Input folder" || exit 1
check_file "$METADATA_FILE" "Metadata file" || exit 1

# Check optional files
if ! check_file "$GEF_ANALYSIS" "GEF analysis script"; then
  log_msg "WARNING" "GEF analysis will be skipped"
fi

if ! check_file "$SEND_COMPLETION" "Completion email script"; then
  log_msg "WARNING" "Completion email will be skipped"
fi

# ============================================================================
# EMAIL NOTIFICATION (SUBMISSION)
# ============================================================================

# Only send email if EMAIL field is available and not empty
if [[ -n "$EMAIL" ]]; then
  log_msg "INFO" "Sending job submission acknowledgment email to $EMAIL..."
  
  TRIGGER_EMAIL="${SCRIPT_DIR}/trigger_email.py"
  if check_file "$TRIGGER_EMAIL" "Email trigger script"; then
    if python3 "$TRIGGER_EMAIL" submission "$EMAIL" "$USER_ID" "$NAME" "$NAME" 2>&1 | tee -a "$MAIN_LOG"; then
      log_msg "SUCCESS" "Submission acknowledgment email sent to $EMAIL"
    else
      log_msg "WARNING" "Failed to send acknowledgment email, continuing with pipeline"
    fi
  else
    log_msg "WARNING" "Email trigger script not found, skipping notification"
  fi
else
  log_msg "INFO" "No email address provided, skipping submission notification"
fi

# ============================================================================
# AZURE FOLDER CREATION (STEP 0)
# ============================================================================

log_msg "INFO" "============================================================"
# ============================================================================
# AZURE FOLDER CREATION (STEP 0)
# ============================================================================

log_msg "INFO" "============================================================"
# ============================================================================
# AZURE FOLDER CREATION (STEP 0)
# ============================================================================

log_msg "INFO" "============================================================"
log_msg "INFO" "Step 0: Creating Azure Storage Folder"
log_msg "INFO" "============================================================"

AZURE_SCRIPT="${SCRIPT_DIR}/azure_glycoshield.py"

if [[ ! -f "$AZURE_SCRIPT" ]]; then
  log_msg "ERROR" "Azure script not found: $AZURE_SCRIPT"
  log_msg "INFO" "Continuing without Azure folder creation"
else
  log_msg "INFO" "Creating Azure folder for user: $USER_ID"
  
  # Activate conda environment for Azure SDK (suppress PS1 warnings)
  set +u
  source /shared/centos7/anaconda3/3.7/bin/activate /projects/SimBioSys/share/software/allosmod-env 2>/dev/null || true
  set -u
  
  # Create folder and capture SAS URL
  AZURE_OUTPUT=$(python3 "$AZURE_SCRIPT" create-folder "$USER_ID" 2>&1)
  AZURE_EXIT_CODE=$?
  
  # Log the output
  echo "$AZURE_OUTPUT" | tee -a "$MAIN_LOG"
  
  # Extract URL from last line
  AZURE_FOLDER_URL=$(echo "$AZURE_OUTPUT" | grep -E '^https://' | tail -1)
  
  if [[ $AZURE_EXIT_CODE -eq 0 ]] && [[ "$AZURE_FOLDER_URL" =~ ^https:// ]]; then
    log_msg "SUCCESS" "Azure folder created successfully"
    log_msg "INFO" "📂 Azure Folder URL: $AZURE_FOLDER_URL"
    
    # Save URL to file for later use
    AZURE_URL_FILE="${PIPELINE_LOG_DIR}/azure_url_${RUN_TIMESTAMP}.txt"
    echo "$AZURE_FOLDER_URL" > "$AZURE_URL_FILE"
    log_msg "INFO" "Azure URL saved to: $AZURE_URL_FILE"
    
    # Export for use in other scripts
    export AZURE_FOLDER_URL
    
    # Also save to a file that completion script can access
    AZURE_URL_GLOBAL="${BASE_LOG_ROOT}/${USER_ID}/azure_folder_url.txt"
    mkdir -p "$(dirname "$AZURE_URL_GLOBAL")"
    echo "$AZURE_FOLDER_URL" > "$AZURE_URL_GLOBAL"
    log_msg "INFO" "Azure URL also saved to: $AZURE_URL_GLOBAL"
    
  else
    log_msg "WARNING" "Failed to create Azure folder"
    log_msg "INFO" "Pipeline will continue without Azure integration"
  fi
fi

log_msg "INFO" "============================================================"


# ============================================================================
# FOLDER DISCOVERY AND JOB SUBMISSION
# ============================================================================

log_msg "INFO" "============================================================"
log_msg "INFO" "Step 1: Discovering and Processing Input Folders"
log_msg "INFO" "============================================================"

# Find all subdirectories in FOLDER_PATH (these are the model folders)
SUBFOLDERS=()
while IFS= read -r -d '' folder; do
    folder_name=$(basename "$folder")
    # Skip hidden folders and ensure it's a directory
    if [[ ! "$folder_name" =~ ^\. ]] && [[ -d "$folder" ]]; then
        SUBFOLDERS+=("$folder")
        log_msg "INFO" "Found input folder: $folder_name"
    fi
done < <(find "$FOLDER_PATH" -mindepth 1 -maxdepth 1 -type d -print0)

if [[ ${#SUBFOLDERS[@]} -eq 0 ]]; then
    log_msg "ERROR" "No subdirectories found in $FOLDER_PATH"
    log_msg "ERROR" "Expected structure: $FOLDER_PATH/<model_name>/ containing PDB, ALI, glyc.dat, input.dat"
    exit 1
fi

log_msg "INFO" "Found ${#SUBFOLDERS[@]} folder(s) to process"

# ============================================================================
# ALLOSMOD JOB SUBMISSION
# ============================================================================

log_msg "INFO" "============================================================"
log_msg "INFO" "Step 2: Submitting AllosMod Jobs"
log_msg "INFO" "============================================================"

# Call run_allosmod_lib.sh ONCE with the parent folder
# It will discover and process all subfolders
TMP_OUT="$(mktemp)"
set +e
"$RUN_ALLOSMOD" "$FOLDER_PATH" \
  | tee -a "${ALLOSMOD_LOG_DIR}/allosmod_submit.log" \
  | tee "$TMP_OUT"
RC=${PIPESTATUS[0]}
set -e

ALL_ALLOSMOD_JOBS=()

if [[ $RC -eq 0 ]]; then
    # Extract job array IDs
    mapfile -t JOB_IDS < <(grep -Eo 'Job array ID:\s*[0-9]+' "$TMP_OUT" | awk '{print $NF}')
    
    if [[ ${#JOB_IDS[@]} -gt 0 ]]; then
        log_msg "SUCCESS" "AllosMod jobs submitted: ${JOB_IDS[*]}"
        ALL_ALLOSMOD_JOBS+=("${JOB_IDS[@]}")
    else
        log_msg "WARNING" "No AllosMod job IDs detected"
    fi
else
    log_msg "ERROR" "AllosMod submission failed (exit code: $RC)"
fi

rm -f "$TMP_OUT"
log_msg "INFO" "Total AllosMod jobs submitted: ${#ALL_ALLOSMOD_JOBS[@]}"








































# ============================================================================
# ENSEMBLE MODELING (GET_PDB) SUBMISSION
# ============================================================================

log_msg "INFO" "============================================================"
log_msg "INFO" "Step 3: Submitting Ensemble Modeling Jobs"
log_msg "INFO" "============================================================"

ALL_GET_PDB_JOBS=()

for folder in "${SUBFOLDERS[@]}"; do
    folder_name=$(basename "$folder")
    log_msg "INFO" "Submitting get_pdb for: $folder_name"
    
    # Common sbatch flags
    sbatch_common=(
      --parsable
      --export=ALL
      --chdir="$folder"
      --output="${ENSEMBLE_LOG_DIR}/get_pdb_${folder_name}-%j.out"
      --error="${ENSEMBLE_LOG_DIR}/get_pdb_${folder_name}-%j.err"
    )
    
    # Submit with dependency on AllosMod jobs if they exist
    get_pdb_job=""
    if [[ ${#ALL_ALLOSMOD_JOBS[@]} -gt 0 ]]; then
        dep="afterany:$(IFS=:; echo "${ALL_ALLOSMOD_JOBS[*]}")"
        get_pdb_job=$(sbatch "${sbatch_common[@]}" --dependency="$dep" -- \
          "$GET_PDB" "$folder")
    else
        log_msg "WARNING" "No AllosMod jobs to depend on, submitting get_pdb independently"
        get_pdb_job=$(sbatch "${sbatch_common[@]}" -- \
          "$GET_PDB" "$folder")
    fi
    
    if [[ -n "$get_pdb_job" ]]; then
        log_msg "SUCCESS" "Submitted get_pdb for $folder_name: Job ID $get_pdb_job"
        ALL_GET_PDB_JOBS+=("$get_pdb_job")
    else
        log_msg "ERROR" "Failed to submit get_pdb for $folder_name"
    fi
done

# ============================================================================
# GEF ANALYSIS SUBMISSION
# ============================================================================

log_msg "INFO" "============================================================"
declare -a ALL_GEF_JOBS=()
log_msg "INFO" "Step 4: Submitting GEF Analysis Jobs"
log_msg "INFO" "============================================================"

if [[ -f "$GEF_ANALYSIS" ]] && [[ ${#ALL_GET_PDB_JOBS[@]} -gt 0 ]]; then
    for i in "${!SUBFOLDERS[@]}"; do
        folder="${SUBFOLDERS[$i]}"
        folder_name=$(basename "$folder")
        get_pdb_job="${ALL_GET_PDB_JOBS[$i]}"
        
        log_msg "INFO" "Submitting GEF analysis for: $folder_name"
        
        # Read per-folder GEF_PROBE_RADIUS from folder's metadata.txt or input.dat
        FOLDER_METADATA="${folder}/metadata.txt"
        FOLDER_INPUT_DAT="${folder}/input.dat"
        FOLDER_PROBE_RADIUS="3"  # Default
        
        if [[ -f "$FOLDER_METADATA" ]]; then
            FOLDER_PROBE_RADIUS=$(grep "^GEF_PROBE_RADIUS=" "$FOLDER_METADATA" | cut -d'=' -f2 | tr -d '[:space:]')
        fi
        if [[ -z "$FOLDER_PROBE_RADIUS" ]] && [[ -f "$FOLDER_INPUT_DAT" ]]; then
            FOLDER_PROBE_RADIUS=$(grep "^GEF_PROBE_RADIUS=" "$FOLDER_INPUT_DAT" | cut -d'=' -f2 | tr -d '[:space:]')
        fi
        FOLDER_PROBE_RADIUS="${FOLDER_PROBE_RADIUS:-3}"
        
        log_msg "INFO" "Using GEF_PROBE_RADIUS=$FOLDER_PROBE_RADIUS for $folder_name"
        
        # Determine output_aligned.pdb location
        OUTPUT_BASE="${OUTPUT_DIR:-${ENSEMBLE_LOG_DIR}}"
        aligned_pdb="${OUTPUT_BASE%/}/${USER_ID}/${folder_name}/ensemble/output_aligned.pdb"
        
        # Submit GEF job with dependency on get_pdb completion
        GEF_SYSTEM_TYPE="${GEF_SYSTEM_TYPE:-auto}"
        gef_job=$(sbatch --parsable \
          --dependency="afterok:$get_pdb_job" \
          --output="${GEF_LOG_DIR}/gef_${folder_name}-%j.out" \
          --error="${GEF_LOG_DIR}/gef_${folder_name}-%j.err" \
          "$GEF_ANALYSIS" "$aligned_pdb" "$GEF_SYSTEM_TYPE" "$FOLDER_PROBE_RADIUS")
        
        if [[ -n "$gef_job" ]]; then
            log_msg "SUCCESS" "Submitted GEF analysis for $folder_name: Job ID $gef_job"
            ALL_GEF_JOBS+=("$gef_job")
        else
            log_msg "ERROR" "Failed to submit GEF analysis for $folder_name"
        fi
    done
else
    if [[ ! -f "$GEF_ANALYSIS" ]]; then
        log_msg "WARNING" "GEF analysis script not found, skipping GEF submission"
    elif [[ ${#ALL_GET_PDB_JOBS[@]} -eq 0 ]]; then
        log_msg "WARNING" "No get_pdb jobs to chain GEF analysis to, skipping GEF submission"
    fi
fi

# ============================================================================
# COMPLETION EMAIL SUBMISSION

# ============================================================================
# BURGLY ANALYSIS SUBMISSION
# ============================================================================

log_msg "INFO" "============================================================"
log_msg "INFO" "Step 4.5: Submitting Burgly Analysis Jobs"
log_msg "INFO" "============================================================"

declare -a ALL_BURGLY_JOBS=()

if [[ -f "$BURGLY_ANALYSIS" ]] && [[ ${#ALL_GEF_JOBS[@]} -gt 0 ]]; then
    for i in "${!SUBFOLDERS[@]}"; do
        folder="${SUBFOLDERS[$i]}"
        folder_name=$(basename "$folder")
        gef_job="${ALL_GEF_JOBS[$i]}"
        
        log_msg "INFO" "Submitting Burgly analysis for: $folder_name"
        
        # Determine aligned_pdb and glyc.dat locations
        OUTPUT_BASE="${OUTPUT_DIR:-${ENSEMBLE_LOG_DIR}}"
        aligned_pdb="${OUTPUT_BASE%/}/${USER_ID}/${folder_name}/ensemble/output_aligned.pdb"
        glyc_dat="${folder}/glyc.dat"
        
        # Check if glyc.dat exists
        if [[ ! -f "$glyc_dat" ]]; then
            log_msg "WARNING" "glyc.dat not found for $folder_name at $glyc_dat, skipping Burgly analysis"
            continue
        fi
        
        # Submit Burgly job with dependency on GEF completion
        burgly_job=$(sbatch --parsable \
          --dependency="afterok:$gef_job" \
          --output="${BURGLY_LOG_DIR}/burgly_${folder_name}-%j.out" \
          --error="${BURGLY_LOG_DIR}/burgly_${folder_name}-%j.err" \
          "$BURGLY_ANALYSIS" "$aligned_pdb" "$glyc_dat")
        
        if [[ -n "$burgly_job" ]]; then
            ALL_BURGLY_JOBS+=("$burgly_job")
            log_msg "SUCCESS" "Submitted Burgly analysis for $folder_name: Job ID $burgly_job"
        else
            log_msg "ERROR" "Failed to submit Burgly analysis for $folder_name"
        fi
    done
else
    if [[ ! -f "$BURGLY_ANALYSIS" ]]; then
        log_msg "WARNING" "Burgly analysis script not found, skipping Burgly submission"
    elif [[ ${#ALL_GEF_JOBS[@]} -eq 0 ]]; then
        log_msg "WARNING" "No GEF jobs to chain Burgly analysis to, skipping Burgly submission"
    fi
fi
# ============================================================================
# MADISON ANALYSIS SUBMISSION (Runs in parallel with Burgly)
# ============================================================================

log_msg "INFO" "============================================================"
log_msg "INFO" "Step 4.6: Submitting Madison Analysis Jobs"
log_msg "INFO" "============================================================"

declare -a ALL_MADISON_JOBS=()

if [[ -f "$MADISON_ANALYSIS" ]] && [[ ${#ALL_GEF_JOBS[@]} -gt 0 ]]; then
    for i in "${!SUBFOLDERS[@]}"; do
        folder="${SUBFOLDERS[$i]}"
        folder_name=$(basename "$folder")
        gef_job="${ALL_GEF_JOBS[$i]}"
        
        log_msg "INFO" "Submitting Madison analysis for: $folder_name"
        
        # Determine aligned_pdb and glyc.dat locations (same as Burgly)
        OUTPUT_BASE="${OUTPUT_DIR:-${ENSEMBLE_LOG_DIR}}"
        aligned_pdb="${OUTPUT_BASE%/}/${USER_ID}/${folder_name}/ensemble/output_aligned.pdb"
        glyc_dat="${folder}/glyc.dat"
        
        # Check if glyc.dat exists
        if [[ ! -f "$glyc_dat" ]]; then
            log_msg "WARNING" "glyc.dat not found for $folder_name at $glyc_dat, skipping Madison analysis"
            continue
        fi
        
        # Submit Madison job with dependency on GEF completion (parallel with Burgly)
        madison_job=$(sbatch --parsable \
          --dependency="afterok:$gef_job" \
          --output="${MADISON_LOG_DIR}/madison_${folder_name}-%j.out" \
          --error="${MADISON_LOG_DIR}/madison_${folder_name}-%j.err" \
          "$MADISON_ANALYSIS" "$aligned_pdb" "$glyc_dat")
        
        if [[ -n "$madison_job" ]]; then
            ALL_MADISON_JOBS+=("$madison_job")
            log_msg "SUCCESS" "Submitted Madison analysis for $folder_name: Job ID $madison_job"
        else
            log_msg "ERROR" "Failed to submit Madison analysis for $folder_name"
        fi
    done
else
    if [[ ! -f "$MADISON_ANALYSIS" ]]; then
        log_msg "WARNING" "Madison analysis script not found, skipping Madison submission"
    elif [[ ${#ALL_GEF_JOBS[@]} -eq 0 ]]; then
        log_msg "WARNING" "No GEF jobs to chain Madison analysis to, skipping Madison submission"
    fi
fi
# ============================================================================

log_msg "INFO" "============================================================"
log_msg "INFO" "============================================================"
log_msg "INFO" "Step 5: Setting up Completion Email Monitoring"
log_msg "INFO" "============================================================"

# Set up completion email monitoring if:
# 1. Email script exists
# 2. User provided an email address
# 3. We have jobs to wait for
#
# IMPORTANT: We must wait for the FINAL stage jobs in the pipeline chain:
#   - If Burgly jobs exist -> wait for Burgly (they depend on GEF which depends on get_pdb)
#   - Else if GEF jobs exist -> wait for GEF (they depend on get_pdb)
#   - Else if get_pdb jobs exist -> wait for get_pdb
WAIT_AND_EMAIL="${SCRIPT_DIR}/wait_and_email.sh"

# Determine which jobs to monitor (the final stage in the pipeline)
FINAL_JOBS=()
FINAL_STAGE=""

# Collect all final stage jobs (both Burgly and Madison run in parallel after GEF)
if [[ ${#ALL_BURGLY_JOBS[@]} -gt 0 ]] || [[ ${#ALL_MADISON_JOBS[@]} -gt 0 ]]; then
    FINAL_JOBS=("${ALL_BURGLY_JOBS[@]}" "${ALL_MADISON_JOBS[@]}")
    FINAL_STAGE="Burgly+Madison"
elif [[ ${#ALL_GEF_JOBS[@]} -gt 0 ]]; then
    FINAL_JOBS=("${ALL_GEF_JOBS[@]}")
    FINAL_STAGE="GEF"
elif [[ ${#ALL_GET_PDB_JOBS[@]} -gt 0 ]]; then
    FINAL_JOBS=("${ALL_GET_PDB_JOBS[@]}")
    FINAL_STAGE="Ensemble"
fi

if [[ -f "$WAIT_AND_EMAIL" ]] && [[ ${#FINAL_JOBS[@]} -gt 0 ]]; then
    log_msg "INFO" "Setting up background job monitor for completion email..."
    
    # Create dependency list from final stage jobs
    dep_list=$(IFS=:; echo "${FINAL_JOBS[*]}")
    
    # IMPORTANT: Run the monitor directly on login node (NOT via SLURM)
    # Compute nodes cannot send emails due to network restrictions
    # Use setsid + nohup + disown to fully detach from the SSH session
    # This ensures the monitor survives even when the backend's SSH connection closes
    
    # Create a wrapper script that will run independently
    MONITOR_WRAPPER="${PIPELINE_LOG_DIR}/run_monitor_${RUN_TIMESTAMP}.sh"
    cat > "$MONITOR_WRAPPER" << 'MONITOR_SCRIPT_EOF'
#!/bin/bash
# Auto-generated completion monitor wrapper
# This script runs on the login node and monitors job completion

JOB_IDS="$1"
FOLDER_PATH="$2"
SCRIPT_DIR="$3"
LOG_FILE="$4"

exec > "$LOG_FILE" 2>&1

echo "============================================"
echo "Job Completion Monitor (Login Node)"
echo "============================================"
echo "Start time: $(date)"
echo "PID: $$"
echo "Monitoring jobs: $JOB_IDS"
echo "============================================"
echo ""

# Convert colon-separated list to array
IFS=':' read -ra JOB_ARRAY <<< "$JOB_IDS"

# Wait for all jobs to complete
echo "Waiting for jobs to complete..."
CHECK_COUNT=0
while true; do
    all_done=true
    running_jobs=0
    
    for job_id in "${JOB_ARRAY[@]}"; do
        if squeue -j "$job_id" -h &>/dev/null; then
            all_done=false
            ((running_jobs++))
        fi
    done
    
    if [[ "$all_done" == "true" ]]; then
        echo ""
        echo "All jobs completed at $(date)"
        break
    fi
    
    ((CHECK_COUNT++))
    if [[ $((CHECK_COUNT % 10)) -eq 0 ]]; then
        echo "[$(date)] Still waiting... $running_jobs jobs running"
    fi
    
    sleep 60
done

echo ""
echo "============================================"
echo "Checking job completion status"
echo "============================================"

for job_id in "${JOB_ARRAY[@]}"; do
    state=$(sacct -j "$job_id" --format=State --noheader | head -1 | tr -d ' ')
    echo "Job $job_id: $state"
done

echo ""
echo "============================================"
echo "Triggering completion email"
echo "============================================"

COMPLETION_SCRIPT="${SCRIPT_DIR}/send_completion_email_login.sh"

if [[ -f "$COMPLETION_SCRIPT" ]]; then
    bash "$COMPLETION_SCRIPT" "$FOLDER_PATH" "$SCRIPT_DIR"
    COMPLETION_EXIT=$?
    if [[ $COMPLETION_EXIT -eq 0 ]]; then
        echo "✓ Completion processing finished successfully"
    else
        echo "⚠ Completion processing finished with errors (exit code: $COMPLETION_EXIT)"
        echo "  Check the log above for details on which steps failed"
    fi
else
    echo "⚠ Completion script not found: $COMPLETION_SCRIPT"
fi

echo ""
echo "Monitor finished at $(date)"
MONITOR_SCRIPT_EOF
    
    chmod +x "$MONITOR_WRAPPER"
    
    # Launch the monitor completely detached from this session
    # setsid creates a new session (detaches from controlling terminal)
    # nohup ignores SIGHUP
    # < /dev/null closes stdin
    # disown removes from shell's job table
    setsid nohup bash "$MONITOR_WRAPPER" "$dep_list" "$FOLDER_PATH" "$SCRIPT_DIR" \
        "${PIPELINE_LOG_DIR}/completion_monitor.log" < /dev/null > /dev/null 2>&1 &
    
    monitor_pid=$!
    disown $monitor_pid 2>/dev/null || true
    
    log_msg "SUCCESS" "Completion monitor started (PID: $monitor_pid, fully detached)"
    log_msg "INFO" "Monitor script: $MONITOR_WRAPPER"
    log_msg "INFO" "Final stage: $FINAL_STAGE"
    log_msg "INFO" "Monitoring ${#FINAL_JOBS[@]} jobs: $dep_list"
    log_msg "INFO" "Results will be uploaded to Azure after all processing completes"
    if [[ -n "$EMAIL" ]]; then
        log_msg "INFO" "Email notification will be sent to $EMAIL"
    else
        log_msg "INFO" "No email provided - results will be available via Azure link"
    fi
    log_msg "INFO" "Monitor log: ${PIPELINE_LOG_DIR}/completion_monitor.log"
else
    if [[ ! -f "$WAIT_AND_EMAIL" ]]; then
        log_msg "WARNING" "Completion monitor script not found, skipping completion setup"
    elif [[ ${#FINAL_JOBS[@]} -eq 0 ]]; then
        log_msg "WARNING" "No jobs submitted, skipping completion processing"
    fi
fi

log_msg "INFO" "============================================================"
log_msg "INFO" "Pipeline Submission Complete"
log_msg "INFO" "============================================================"
log_msg "INFO" "AllosMod jobs: ${#ALL_ALLOSMOD_JOBS[@]}"
log_msg "INFO" "Ensemble jobs: ${#ALL_GET_PDB_JOBS[@]}"
log_msg "INFO" "GEF jobs: ${#ALL_GEF_JOBS[@]}"
log_msg "INFO" "Burgly jobs: ${#ALL_BURGLY_JOBS[@]}"
log_msg "INFO" "Madison jobs: ${#ALL_MADISON_JOBS[@]}"
log_msg "INFO" "Pipeline logs: ${PIPELINE_LOG_DIR}"
log_msg "INFO" "AllosMod logs: ${ALLOSMOD_LOG_DIR}"
log_msg "INFO" "Ensemble logs: ${ENSEMBLE_LOG_DIR}"
log_msg "INFO" "GEF logs: ${GEF_LOG_DIR}"
log_msg "INFO" "Burgly logs: ${BURGLY_LOG_DIR}"
log_msg "INFO" "Madison logs: ${MADISON_LOG_DIR}"
log_msg "INFO" "============================================================"
