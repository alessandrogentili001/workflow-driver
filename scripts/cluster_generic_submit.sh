#!/usr/bin/env bash
# Local wrapper script for Snakemake cluster-generic job submission
set -euo pipefail

# Snakemake passes the local jobscript path as the first argument ($1)
local_script="$1"
filename=$(basename "${local_script}")

# Load generalized paths
source "$(dirname "$0")/cluster_config.sh"

# 1. Setup remote directory and virtual input paths on Leonardo
remote_dir="${REMOTE_WORKDIR}/.snakemake"
ssh -o BatchMode=yes "${REMOTE_HOST}" "mkdir -p ${remote_dir} ${REMOTE_WORKDIR}/cavity/logs"
storage_base="${remote_dir}/storage/sftp/${REMOTE_STORAGE_HOST}${REMOTE_WORKDIR}"
ssh -o BatchMode=yes "${REMOTE_HOST}" "mkdir -p ${storage_base} && ln -sfn ${REMOTE_WORKDIR}/data ${storage_base}/data && ln -sfn ${REMOTE_WORKDIR}/loop_files ${storage_base}/loop_files && ln -sfn ${REMOTE_WORKDIR}/cavity ${storage_base}/cavity"

# Ensure the cluster's Snakefiles are up-to-date with WSL, otherwise remote Snakemake evaluation crashes
scp -o BatchMode=yes workflow/cavity_workflow.smk "${REMOTE_HOST}:${REMOTE_WORKDIR}/workflow/cavity_workflow.smk" >/dev/null 2>&1

# 2. Path virtualization: Replace all local WSL paths inside the jobscript with cluster-native Leonardo paths
sed -i "s|${LOCAL_WORKDIR}|${REMOTE_WORKDIR}|g" "${local_script}"
sed -i "s|${LOCAL_VENV}|${REMOTE_VENV}|g" "${local_script}"
sed -i "s|${LOCAL_CACHE}|${REMOTE_CACHE}|g" "${local_script}"
sed -i 's|--storage-sftp-timeout [0-9]*||g' "${local_script}"
sed -i 's|--default-storage-provider [^ ]*||g' "${local_script}"
sed -i 's|--default-storage-prefix [^ ]*||g' "${local_script}"
sed -i 's|--storage-sftp-username [^ ]*||g' "${local_script}"

# Extract any --wait-for-files temporary directories and ensure they exist on Leonardo
wait_dir=$(grep -o -E "\-\-wait-for-files '[^']+'" "${local_script}" | head -n 1 | cut -d"'" -f2 || true)
if [ -n "${wait_dir}" ]; then
  # Create the wait directory on Leonardo GPFS to satisfy the remote orchestrator's wait check
  ssh -o BatchMode=yes "${REMOTE_HOST}" "mkdir -p ${wait_dir}"
fi

# 3. Copy the virtualized local Snakemake jobscript to the GPFS shared filesystem .snakemake folder
scp -o BatchMode=yes "${local_script}" "${REMOTE_HOST}:${remote_dir}/${filename}" >/dev/null 2>&1

# Extract properties JSON from the second line of the local job script
PROPERTIES_JSON=$(sed -n '2p' "${local_script}" | sed 's/^# properties = //')

# Parse resources dynamically using Python
SLURM_ACCOUNT=$(echo "$PROPERTIES_JSON" | python3 -c 'import sys, json; print(json.load(sys.stdin).get("resources", {}).get("slurm_account", "phd_gentili_0"))')
SLURM_PARTITION=$(echo "$PROPERTIES_JSON" | python3 -c 'import sys, json; print(json.load(sys.stdin).get("resources", {}).get("slurm_partition", "dcgp_usr_prod"))')
SLURM_TIME=$(echo "$PROPERTIES_JSON" | python3 -c 'import sys, json; print(json.load(sys.stdin).get("resources", {}).get("runtime", 10))')
SLURM_CPUS=$(echo "$PROPERTIES_JSON" | python3 -c 'import sys, json; print(json.load(sys.stdin).get("resources", {}).get("cpus_per_task", 4))')
SLURM_MEM_MB=$(echo "$PROPERTIES_JSON" | python3 -c 'import sys, json; print(json.load(sys.stdin).get("resources", {}).get("mem_mb", 32000))')
SLURM_NTASKS=$(echo "$PROPERTIES_JSON" | python3 -c 'import sys, json; print(json.load(sys.stdin).get("resources", {}).get("ntasks_per_node", 1))')

# 4. Submit the job via SSH to SLURM on Leonardo.
# We wrap the command to activate conda, run the script from the shared folder, and clean it up afterward.
ssh -o BatchMode=yes "${REMOTE_HOST}" "sbatch \
  --account=${SLURM_ACCOUNT} \
  --partition=${SLURM_PARTITION} \
  --time=${SLURM_TIME} \
  --cpus-per-task=${SLURM_CPUS} \
  --ntasks-per-node=${SLURM_NTASKS} \
  --mem=${SLURM_MEM_MB}M \
  --output=${REMOTE_WORKDIR}/cavity/logs/slurm-%j.out \
  --error=${REMOTE_WORKDIR}/cavity/logs/slurm-%j.out \
  --parsable \
  --wrap 'cd ${REMOTE_WORKDIR}/ && source ${REMOTE_VENV}/bin/activate && bash ${remote_dir}/${filename} && rm -f ${remote_dir}/${filename}'"
