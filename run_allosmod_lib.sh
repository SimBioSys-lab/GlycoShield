#!/bin/bash
#SBATCH --nodes=1
#SBATCH --cpus-per-task=12
#SBATCH --ntasks-per-node=1
#SBATCH --partition=gpu
#SBATCH --gres=gpu:h200:1
#SBATCH --mem=128G
#SBATCH --time=08:00:00

set -euo pipefail

# ------------------------------
# .env loader
# ------------------------------
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
try_source_env() {
  local envfile="$1"
  [[ -f "$envfile" ]] || return 1
  set -a; . "$envfile"; set +a
  echo "Loaded .env from: $envfile"
}
try_source_env ".env" || true
try_source_env "$SCRIPT_DIR/.env" || true

# ------------------------------
# args
# ------------------------------
if [[ $# -ne 4 ]]; then
  echo "Usage: $0 <FOLDER_PATH> <USER_ID> <EMAIL> <NAME>"
  exit 1
fi
FOLDER_PATH="$1"
USER_ID="$2"
EMAIL="$3"
NAME="$4"

try_source_env "$FOLDER_PATH/.env" || true
try_source_env "$(dirname "$FOLDER_PATH")/.env" || true

# ------------------------------
# logging
# ------------------------------
BASE_LOG_ROOT="${LOG_DIR:-${LOG_ROOT:-"$PWD/logs"}}"
USER_LOG_ROOT="${BASE_LOG_ROOT%/}/${USER_ID}"
LOG_DIR="${USER_LOG_ROOT}/allosmod_run"
mkdir -p "$LOG_DIR"
exec > >(tee -a "$LOG_DIR/allosmod-gpu.out") 2> >(tee -a "$LOG_DIR/allosmod-gpu.err" >&2)

# ------------------------------
# modules & environment
# ------------------------------
module purge || true
module use /projects/SimBioSys/share/software/modulefiles
module load allosmod

export ALLOSMOD_ENV=/projects/SimBioSys/share/software/allosmod-env
export ALLSMOD_DATA=/projects/SimBioSys/share/software/allosmod-env/opt/allosmod/data

# ------------------------------
# input checks
# ------------------------------
if [[ ! -d "$FOLDER_PATH" ]]; then
  echo "Error: Directory '$FOLDER_PATH' not found!"
  exit 1
fi

echo "Starting job for USER_ID: $USER_ID, EMAIL: $EMAIL, NAME: $NAME, FOLDER_PATH: $FOLDER_PATH"
job_ids=()

# ------------------------------
# main loop over subfolders
# ------------------------------
for folder in "$FOLDER_PATH"/*; do
  [[ -d "$folder" ]] || { echo "Skipping (not a dir): $folder"; continue; }

  input_dat="$folder/input.dat"
  echo "Processing: $folder"
  if [[ ! -f "$input_dat" ]]; then
    echo "No input.dat in $folder — skipping"
    continue
  fi

  # get NRUNS (default 1)
  n_runs=$(awk -F '=' '/^NRUNS=/ {print $2}' "$input_dat" || true)
  [[ -n "${n_runs:-}" ]] || n_runs=1
  echo "NRUNS = $n_runs"

  # Generate qsub.sh using AllosMod (runs in the case folder)
  (
    cd "$folder"
    allosmod setup
  )

  qsub_script="$folder/qsub.sh"
  if [[ ! -f "$qsub_script" ]]; then
    echo "Error: qsub.sh not found after setup in $folder"
    continue
  fi
  chmod +x "$qsub_script"

  # --- Normalize qsub.sh newlines
  perl -pi -e 's/\r$//' "$qsub_script"

  # --- Insert Slurm+env header
  awk -v jobname="qsub-$(basename "$folder")" '
    NR==1 {
      print $0
      print "#SBATCH --job-name=" jobname
      print "export SGE_TASK_ID=${SLURM_ARRAY_TASK_ID:-1}"
      print "module use /projects/SimBioSys/share/software/modulefiles"
      print "module load allosmod"
      print "export ALLOSMOD_ENV=/projects/SimBioSys/share/software/allosmod-env"
      print "export ALLSMOD_DATA=/projects/SimBioSys/share/software/allosmod-env/opt/allosmod/data"
      print "export MODELLER_HOME=/projects/SimBioSys/share/software/modeller-10.7"
      print "export PATH=$MODELLER_HOME/bin:$PATH"
      print "export PYTHONPATH=$MODELLER_HOME/modlib:$MODELLER_HOME/lib/x86_64-intel8/python3.3:$PYTHONPATH"
      print "export LD_LIBRARY_PATH=$MODELLER_HOME/lib/x86_64-intel8:${LD_LIBRARY_PATH:-}"
      next
    }
    { print $0 }
  ' "$qsub_script" > "$qsub_script.tmp" && mv "$qsub_script.tmp" "$qsub_script"

  # Submit the array
  echo "Submitting array for $qsub_script (1-$n_runs) with --chdir=$folder"
  jobid_array=$(sbatch --parsable \
                       --export=ALL \
                       --chdir="$folder" \
                       -a 1-"$n_runs" \
                       --output="$LOG_DIR/qsub_%A_%a.out" \
                       --error="$LOG_DIR/qsub_%A_%a.err" \
                       "$qsub_script")
  echo "Job array ID: $jobid_array"
  job_ids+=("$jobid_array")
done

