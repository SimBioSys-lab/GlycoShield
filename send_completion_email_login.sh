#!/bin/bash
# Send completion email from login node
# This is called by the background monitor (wait_and_email.sh)
#
# UPDATED: Stages only user-facing result files before uploading to Azure.
# Full outputs remain on disk; only curated results are shared.
#
# IMPORTANT: We intentionally do NOT use set -e here.
# Each step is independently error-handled so that a failure in one step
# (e.g., Azure upload) does not prevent subsequent steps (e.g., email) from running.

set -uo pipefail

# Track overall status for exit code
OVERALL_STATUS=0

# Parse arguments
if [[ $# -ne 2 ]]; then
  echo "Usage: $0 <FOLDER_PATH> <SCRIPT_DIR>"
  exit 1
fi

FOLDER_PATH="$1"
SCRIPT_DIR="$2"

echo "============================================"
echo "GlycoShield Completion Processing (Login Node)"
echo "============================================"
echo "Folder: $FOLDER_PATH"
echo "Script Dir: $SCRIPT_DIR"
echo ""

# Activate conda environment for Azure SDK and email
set +u
source /shared/centos7/anaconda3/3.7/bin/activate /projects/SimBioSys/share/software/allosmod-env 2>/dev/null || true
set -u

# Load .env file if exists
if [[ -f "${SCRIPT_DIR}/.env" ]]; then
  set -a
  source "${SCRIPT_DIR}/.env"
  set +a
  echo "Loaded .env from: ${SCRIPT_DIR}/.env"
fi

# Load metadata
METADATA_FILE="${FOLDER_PATH}/metadata.txt"

if [[ ! -f "$METADATA_FILE" ]]; then
  echo "Error: metadata.txt not found in $FOLDER_PATH"
  exit 1
fi

read_metadata() {
  local key="$1"
  local value=$(grep "^${key}=" "$METADATA_FILE" | cut -d'=' -f2- | tr -d '\r\n' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
  echo "$value"
}

USER_ID=$(read_metadata "USER_ID")
EMAIL=$(read_metadata "EMAIL")
JOB_NAME=$(read_metadata "JOB_NAME")
USER_NAME=$(read_metadata "NAME")
# Fallback to USER_ID if NAME not set
USER_NAME="${USER_NAME:-$USER_ID}"

echo "User ID: $USER_ID"
echo "Email: $EMAIL"
echo "Job Name: $JOB_NAME"
echo "User Name: $USER_NAME"
echo ""

# Define paths
AZURE_SCRIPT="${SCRIPT_DIR}/azure_glycoshield.py"
OUTPUT_BASE="${SCRIPT_DIR}/outputs/${USER_ID}"
LOGS_BASE="${SCRIPT_DIR}/logs/${USER_ID}"

# Default sharing link (fallback)
SHARING_LINK="https://glacierstorage01.blob.core.windows.net/glacier/${USER_ID}/index.html"

# ============================================================
# Step 1: Stage only user-facing result files
# ============================================================
echo "Step 1: Staging user-facing result files..."

STAGING_DIR="/tmp/glacier_share_${USER_ID}_$$"
mkdir -p "$STAGING_DIR"

stage_count=0
stage_errors=0

# Iterate over each model folder in outputs
if [[ -d "$OUTPUT_BASE" ]]; then
  for MODEL_DIR in "$OUTPUT_BASE"/*/; do
    MODEL_NAME=$(basename "$MODEL_DIR")
    STAGE_MODEL="$STAGING_DIR/$MODEL_NAME"
    mkdir -p "$STAGE_MODEL"

    echo "  Staging model: $MODEL_NAME"

    # (i) output_aligned.pdb — check both old (root) and new (ensemble/) layouts
    for pdb_path in "$MODEL_DIR/output_aligned.pdb" "$MODEL_DIR/ensemble/output_aligned.pdb"; do
      if [[ -f "$pdb_path" ]]; then
        cp "$pdb_path" "$STAGE_MODEL/output_aligned.pdb"
        echo "    ✓ output_aligned.pdb"
        ((stage_count++))
        break
      fi
    done

    # (ii) GEF CSV — check both old (root) and new (gef/) layouts
    for csv_path in "$MODEL_DIR/processed_GEF_output.csv" "$MODEL_DIR/gef/processed_GEF_output.csv"; do
      if [[ -f "$csv_path" ]]; then
        mkdir -p "$STAGE_MODEL/gef"
        cp "$csv_path" "$STAGE_MODEL/gef/processed_GEF_output.csv"
        echo "    ✓ gef/processed_GEF_output.csv"
        ((stage_count++))
        break
      fi
    done

    # (iii) GEF single-frame PDB
    for pdb_path in "$MODEL_DIR/gef_single_frame.pdb" "$MODEL_DIR/gef/gef_single_frame.pdb"; do
      if [[ -f "$pdb_path" ]]; then
        mkdir -p "$STAGE_MODEL/gef"
        cp "$pdb_path" "$STAGE_MODEL/gef/gef_single_frame.pdb"
        echo "    ✓ gef/gef_single_frame.pdb"
        ((stage_count++))
        break
      fi
    done

    # (iv) GEF PNG plots — check both layouts
    gef_pngs_found=0
    for gef_dir in "$MODEL_DIR" "$MODEL_DIR/gef"; do
      if ls "$gef_dir"/gef_data_range_*.png 1>/dev/null 2>&1; then
        mkdir -p "$STAGE_MODEL/gef"
        cp "$gef_dir"/gef_data_range_*.png "$STAGE_MODEL/gef/"
        gef_pngs_found=$(ls "$STAGE_MODEL/gef"/gef_data_range_*.png 2>/dev/null | wc -l)
        echo "    ✓ gef/gef_data_range_*.png ($gef_pngs_found files)"
        stage_count=$((stage_count + gef_pngs_found))
        break
      fi
    done

    # (v) Madison/interglycan PNGs and CSVs — check both old and new dir names
    for madison_dir in "$MODEL_DIR/interglycan_interactions" "$MODEL_DIR/madison_analysis"; do
      if [[ -d "$madison_dir" ]]; then
        mkdir -p "$STAGE_MODEL/interglycan_interactions"
        madison_staged=0

        # CSVs
        for f in "$madison_dir"/*adjacency_matrix*.csv "$madison_dir"/aggregated_*.csv; do
          if [[ -f "$f" ]]; then
            cp "$f" "$STAGE_MODEL/interglycan_interactions/"
            ((madison_staged++))
            ((stage_count++))
          fi
        done

        # PNGs
        for f in "$madison_dir"/*.png; do
          if [[ -f "$f" ]]; then
            cp "$f" "$STAGE_MODEL/interglycan_interactions/"
            ((madison_staged++))
            ((stage_count++))
          fi
        done

        if [[ $madison_staged -gt 0 ]]; then
          echo "    ✓ interglycan_interactions/ ($madison_staged files)"
        fi
        break
      fi
    done

    # (vi) Burgly PNGs and CSVs — check both old and new dir names
    for burgly_dir in "$MODEL_DIR/burgly" "$MODEL_DIR/burgly_analysis"; do
      if [[ -d "$burgly_dir" ]]; then
        mkdir -p "$STAGE_MODEL/burgly"
        burgly_staged=0

        # CSVs (glycan_depth_CAR*.csv)
        for f in "$burgly_dir"/glycan_depth_CAR*.csv; do
          if [[ -f "$f" ]]; then
            cp "$f" "$STAGE_MODEL/burgly/"
            ((burgly_staged++))
            ((stage_count++))
          fi
        done

        # Heatmap PNG
        if [[ -f "$burgly_dir/glycan_depth_heatmap.png" ]]; then
          cp "$burgly_dir/glycan_depth_heatmap.png" "$STAGE_MODEL/burgly/"
          ((burgly_staged++))
          ((stage_count++))
        fi

        if [[ $burgly_staged -gt 0 ]]; then
          echo "    ✓ burgly/ ($burgly_staged files)"
        fi
        break
      fi
    done

  done

  echo ""
  echo "  Staged $stage_count files total to: $STAGING_DIR"
else
  echo "⚠ Output directory not found: $OUTPUT_BASE"
  OVERALL_STATUS=1
fi

echo ""

# ============================================================
# Step 2: Upload staged results to Azure
# ============================================================
echo "Step 2: Uploading staged results to Azure..."

if [[ -f "$AZURE_SCRIPT" ]] && [[ -d "$STAGING_DIR" ]] && [[ $stage_count -gt 0 ]]; then
  UPLOAD_EXIT=0
  UPLOAD_OUTPUT=$(python3 "$AZURE_SCRIPT" upload-files "$USER_ID" "$STAGING_DIR" 2>&1) || UPLOAD_EXIT=$?
  echo "$UPLOAD_OUTPUT"

  if [[ $UPLOAD_EXIT -ne 0 ]]; then
    echo "⚠ Azure upload exited with code $UPLOAD_EXIT (continuing with remaining steps)"
    OVERALL_STATUS=1
  fi

  # Extract Azure URL
  AZURE_URL=$(echo "$UPLOAD_OUTPUT" | grep -oP "https://[^\s]+" | tail -1 || true)

  if [[ -n "$AZURE_URL" ]]; then
    echo "✓ Staged results uploaded to: $AZURE_URL"
    SHARING_LINK="$AZURE_URL"
  else
    echo "⚠ Azure upload completed but URL not extracted, using fallback URL"
  fi
else
  echo "⚠ Azure script or staging directory not found, or nothing to upload"
  OVERALL_STATUS=1
fi

# Clean up staging directory
rm -rf "$STAGING_DIR"
echo "✓ Staging directory cleaned up"

# ============================================================
# Step 3: Upload AllosMod logs on failure (conditional)
# ============================================================
echo ""
echo "Step 3: Checking for failed jobs (conditional log upload)..."

if [[ -d "$LOGS_BASE" ]]; then
  # Check for any error indicators in log files
  has_failures=false

  for err_file in "$LOGS_BASE"/*/*.err "$LOGS_BASE"/*/*/*.err; do
    if [[ -f "$err_file" ]] && [[ -s "$err_file" ]]; then
      # Check if error file contains actual errors (not just warnings)
      if grep -qiE "error|failed|fatal|traceback|exception" "$err_file" 2>/dev/null; then
        has_failures=true
        break
      fi
    fi
  done

  if [[ "$has_failures" == "true" ]]; then
    echo "  ⚠ Failures detected — uploading logs for debugging..."
    python3 << PYEOF || { echo "⚠ Log upload failed (continuing)"; OVERALL_STATUS=1; }
import os
import sys
sys.path.insert(0, '${SCRIPT_DIR}')
from dotenv import load_dotenv
load_dotenv('${SCRIPT_DIR}/.env')
from azure.storage.blob import BlobServiceClient

conn_str = os.getenv('AZURE_CONNECTION_STRING')
client = BlobServiceClient.from_connection_string(conn_str)
cont = client.get_container_client('glacier')

user_id = '${USER_ID}'
logs_dir = '${LOGS_BASE}'
uploaded = 0

for root, dirs, files in os.walk(logs_dir):
    for filename in files:
        if filename.startswith('.'):
            continue
        local_path = os.path.join(root, filename)
        relative_path = os.path.relpath(local_path, logs_dir)
        blob_path = f'{user_id}/logs/{relative_path}'.replace('\\\\', '/')

        with open(local_path, 'rb') as data:
            blob_client = cont.get_blob_client(blob_path)
            blob_client.upload_blob(data, overwrite=True)
        uploaded += 1

print(f'✓ Logs uploaded for debugging ({uploaded} files)')
PYEOF
  else
    echo "  ✓ No failures detected — skipping log upload"
  fi
else
  echo "  ℹ No logs directory found, skipping"
fi

# ============================================================
# Step 4: Regenerate the index to include all uploaded files
# ============================================================
echo ""
echo "Step 4: Regenerating index page..."
INDEX_SCRIPT="${SCRIPT_DIR}/generate_azure_index.py"

if [[ -f "$INDEX_SCRIPT" ]]; then
  INDEX_OUTPUT=$(python3 "$INDEX_SCRIPT" "$USER_ID" 2>&1) || { echo "⚠ Index generation failed (continuing)"; }
  echo "$INDEX_OUTPUT"

  # Update sharing link to the new index
  NEW_INDEX_URL=$(echo "$INDEX_OUTPUT" | grep -oP "https://[^\s]+" | tail -1 || true)
  if [[ -n "$NEW_INDEX_URL" ]]; then
    SHARING_LINK="$NEW_INDEX_URL"
    echo "✓ Index regenerated"
  fi
else
  echo "⚠ Index script not found: $INDEX_SCRIPT"
fi

# ============================================================
# Step 5: Send completion email (MOST CRITICAL - always attempt)
# ============================================================
echo ""
echo "Step 5: Sending completion email..."

if [[ -z "$EMAIL" ]]; then
  echo "ℹ No email address provided, skipping email notification"
  echo "  Results are still available at: $SHARING_LINK"
else
  TRIGGER_EMAIL="${SCRIPT_DIR}/trigger_email.py"

  if [[ -f "$TRIGGER_EMAIL" ]]; then
    echo "Calling: python3 $TRIGGER_EMAIL completion $EMAIL $USER_ID $JOB_NAME $USER_NAME --download-link $SHARING_LINK"

    python3 "$TRIGGER_EMAIL" completion "$EMAIL" "$USER_ID" "$JOB_NAME" "$USER_NAME" \
      --download-link "$SHARING_LINK" 2>&1

    EMAIL_EXIT=$?
    if [[ $EMAIL_EXIT -eq 0 ]]; then
      echo "✓ Email sent to $EMAIL"
    else
      echo "⚠ Email sending failed with exit code: $EMAIL_EXIT"
      OVERALL_STATUS=1

      # Retry once after a short delay
      echo "  Retrying email in 10 seconds..."
      sleep 10
      python3 "$TRIGGER_EMAIL" completion "$EMAIL" "$USER_ID" "$JOB_NAME" "$USER_NAME" \
        --download-link "$SHARING_LINK" 2>&1
      RETRY_EXIT=$?
      if [[ $RETRY_EXIT -eq 0 ]]; then
        echo "  ✓ Email sent on retry"
      else
        echo "  ✗ Email retry also failed with exit code: $RETRY_EXIT"
      fi
    fi
  else
    echo "⚠ Email trigger script not found: $TRIGGER_EMAIL"
    OVERALL_STATUS=1
  fi
fi

echo ""
echo "============================================"
if [[ $OVERALL_STATUS -eq 0 ]]; then
  echo "✓ Completion processing finished successfully"
else
  echo "⚠ Completion processing finished with some errors (see above)"
fi
echo "============================================"
echo "Results URL: $SHARING_LINK"
echo ""

exit $OVERALL_STATUS
