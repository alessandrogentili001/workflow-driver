#!/usr/bin/env bash
# Robust Snakemake status checker for Slurm with SSH connection retries
set -euo pipefail

jobid="$1"

# Load generalized paths
source "$(dirname "$0")/cluster_config.sh"

# Helper to run SSH command with retries for connection errors (exit code 255)
ssh_run() {
  local max_attempts=5
  local attempt=1
  local exit_code=0
  while [ $attempt -le $max_attempts ]; do
    local tmp_out
    tmp_out=$(mktemp)
    if ssh -o BatchMode=yes -o ConnectTimeout=5 "${REMOTE_HOST}" "$@" > "$tmp_out" 2>/dev/null; then
      cat "$tmp_out"
      rm -f "$tmp_out"
      return 0
    fi
    exit_code=$?
    rm -f "$tmp_out"
    if [ $exit_code -ne 255 ]; then
      # If it's a Slurm/command error rather than an SSH connection error, return immediately
      return $exit_code
    fi
    # Exponential backoff before retrying SSH connection
    sleep $((attempt * 2))
    attempt=$((attempt + 1))
  done
  return 255
}

# Check if the job is in squeue (live queue)
if squeue_out=$(ssh_run "squeue -j ${jobid} -h -o %t" 2>/dev/null); then
  if [ -n "${squeue_out}" ]; then
    echo running
    exit 0
  fi
fi

# If not in squeue, query sacct for historical state
if sacct_out=$(ssh_run "sacct -j ${jobid} --format=State --noheader" 2>/dev/null); then
  state=$(echo "${sacct_out}" | head -n 1 | awk '{print $1}')
else
  # If SSH failed completely, assume running to prevent Snakemake from aborting prematurely
  echo running
  exit 0
fi

# Fallback to scontrol if sacct is lagging (known issue on Leonardo)
if [ -z "$state" ]; then
  if scontrol_out=$(ssh_run "scontrol show job ${jobid}" 2>/dev/null); then
    state=$(echo "${scontrol_out}" | grep -o 'JobState=[A-Z]*' | cut -d= -f2 || true)
  fi
fi

# If state is STILL empty, assume running to let Slurm catch up
if [ -z "$state" ]; then
  echo running
  exit 0
fi

case "$state" in
  COMPLETED)
    scp -r -o BatchMode=yes "${REMOTE_HOST}:${REMOTE_WORKDIR}/cavity/logs" "${LOCAL_WORKDIR}/cavity/" >/dev/null 2>&1 || true
    echo success
    ;;
  RUNNING|PENDING|REQUEUED|CONFIGURING|COMPLETING)
    echo running
    ;;
  *)
    scp -r -o BatchMode=yes "${REMOTE_HOST}:${REMOTE_WORKDIR}/cavity/logs" "${LOCAL_WORKDIR}/cavity/" >/dev/null 2>&1 || true
    echo failed
    ;;
esac

