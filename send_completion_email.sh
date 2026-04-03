#!/bin/bash
#SBATCH --job-name=send_email
#SBATCH --partition=short
#SBATCH --time=02:00:00
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=2
#SBATCH --mem=8G

# Script to upload results to Azure and send completion email
# This script will be submitted as a SLURM job with dependencies on all GEF jobs

set -euo pipefail

# Parse arguments
if [[ $# -ne 2 ]]; then
  echo "Usage: $0 <FOLDER_PATH> <SCRIPT_DIR>"
  echo ""
  echo "The FOLDER_PATH must contain a metadata.txt file with:"
  echo "  USER_ID=<user_identifier>"
  echo "  EMAIL=<user_email>"
  echo "  JOB_NAME=<job_name>"
  exit 1
fi

FOLDER_PATH="$1"
SCRIPT_DIR="$2"

# ------------------------------
# METADATA LOADING
# ------------------------------
METADATA_FILE="${FOLDER_PATH}/metadata.txt"

if [[ ! -f "$METADATA_FILE" ]]; then
  echo "Error: metadata.txt not found in $FOLDER_PATH"
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
JOB_NAME=$(read_metadata "JOB_NAME")
USER_NAME="$USER_ID"  # Use USER_ID as USER_NAME if not separately specified

# Validate metadata
if [[ -z "$USER_ID" ]]; then
  echo "Error: USER_ID not found in metadata.txt"
  exit 1
fi

if [[ -z "$JOB_NAME" ]]; then
  echo "Error: JOB_NAME not found in metadata.txt"
  exit 1
fi

echo "============================================"
echo "GLACIER Pipeline Completion Processing"
echo "============================================"
echo "Metadata File: $METADATA_FILE"
echo "Job: $JOB_NAME"
echo "User: $USER_ID"
echo "Email: $EMAIL"
echo "Time: $(date)"
echo "============================================"

# Define paths
OUTPUT_BASE="${OUTPUT_DIR:-/projects/SimBioSys/share/software/GlycoShield/outputs}"
USER_OUTPUT_DIR="${OUTPUT_BASE}/${USER_ID}"
INPUTS_BASE="${INPUTS_DIR:-/projects/SimBioSys/share/software/GlycoShield/inputs}"
USER_INPUTS_DIR="${INPUTS_BASE}/${USER_ID}"
LOGS_BASE="${LOGS_DIR:-/projects/SimBioSys/share/software/GlycoShield/logs}"
USER_LOGS_DIR="${LOGS_BASE}/${USER_ID}"
AZURE_SCRIPT="${SCRIPT_DIR}/azure_glycoshield.py"
INDEX_SCRIPT="${SCRIPT_DIR}/generate_azure_index.py"
TRIGGER_EMAIL="${SCRIPT_DIR}/trigger_email.py"
LOG_BASE="${SCRIPT_DIR}/logs"

# Step 1: Verify user output directory exists
echo ""
echo "Step 1: Verifying output directory..."
echo "Output directory: $USER_OUTPUT_DIR"

if [[ ! -d "$USER_OUTPUT_DIR" ]]; then
  echo "Error: User output directory not found: $USER_OUTPUT_DIR"
  exit 1
fi

# Count files
FILE_COUNT=$(find "$USER_OUTPUT_DIR" -type f | wc -l)
TOTAL_SIZE=$(du -sh "$USER_OUTPUT_DIR" | cut -f1)
echo "✓ Output directory verified"
echo "  Files: $FILE_COUNT"
echo "  Total size: $TOTAL_SIZE"

# Step 2: Upload to Azure
echo ""
echo "Step 2: Uploading files to Azure Blob Storage..."

if [[ ! -f "$AZURE_SCRIPT" ]]; then
  echo "Error: Azure script not found at $AZURE_SCRIPT"
  exit 1
fi

# Activate conda environment for Azure SDK
echo "Activating conda environment..."
set +u
source /shared/centos7/anaconda3/3.7/bin/activate /projects/SimBioSys/share/software/allosmod-env 2>/dev/null || true
set -u

# Check if we can load Azure credentials
if python3 -c "from dotenv import load_dotenv; load_dotenv(); import os; exit(0 if os.getenv('AZURE_CONNECTION_STRING') else 1)" 2>/dev/null; then
  echo "✓ Azure credentials loaded"
else
  echo "Error: AZURE_CONNECTION_STRING not found in environment"
  echo "Please check .env file configuration"
  exit 1
fi

# Upload files and capture the viewing URL
echo ""
echo "Uploading files to Azure..."
echo "This may take several minutes depending on file sizes..."
echo ""

# Upload outputs folder (main results)
echo "📤 Uploading outputs folder..."
AZURE_UPLOAD_OUTPUT=$(python3 "$AZURE_SCRIPT" upload-files "$USER_ID" "$USER_OUTPUT_DIR" 2>&1)
UPLOAD_EXIT_CODE=$?
echo "$AZURE_UPLOAD_OUTPUT"

if [[ $UPLOAD_EXIT_CODE -ne 0 ]]; then
  echo "✗ Failed to upload outputs to Azure"
  echo "Check logs for details"
  exit 1
fi

# Upload inputs folder (user-uploaded files only, excluding AllosMod-generated files)
if [[ -d "$USER_INPUTS_DIR" ]]; then
  echo ""
  echo "📤 Uploading user input files..."
  python3 -c "
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
inputs_dir = '${USER_INPUTS_DIR}'

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
" 2>&1
else
  echo "⚠ Inputs folder not found, skipping: $USER_INPUTS_DIR"
fi

# Upload logs folder (pipeline execution logs)
if [[ -d "$USER_LOGS_DIR" ]]; then
  echo ""
  echo "📤 Uploading logs folder..."
  python3 -c "
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
logs_dir = '${USER_LOGS_DIR}'

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

print('✓ Logs folder uploaded')
" 2>&1
else
  echo "⚠ Logs folder not found, skipping: $USER_LOGS_DIR"
fi

# Extract sharing link from outputs upload
SHARING_LINK=$(echo "$AZURE_UPLOAD_OUTPUT" | grep -E '^https://' | tail -1)

if [[ -z "$SHARING_LINK" ]]; then
  echo "Warning: Could not extract sharing link from upload output"
  # Try to get it from the saved file
  AZURE_URL_FILE="${LOG_BASE}/${USER_ID}/azure_folder_url.txt"
  if [[ -f "$AZURE_URL_FILE" ]]; then
    SHARING_LINK=$(cat "$AZURE_URL_FILE")
    echo "✓ Retrieved sharing link from saved file"
  else
    echo "Error: No sharing link available"
    exit 1
  fi
fi

echo ""
echo "✓ All files uploaded successfully to Azure"
echo "📂 View URL: $SHARING_LINK"

# Step 3: Generate browsable HTML index
echo ""
echo "Step 3: Generating browsable index page..."

if [[ -f "$INDEX_SCRIPT" ]]; then
  INDEX_OUTPUT=$(python3 "$INDEX_SCRIPT" "$USER_ID" 2>&1)
  INDEX_EXIT_CODE=$?
  
  if [[ $INDEX_EXIT_CODE -eq 0 ]]; then
    INDEX_URL=$(echo "$INDEX_OUTPUT" | grep -E '^https://' | tail -1)
    echo "✓ Index page generated"
    echo "🌐 Browse results: $INDEX_URL"
    
    # Use index URL as the sharing link for email
    SHARING_LINK="$INDEX_URL"
  else
    echo "⚠ Failed to generate index page, using folder URL"
    echo "$INDEX_OUTPUT"
  fi
else
  echo "⚠ Index generator not found, using folder URL"
fi

# Step 4: Send completion email (only if email is available)
echo ""
echo "Step 4: Sending completion email..."

if [[ -z "$EMAIL" ]]; then
  echo "Info: No email address provided, skipping completion notification"
  echo "Results have been uploaded to Azure"
  echo "Sharing link: $SHARING_LINK"
else
  if [[ ! -f "$TRIGGER_EMAIL" ]]; then
    echo "Warning: Email trigger script not found at $TRIGGER_EMAIL"
    echo "Skipping email notification but job completed successfully"
  else
    # Send completion email with download link
    if python3 "$TRIGGER_EMAIL" completion "$EMAIL" "$USER_ID" "$JOB_NAME" "$USER_NAME" --download-link "$SHARING_LINK" 2>&1; then
      echo "✓ Completion email sent successfully to $EMAIL"
    else
      echo "Warning: Failed to send completion email to $EMAIL"
      echo "Job completed successfully but email notification failed"
    fi
  fi
fi

# Step 5: Summary
echo ""
echo "============================================"
echo "Pipeline Completion Summary"
echo "============================================"
echo "User ID: $USER_ID"
echo "Job Name: $JOB_NAME"
echo "Files Uploaded: $FILE_COUNT"
echo "Total Size: $TOTAL_SIZE"
echo "Azure URL: $SHARING_LINK"
if [[ -n "$EMAIL" ]]; then
  echo "Email notification sent to: $EMAIL"
fi
echo ""
echo "✓ All processing complete!"
echo "============================================"

exit 0
