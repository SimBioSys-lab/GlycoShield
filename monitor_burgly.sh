#!/bin/bash
# Monitor Burgly job execution

JOBID="$1"

if [ -z "$JOBID" ]; then
    echo "Usage: $0 <JOBID>"
    echo ""
    echo "Current Burgly jobs:"
    squeue -u $USER | grep -E "JOBID|burgly"
    exit 1
fi

echo "============================================"
echo "Monitoring Burgly Job: $JOBID"
echo "============================================"
echo ""

# Check job status
echo "Job Status:"
squeue -j $JOBID -o "%.18i %.9P %.8T %.10M %.6D %R" 2>/dev/null || echo "Job $JOBID not in queue (may be completed or failed)"

echo ""
echo "Job Details:"
sacct -j $JOBID --format=JobID,JobName,State,ExitCode,Elapsed,MaxRSS,NodeList

echo ""
echo "============================================"
echo "Log Files:"
echo "============================================"

# Find log files
LOG_OUT=$(ls -t burgly_${JOBID}.out 2>/dev/null | head -1)
LOG_ERR=$(ls -t burgly_${JOBID}.err 2>/dev/null | head -1)

if [ -n "$LOG_OUT" ]; then
    echo "Output log: $LOG_OUT"
    echo ""
    echo "Last 30 lines of output:"
    tail -30 "$LOG_OUT"
else
    echo "Output log not yet created"
fi

echo ""
if [ -n "$LOG_ERR" ] && [ -s "$LOG_ERR" ]; then
    echo "============================================"
    echo "Error log: $LOG_ERR"
    echo ""
    tail -20 "$LOG_ERR"
fi

echo ""
echo "============================================"
echo "To follow live output:"
echo "  tail -f $LOG_OUT"
echo "============================================"
