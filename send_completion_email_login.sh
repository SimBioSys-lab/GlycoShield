#!/bin/bash
# Send completion email from login node
# This is called by the background monitor (wait_and_email.sh)
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
INPUTS_BASE="${SCRIPT_DIR}/inputs/${USER_ID}"
LOGS_BASE="${SCRIPT_DIR}/logs/${USER_ID}"

# Default sharing link (fallback)
SHARING_LINK="https://glacierstorage01.blob.core.windows.net/glacier/${USER_ID}/index.html"

# ============================================================
# Step 1: Upload outputs folder to Azure
# ============================================================
echo "Step 1: Uploading outputs folder to Azure..."

if [[ -f "$AZURE_SCRIPT" ]] && [[ -d "$OUTPUT_BASE" ]]; then
  UPLOAD_EXIT=0
  UPLOAD_OUTPUT=$(python3 "$AZURE_SCRIPT" upload-files "$USER_ID" "$OUTPUT_BASE" 2>&1) || UPLOAD_EXIT=$?
  echo "$UPLOAD_OUTPUT"
  
  if [[ $UPLOAD_EXIT -ne 0 ]]; then
    echo "⚠ Azure upload exited with code $UPLOAD_EXIT (continuing with remaining steps)"
    OVERALL_STATUS=1
  fi
  
  # Extract Azure URL - use || true to prevent pipefail from killing the script
  AZURE_URL=$(echo "$UPLOAD_OUTPUT" | grep -oP "https://[^\s]+" | tail -1 || true)
  
  if [[ -n "$AZURE_URL" ]]; then
    echo "✓ Outputs uploaded to: $AZURE_URL"
    SHARING_LINK="$AZURE_URL"
  else
    echo "⚠ Azure upload completed but URL not extracted, using fallback URL"
  fi
else
  echo "⚠ Azure script or output directory not found"
  echo "   Azure script: $AZURE_SCRIPT (exists: $(test -f "$AZURE_SCRIPT" && echo yes || echo no))"
  echo "   Output dir: $OUTPUT_BASE (exists: $(test -d "$OUTPUT_BASE" && echo yes || echo no))"
  OVERALL_STATUS=1
fi

# ============================================================
# Step 2: Upload inputs folder to Azure (user-uploaded files only)
# ============================================================
echo ""
echo "Step 2: Uploading user input files to Azure..."

if [[ -d "$INPUTS_BASE" ]]; then
  python3 << PYEOF || { echo "⚠ Input upload failed (continuing)"; OVERALL_STATUS=1; }
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
inputs_dir = '${INPUTS_BASE}'

# Exclude AllosMod-generated files/folders
EXCLUDE_PATTERNS = {'pred_dECALCrAS1000', 'qsub.sh', 'list', 'input.dat'}
uploaded = 0

for root, dirs, files in os.walk(inputs_dir):
    # Skip AllosMod ensemble directories
    dirs[:] = [d for d in dirs if d not in EXCLUDE_PATTERNS]
    
    for filename in files:
        if filename.startswith('.') or filename in EXCLUDE_PATTERNS:
            continue
        local_path = os.path.join(root, filename)
        relative_path = os.path.relpath(local_path, inputs_dir)
        blob_path = f'{user_id}/inputs/{relative_path}'.replace('\\\\', '/')
        
        with open(local_path, 'rb') as data:
            blob_client = cont.get_blob_client(blob_path)
            blob_client.upload_blob(data, overwrite=True)
        uploaded += 1

print(f'✓ User input files uploaded ({uploaded} files)')
PYEOF
else
  echo "⚠ Inputs folder not found at $INPUTS_BASE, skipping"
fi

# ============================================================
# Step 3: Upload logs folder to Azure
# ============================================================
echo ""
echo "Step 3: Uploading logs folder to Azure..."

if [[ -d "$LOGS_BASE" ]]; then
  python3 << PYEOF || { echo "⚠ Logs upload failed (continuing)"; OVERALL_STATUS=1; }
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

print(f'✓ Logs folder uploaded ({uploaded} files)')
PYEOF
else
  echo "⚠ Logs folder not found at $LOGS_BASE, skipping"
fi

# ============================================================
# Step 4: Regenerate the index to include all folders
# ============================================================
echo ""
echo "Step 4: Regenerating index page..."
INDEX_SCRIPT="${SCRIPT_DIR}/generate_azure_index.py"

if [[ -f "$INDEX_SCRIPT" ]]; then
  INDEX_OUTPUT=$(python3 "$INDEX_SCRIPT" "$USER_ID" 2>&1) || { echo "⚠ Index generation failed (continuing)"; }
  echo "$INDEX_OUTPUT"
  
  # Update sharing link to the new index - use || true to prevent pipefail issues
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
