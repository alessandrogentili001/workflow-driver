# Snakemake Cluster Helper Scripts

This directory contains the helper scripts used by Snakemake's `cluster-generic` executor to manage jobs on the remote Leonardo SLURM cluster from a local WSL environment.

These scripts act as the bridge between the local Snakemake orchestrator and the remote execution environment.

## 1. `cluster_generic_submit.sh`

This script is responsible for taking a job script generated locally by Snakemake and submitting it to the remote cluster via SSH.

Because the local machine (WSL) and the cluster (Leonardo) do not share the same filesystem, this script performs several critical "translation" steps:

- **Remote Preparation**: Creates necessary `.snakemake` directories and symlinks on the remote filesystem so the job can find inputs inside the SFTP storage cache.
- **Path Virtualization**: Uses `sed` to search-and-replace all local WSL paths in the Snakemake-generated job script with the corresponding native Leonardo cluster paths. Without this, the remote job would instantly crash looking for local directories like `/mnt/c/Users/...`.
- **Dynamic Resource Parsing**: Uses Python to parse the `# properties` JSON injected by Snakemake into the generated job script. This extracts the `resources` defined in your Snakefile (e.g., `mem_mb`, `runtime`, `cpus_per_task`, `ntasks_per_node`, `slurm_partition`, `slurm_account`) and passes them dynamically to `sbatch`.
- **Job Submission**: Uploads the modified job script to the cluster and submits it using `sbatch`.

## 2. `cluster_generic_status.sh`

This script is used by Snakemake to periodically check the status of a submitted job.

- **Robust SSH Handling**: It includes a custom `ssh_run` wrapper function that implements exponential backoff. This ensures that if the SSH connection temporarily drops (returning exit code 255), Snakemake will retry instead of instantly assuming the job failed and crashing the workflow.
- **Two-Tier State Checking**:
  1. It first queries `squeue` to see if the job is actively running or pending.
  2. If the job is no longer in `squeue` (because it finished), it falls back to querying `sacct` for historical state data.
- It returns standard states (`success`, `running`, `failed`) expected by Snakemake.

## 3. `cluster_generic_cancel.sh`

This is a minimal script called by Snakemake if the workflow is interrupted (e.g., you press Ctrl+C). It connects via SSH and runs `scancel <jobid>` to kill the job on the remote SLURM cluster.
