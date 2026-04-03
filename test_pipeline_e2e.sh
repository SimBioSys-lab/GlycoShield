#!/usr/bin/env bash
# ============================================================================
# GlycoShield End-to-End Pipeline Test
# ============================================================================
#
# Creates a minimal test input (NRUNS=1) using the existing bg505 reference
# data, runs the full pipeline, monitors each SLURM stage, and validates
# expected outputs at every step.
#
# Usage:
#   bash test_pipeline_e2e.sh [--dry-run]    # --dry-run: setup only, no sbatch
#
# What it does:
#   1. Copies reference input (bg505) into a fresh test user folder with NRUNS=1
#   2. Runs pipeline.sh against that folder
#   3. Polls SLURM until all jobs finish (or timeout)
#   4. Validates every expected output file exists
#   5. Prints a pass/fail report
#   6. Optionally cleans up on success
#
# Estimated runtime: ~2-6 hours (1 AllosMod run + ensemble + GEF + Burgly + Madison)
# ============================================================================

set -uo pipefail

# ── Config ──────────────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
TEST_USER_ID="e2e-test-$(date +%Y%m%d-%H%M%S)"
TEST_MODEL="bg505"
REFERENCE_INPUT="$SCRIPT_DIR/inputs/49c78fe6-5805-46ac-9857-e046cf64d0ff/bg505"
TEST_INPUT_DIR="$SCRIPT_DIR/inputs/$TEST_USER_ID"
TEST_MODEL_DIR="$TEST_INPUT_DIR/$TEST_MODEL"
TEST_OUTPUT_DIR="$SCRIPT_DIR/outputs/$TEST_USER_ID"
TEST_LOG_DIR="$SCRIPT_DIR/logs/$TEST_USER_ID"
POLL_INTERVAL=60        # seconds between squeue checks
MAX_WAIT=21600          # 6 hours max before we declare timeout
DRY_RUN=false

if [[ "${1:-}" == "--dry-run" ]]; then
  DRY_RUN=true
  echo "*** DRY RUN MODE — will set up inputs but not submit jobs ***"
  echo ""
fi

# ── Colors ──────────────────────────────────────────────────────────────────
green()  { echo -e "\033[32m$*\033[0m"; }
yellow() { echo -e "\033[33m$*\033[0m"; }
red()    { echo -e "\033[31m$*\033[0m"; }
bold()   { echo -e "\033[1m$*\033[0m"; }

PASS=0; FAIL=0; WARN=0
pass() { green "  ✓ $*"; ((PASS++)); }
fail() { red   "  ✗ $*"; ((FAIL++)); }
warn() { yellow "  ⚠ $*"; ((WARN++)); }

# ── Cleanup trap ────────────────────────────────────────────────────────────
cleanup_on_exit() {
  if [[ $FAIL -gt 0 ]]; then
    echo ""
    yellow "Test FAILED — leaving test data in place for debugging:"
    echo "  Input:  $TEST_INPUT_DIR"
    echo "  Output: $TEST_OUTPUT_DIR"
    echo "  Logs:   $TEST_LOG_DIR"
    echo ""
    echo "To clean up manually:"
    echo "  rm -rf $TEST_INPUT_DIR $TEST_OUTPUT_DIR $TEST_LOG_DIR"
  fi
}
trap cleanup_on_exit EXIT

# ============================================================================
# STEP 0: Pre-flight checks
# ============================================================================
bold "=== Step 0: Pre-flight Checks ==="

# Check reference input exists
if [[ -d "$REFERENCE_INPUT" ]]; then
  pass "Reference input exists: $REFERENCE_INPUT"
else
  fail "Reference input missing: $REFERENCE_INPUT"
  echo "Cannot proceed without reference data."
  exit 1
fi

# Check pipeline.sh exists
if [[ -x "$SCRIPT_DIR/pipeline.sh" ]]; then
  pass "pipeline.sh exists and is executable"
else
  fail "pipeline.sh missing or not executable"
  exit 1
fi

# Check SLURM available
if command -v sbatch &>/dev/null && command -v squeue &>/dev/null; then
  pass "SLURM commands available (sbatch, squeue)"
else
  fail "SLURM not available — cannot run pipeline"
  exit 1
fi

# Check we're not on a compute node (pipeline submits from login)
hostname_str=$(hostname)
if [[ "$hostname_str" =~ ^login|^explorer ]]; then
  pass "Running on login node: $hostname_str"
else
  warn "Running on $hostname_str — pipeline expects a login node"
fi

echo ""

# ============================================================================
# STEP 1: Create test input
# ============================================================================
bold "=== Step 1: Creating Test Input (NRUNS=1) ==="

mkdir -p "$TEST_MODEL_DIR"
pass "Created test directory: $TEST_MODEL_DIR"

# Copy reference files
cp "$REFERENCE_INPUT/bg505.pdb" "$TEST_MODEL_DIR/bg505.pdb"
cp "$REFERENCE_INPUT/align.ali" "$TEST_MODEL_DIR/align.ali"
cp "$REFERENCE_INPUT/glyc.dat"  "$TEST_MODEL_DIR/glyc.dat"
cp "$REFERENCE_INPUT/list"      "$TEST_MODEL_DIR/list"
pass "Copied reference PDB, alignment, glycan data, list"

# Create input.dat with NRUNS=1 (minimal test)
cat > "$TEST_MODEL_DIR/input.dat" << EOF
NRUNS=1
ATTACH_GAPS=TRUE
GEF_PROBE_RADIUS=3
EOF
pass "Created input.dat with NRUNS=1"

# Create top-level metadata.txt
cat > "$TEST_INPUT_DIR/metadata.txt" << EOF
USER_ID=$TEST_USER_ID
EMAIL=
JOB_NAME=${TEST_USER_ID}_e2e_test
NAME=E2E Test
ORGANIZATION=Automated Test
DESCRIPTION=End-to-end pipeline validation with NRUNS=1
TIMESTAMP=$(date +%s)
FOLDER_COUNT=1
EOF
pass "Created top-level metadata.txt"

# Create model-level metadata.txt
cat > "$TEST_MODEL_DIR/metadata.txt" << EOF
USER_ID=$TEST_USER_ID
EMAIL=
JOB_NAME=$TEST_MODEL
NAME=E2E Test
NUMBER_OF_RUNS=1
GEF_PROBE_RADIUS=3
TIMESTAMP=$(date +%s)
EOF
pass "Created model-level metadata.txt"

echo ""
echo "  Test input structure:"
find "$TEST_INPUT_DIR" -type f | sed "s|$SCRIPT_DIR/||" | sort | while read -r f; do
  echo "    $f"
done
echo ""

if [[ "$DRY_RUN" == "true" ]]; then
  bold "=== DRY RUN: Input created. Verify above, then run without --dry-run ==="
  echo ""
  echo "  To run the actual test:"
  echo "    bash $SCRIPT_DIR/test_pipeline_e2e.sh"
  echo ""
  echo "  To remove test input:"
  echo "    rm -rf $TEST_INPUT_DIR"
  exit 0
fi

# ============================================================================
# STEP 2: Run pipeline.sh
# ============================================================================
bold "=== Step 2: Running pipeline.sh ==="

PIPELINE_LOG="$SCRIPT_DIR/logs/e2e_test_pipeline_${TEST_USER_ID}.log"
mkdir -p "$(dirname "$PIPELINE_LOG")"

echo "  Launching: ./pipeline.sh $TEST_INPUT_DIR"
echo "  Pipeline log: $PIPELINE_LOG"
echo ""

# Run pipeline and capture output
set +e
bash "$SCRIPT_DIR/pipeline.sh" "$TEST_INPUT_DIR" 2>&1 | tee "$PIPELINE_LOG"
PIPELINE_EXIT=$?
set -e

if [[ $PIPELINE_EXIT -eq 0 ]]; then
  pass "pipeline.sh exited successfully (code 0)"
else
  fail "pipeline.sh exited with code $PIPELINE_EXIT"
  echo "  Check log: $PIPELINE_LOG"
fi

# Extract submitted job IDs from pipeline log
echo ""
bold "=== Step 3: Extracting Submitted Job IDs ==="

ALLOSMOD_JOBS=($(grep -oP 'AllosMod jobs submitted: \K[\d ]+' "$PIPELINE_LOG" 2>/dev/null || true))
GET_PDB_JOBS=($(grep -oP 'Submitted get_pdb for .+: Job ID \K\d+' "$PIPELINE_LOG" 2>/dev/null || true))
GEF_JOBS=($(grep -oP 'Submitted GEF analysis for .+: Job ID \K\d+' "$PIPELINE_LOG" 2>/dev/null || true))
BURGLY_JOBS=($(grep -oP 'Submitted Burgly analysis for .+: Job ID \K\d+' "$PIPELINE_LOG" 2>/dev/null || true))
MADISON_JOBS=($(grep -oP 'Submitted Madison analysis for .+: Job ID \K\d+' "$PIPELINE_LOG" 2>/dev/null || true))

ALL_JOBS=("${ALLOSMOD_JOBS[@]}" "${GET_PDB_JOBS[@]}" "${GEF_JOBS[@]}" "${BURGLY_JOBS[@]}" "${MADISON_JOBS[@]}")

echo "  AllosMod:  ${ALLOSMOD_JOBS[*]:-none}"
echo "  Ensemble:  ${GET_PDB_JOBS[*]:-none}"
echo "  GEF:       ${GEF_JOBS[*]:-none}"
echo "  Burgly:    ${BURGLY_JOBS[*]:-none}"
echo "  Madison:   ${MADISON_JOBS[*]:-none}"
echo "  Total:     ${#ALL_JOBS[@]} jobs"
echo ""

if [[ ${#ALL_JOBS[@]} -eq 0 ]]; then
  fail "No SLURM jobs were submitted!"
  echo "  Something went wrong during pipeline submission."
  echo "  Check: $PIPELINE_LOG"
  exit 1
else
  pass "${#ALL_JOBS[@]} SLURM jobs submitted"
fi

# ============================================================================
# STEP 4: Monitor SLURM jobs
# ============================================================================
bold "=== Step 4: Monitoring SLURM Jobs ==="

elapsed=0
check_count=0

while true; do
  still_running=0
  for job_id in "${ALL_JOBS[@]}"; do
    if squeue -j "$job_id" -h 2>/dev/null | grep -q "$job_id"; then
      ((still_running++))
    fi
  done

  if [[ $still_running -eq 0 ]]; then
    echo ""
    pass "All jobs completed after ~$((elapsed / 60)) minutes"
    break
  fi

  if [[ $elapsed -ge $MAX_WAIT ]]; then
    echo ""
    fail "TIMEOUT: $still_running jobs still running after $((MAX_WAIT / 3600))h"
    echo "  Remaining jobs:"
    for job_id in "${ALL_JOBS[@]}"; do
      state=$(squeue -j "$job_id" -h -o "%T" 2>/dev/null || echo "UNKNOWN")
      [[ "$state" != "" ]] && echo "    Job $job_id: $state"
    done
    break
  fi

  ((check_count++))
  if [[ $((check_count % 5)) -eq 0 ]]; then
    echo "  [$(date +%H:%M:%S)] Waiting... $still_running/$((${#ALL_JOBS[@]})) jobs running (~$((elapsed / 60))m elapsed)"
  fi

  sleep "$POLL_INTERVAL"
  elapsed=$((elapsed + POLL_INTERVAL))
done

echo ""

# ============================================================================
# STEP 5: Check job exit statuses
# ============================================================================
bold "=== Step 5: SLURM Job Exit Statuses ==="

all_succeeded=true
for job_id in "${ALL_JOBS[@]}"; do
  state=$(sacct -j "$job_id" --format=State --noheader 2>/dev/null | head -1 | tr -d ' ')
  exitcode=$(sacct -j "$job_id" --format=ExitCode --noheader 2>/dev/null | head -1 | tr -d ' ')
  
  if [[ "$state" == "COMPLETED" ]]; then
    pass "Job $job_id: $state ($exitcode)"
  elif [[ "$state" == "FAILED" ]] || [[ "$state" == "CANCELLED" ]] || [[ "$state" == "TIMEOUT" ]]; then
    fail "Job $job_id: $state ($exitcode)"
    all_succeeded=false
  else
    warn "Job $job_id: $state ($exitcode)"
  fi
done
echo ""

# ============================================================================
# STEP 6: Validate output files
# ============================================================================
bold "=== Step 6: Validating Output Files ==="

MODEL_OUTPUT="$TEST_OUTPUT_DIR/$TEST_MODEL"

# Expected outputs per stage
check_output() {
  local path="$1"
  local desc="$2"
  if [[ -f "$path" ]]; then
    local size=$(stat --format="%s" "$path" 2>/dev/null || echo 0)
    if [[ $size -gt 0 ]]; then
      pass "$desc ($(numfmt --to=iec $size 2>/dev/null || echo "${size}B"))"
    else
      fail "$desc — exists but EMPTY"
    fi
  else
    fail "$desc — NOT FOUND: $path"
  fi
}

echo "  --- Ensemble Modeling ---"
check_output "$MODEL_OUTPUT/output.pdb"                  "output.pdb (raw ensemble)"
check_output "$MODEL_OUTPUT/output_aligned.pdb"          "output_aligned.pdb (aligned ensemble)"

echo ""
echo "  --- GEF Analysis ---"
check_output "$MODEL_OUTPUT/processed_GEF_output.csv"    "processed_GEF_output.csv"
check_output "$MODEL_OUTPUT/GEF_CHA_X.dat"               "GEF_CHA_X.dat"
check_output "$MODEL_OUTPUT/GEF_CHA_Y.dat"               "GEF_CHA_Y.dat"
check_output "$MODEL_OUTPUT/GEF_CHA_Z.dat"               "GEF_CHA_Z.dat"

# Check for at least one GEF plot
gef_plots=$(find "$MODEL_OUTPUT" -maxdepth 1 -name "gef_data_range_*.png" 2>/dev/null | wc -l)
if [[ $gef_plots -gt 0 ]]; then
  pass "GEF plots: $gef_plots .png files"
else
  fail "No GEF plot files (gef_data_range_*.png)"
fi

echo ""
echo "  --- Burgly Depth Analysis ---"
check_output "$MODEL_OUTPUT/burgly_analysis/glycan_depth_CAR1.csv"     "glycan_depth_CAR1.csv"
check_output "$MODEL_OUTPUT/burgly_analysis/glycan_depth_CAR2.csv"     "glycan_depth_CAR2.csv"
check_output "$MODEL_OUTPUT/burgly_analysis/glycan_depth_CAR3.csv"     "glycan_depth_CAR3.csv"
check_output "$MODEL_OUTPUT/burgly_analysis/glycan_depth_heatmap.png"  "glycan_depth_heatmap.png"

echo ""
echo "  --- Madison Adjacency Analysis ---"
madison_dir="$MODEL_OUTPUT/madison_analysis"
if [[ -d "$madison_dir" ]]; then
  # Check for adjacency matrix CSV
  adj_csv=$(find "$madison_dir" -name "*adjacency*matrix*.csv" 2>/dev/null | head -1)
  if [[ -n "$adj_csv" ]]; then
    pass "Adjacency matrix CSV found: $(basename "$adj_csv")"
  else
    fail "No adjacency matrix CSV in madison_analysis/"
  fi
  
  # Check for at least one heatmap
  madison_plots=$(find "$madison_dir" -name "*.png" 2>/dev/null | wc -l)
  if [[ $madison_plots -gt 0 ]]; then
    pass "Madison plots: $madison_plots .png files"
  else
    fail "No Madison plot files"
  fi
else
  fail "madison_analysis/ directory not found"
fi

echo ""

# ============================================================================
# STEP 7: Validate logs
# ============================================================================
bold "=== Step 7: Validating Log Files ==="

if [[ -d "$TEST_LOG_DIR" ]]; then
  pass "Log directory exists: $TEST_LOG_DIR"
  
  for stage in pipeline allosmod_run ensemble_modelling gef_analysis burgly_analysis madison_analysis; do
    stage_dir="$TEST_LOG_DIR/$stage"
    if [[ -d "$stage_dir" ]]; then
      log_count=$(find "$stage_dir" -type f | wc -l)
      pass "$stage/ — $log_count log file(s)"
    else
      warn "$stage/ — not created"
    fi
  done
else
  fail "Log directory not created: $TEST_LOG_DIR"
fi
echo ""

# ============================================================================
# SUMMARY
# ============================================================================
bold "============================================"
bold "E2E TEST RESULTS"
bold "============================================"
echo ""
echo "  Test User ID: $TEST_USER_ID"
echo "  Model:        $TEST_MODEL"
echo "  NRUNS:        1"
echo ""
green "  Passed:   $PASS"
[[ $WARN -gt 0 ]] && yellow "  Warnings: $WARN"
[[ $FAIL -gt 0 ]] && red    "  Failed:   $FAIL"
echo ""

if [[ $FAIL -eq 0 ]]; then
  bold "$(green '🎉 ALL TESTS PASSED — Pipeline is working end-to-end!')"
  echo ""
  echo "  To clean up test data:"
  echo "    rm -rf $TEST_INPUT_DIR $TEST_OUTPUT_DIR $TEST_LOG_DIR $PIPELINE_LOG"
else
  bold "$(red '❌ SOME TESTS FAILED — Review output above for details.')"
  echo ""
  echo "  Debug resources:"
  echo "    Pipeline log: $PIPELINE_LOG"
  echo "    SLURM logs:   $TEST_LOG_DIR"
  echo "    Input data:   $TEST_INPUT_DIR"
  echo "    Output data:  $TEST_OUTPUT_DIR"
fi

echo ""
bold "============================================"

exit $FAIL
