#!/usr/bin/env bash
set -euo pipefail

# Usage
if [[ $# -ne 4 ]]; then
  echo "Usage: $0 <FOLDER_PATH> <USER_ID> <EMAIL> <n>"
  exit 1
fi
FOLDER_PATH="$1"
USER_ID="$2"
EMAIL="$3"
NAME="$4"

# Resolve script dir
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"

# --- Load .env (only LOG_DIR / LOG_ROOT are honored here; others passed through to jobs) ---
try_source_env() {
  local envfile="$1"
  [[ -f "$envfile" ]] || return 1
  set -a
  # shellcheck disable=SC1090
  . "$envfile"
  set +a
  echo "Loaded .env from: $envfile"
  return 0
}
ENV_CANDIDATES=(
  ".env"
  "$SCRIPT_DIR/.env"
  "$FOLDER_PATH/.env"
  "$(dirname "$FOLDER_PATH")/.env"
)
for cand in "${ENV_CANDIDATES[@]}"; do
  try_source_env "$cand" && break
done

# --- Tools (overridable by env) ---
RUN_ALLOSMOD="${RUN_ALLOSMOD:-${SCRIPT_DIR}/run_allosmod_lib.sh}"
GET_PDB="${GET_PDB:-${SCRIPT_DIR}/Ensemble-Modelling/get_pdb.sh}"
GEF_ANALYSIS="${GEF_ANALYSIS:-${SCRIPT_DIR}/GEF/run_gef_analysis.sh}"

# Compute absolute dir for helper scripts and export it
GET_PDB_DIR="$(cd -- "$(dirname -- "$GET_PDB")" >/dev/null 2>&1 && pwd)"
export ENSEMBLE_SCRIPTS_DIR="$GET_PDB_DIR"

echo "Using RUN_ALLOSMOD: $RUN_ALLOSMOD"
echo "Using GET_PDB:      $GET_PDB"
echo "Using GEF_ANALYSIS: $GEF_ANALYSIS"
echo "Using ENSEMBLE_SCRIPTS_DIR: $ENSEMBLE_SCRIPTS_DIR"

[[ -f "$GET_PDB" ]] || { echo "Error: get_pdb.sh not found at '$GET_PDB'"; exit 1; }
[[ -f "$GEF_ANALYSIS" ]] || echo "Warning: GEF analysis script not found at '$GEF_ANALYSIS' - GEF will be skipped"

# --- Logs ---
BASE_LOG_ROOT="${LOG_DIR:-${LOG_ROOT:-"$PWD/logs"}}"
USER_LOG_ROOT="${BASE_LOG_ROOT%/}/${USER_ID}"
PIPELINE_LOG_DIR="${USER_LOG_ROOT}/pipeline"
ALLOSMOD_LOG_DIR="${USER_LOG_ROOT}/allosmod_run"
ENSEMBLE_LOG_DIR="${USER_LOG_ROOT}/ensemble_modelling"
GEF_LOG_DIR="${USER_LOG_ROOT}/gef_analysis"
mkdir -p "$PIPELINE_LOG_DIR" "$ALLOSMOD_LOG_DIR" "$ENSEMBLE_LOG_DIR" "$GEF_LOG_DIR"

# --- Sanity checks ---
[[ -f "$RUN_ALLOSMOD" ]] || { echo "Error: $RUN_ALLOSMOD not found"; exit 1; }
[[ -f "$GET_PDB"      ]] || { echo "Error: $GET_PDB not found"; exit 1; }
[[ -d "$FOLDER_PATH"  ]] || { echo "Error: folder '$FOLDER_PATH' not found"; exit 1; }

# --- GEF Configuration (overridable by env) ---
GEF_SYSTEM_TYPE="${GEF_SYSTEM_TYPE:-auto}"  # Default to auto-detection
RUN_GEF="${RUN_GEF:-1}"  # Set to 0 to disable GEF analysis

echo "GEF Analysis enabled: $RUN_GEF"
echo "GEF System type: $GEF_SYSTEM_TYPE"

# --- Helper function to submit GEF jobs ---
submit_gef_jobs() {
  local get_pdb_job_id="$1"
  
  if [[ "$RUN_GEF" != "1" ]] || [[ ! -f "$GEF_ANALYSIS" ]]; then
    [[ "$RUN_GEF" != "1" ]] && echo "GEF analysis disabled (RUN_GEF=0)"
    [[ ! -f "$GEF_ANALYSIS" ]] && echo "GEF analysis script not found - skipping"
    return 0
  fi
  
  echo ""
  echo "=== Submitting GEF Analysis Jobs ==="
  
  # Determine output_aligned.pdb location based on OUTPUT_DIR or default
  OUTPUT_BASE="${OUTPUT_DIR:-${ENSEMBLE_LOG_DIR}}"
  
  # Find all model subdirectories and submit GEF jobs for each
  local gef_job_count=0
  for model_dir in "$FOLDER_PATH"/*; do
    [[ -d "$model_dir" ]] || continue
    model_name="$(basename "$model_dir")"
    
    aligned_pdb="${OUTPUT_BASE%/}/${USER_ID}/${model_name}/output_aligned.pdb"
    
    # Submit GEF job with dependency on get_pdb completion
    gef_job=$(sbatch --parsable \
      --dependency="afterok:$get_pdb_job_id" \
      --output="${GEF_LOG_DIR}/gef_${model_name}-%j.out" \
      --error="${GEF_LOG_DIR}/gef_${model_name}-%j.err" \
      "$GEF_ANALYSIS" "$aligned_pdb" "$GEF_SYSTEM_TYPE")
    
    echo "Submitted GEF analysis for $model_name: Job ID $gef_job (depends on $get_pdb_job_id)"
    ((gef_job_count++))
  done
  
  echo "Total GEF jobs submitted: $gef_job_count"
}

# --- ONLY_GET_PDB shortcut (skip Allosmod, submit get_pdb.sh only) ---
if [[ "${ONLY_GET_PDB:-0}" == "1" ]]; then
  echo "ONLY_GET_PDB=1: skipping Allosmod submission; running get_pdb.sh only."
  
  # Submit get_pdb.sh
  get_pdb_job=$(sbatch --parsable --export=ALL --chdir="$FOLDER_PATH" \
    --output="${ENSEMBLE_LOG_DIR}/get_pdb-%j.out" \
    --error="${ENSEMBLE_LOG_DIR}/get_pdb-%j.err" \
    "$GET_PDB" "$FOLDER_PATH" "$USER_ID")
  
  echo "Submitted get_pdb.sh: Job ID $get_pdb_job"
  
  # Always submit GEF analysis after get_pdb
  submit_gef_jobs "$get_pdb_job"
  
  echo ""
  echo "Pipeline logs: ${PIPELINE_LOG_DIR}"
  echo "Allosmod logs: ${ALLOSMOD_LOG_DIR}"
  echo "Ensemble logs: ${ENSEMBLE_LOG_DIR}"
  echo "GEF logs: ${GEF_LOG_DIR}"
  exit 0
fi

# 1) Submit Allosmod and capture output to parse final job ID(s)
TMP_OUT="$(mktemp)"
set +e
# We tee to both stdout and pipeline-log
"$RUN_ALLOSMOD" "$FOLDER_PATH" "$USER_ID" "$EMAIL" "$NAME" \
  | tee -a "${PIPELINE_LOG_DIR}/allosmod_submit.log" \
  | tee "$TMP_OUT"
RC=${PIPESTATUS[0]}
set -e
[[ $RC -eq 0 ]] || { echo "Error: $RUN_ALLOSMOD exited with $RC"; rm -f "$TMP_OUT"; exit $RC; }

# 2) Extract *all* job array IDs to depend on
mapfile -t JOB_IDS < <(grep -Eo 'Job array ID:\s*[0-9]+' "$TMP_OUT" | awk '{print $NF}')

rm -f "$TMP_OUT"

# common flags for get_pdb submission
sbatch_common=(
  --parsable
  --export=ALL
  --chdir="$FOLDER_PATH"
  --output="${ENSEMBLE_LOG_DIR}/get_pdb-%j.out"
  --error="${ENSEMBLE_LOG_DIR}/get_pdb-%j.err"
)

# 3) Submit get_pdb.sh with dependency on all Allosmod arrays (if any)
get_pdb_job=""
if ((${#JOB_IDS[@]} > 0)); then
  dep="afterany:$(IFS=:; echo "${JOB_IDS[*]}")"
  echo "Detected Allosmod job arrays: ${JOB_IDS[*]}"
  get_pdb_job=$(sbatch "${sbatch_common[@]}" --dependency="$dep" -- \
    "$GET_PDB" "$FOLDER_PATH" "$USER_ID")
else
  echo "Warning: could not detect any Allosmod job IDs. Submitting get_pdb.sh without dependency."
  get_pdb_job=$(sbatch "${sbatch_common[@]}" -- \
    "$GET_PDB" "$FOLDER_PATH" "$USER_ID")
fi

echo "Submitted get_pdb.sh: Job ID $get_pdb_job"

# 4) Always submit GEF analysis after get_pdb completion
submit_gef_jobs "$get_pdb_job"

echo ""
echo "=== Pipeline Submission Complete ==="
echo "Pipeline logs: ${PIPELINE_LOG_DIR}"
echo "Allosmod logs: ${ALLOSMOD_LOG_DIR}"
echo "Ensemble logs: ${ENSEMBLE_LOG_DIR}"
echo "GEF logs: ${GEF_LOG_DIR}"
echo ""
echo "Job chain: AllosMod → get_pdb (Job $get_pdb_job) → GEF analysis"
