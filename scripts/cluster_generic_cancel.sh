#!/usr/bin/env bash
set -euo pipefail

# Load generalized paths
source "$(dirname "$0")/cluster_config.sh"

jobid="$1"
ssh -o BatchMode=yes "${REMOTE_HOST}" "scancel ${jobid}"
