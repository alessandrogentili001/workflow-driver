# Workflow Driver

> *This project is carried out as part of the [SciFi-Turbo](https://scifiturbo.eu/) European project on behalf of CINECA as the HPC partner.*

## Scope of the Project
The scope of this project is to develop a customizable workflow driver to manage complex Computational Fluid Dynamics (CFD) simulations automatically. It demonstrates how to robustly orchestrate CFD tasks using Snakemake. The workflow is designed to seamlessly support two execution modes:
1. **Remote Orchestration**: The workflow manager runs on a local Linux-based machine (or on the Windows Subsystem for Linux) and orchestrates jobs on a remote HPC cluster.
2. **Local Execution**: The workflow manager runs directly on the HPC cluster's frontend node (or inside a dedicated Slurm job).

Furthermore, the repository provides two workflow paradigms:
- **Standard Checkpoint Workflow** (`workflow/cavity_workflow.smk`): Sequential simulation runs where parameter steering (`controlDict` update) occurs between successive simulation steps.
- **Concurrent In-Flight Check Workflow** (`workflow/cavity_workflow_concurrent_check.smk`): In-flight monitoring where a Python checker runs concurrently alongside OpenFOAM inside the same Slurm job, records timesteps as a NumPy tensor on disk, and terminates the solver early once target conditions are met.

## Repository Structure

This repository cleanly separates the workflow orchestration logic, configuration profiles, helper scripts, and simulation case data:

- `workflow/`: Contains Snakemake workflow definitions:
  - `cavity_workflow.smk`: Standard reference pipeline with post-run checkpoint evaluation.
  - `cavity_workflow_concurrent_check.smk`: Pipeline with concurrent in-flight monitoring and dynamic steering.
- `profiles/`: Configuration profiles for different cluster environments and workflow types:
  - `my-local.yaml` & `my-remote.yaml`: Generic, heavily commented templates to customize for any HPC cluster.
  - `leonardo-local.yaml` & `leonardo-remote.yaml`: Profiles for standard execution on the CINECA Leonardo cluster.
  - `leonardo-local-concurrent-check.yaml` & `leonardo-remote-concurrent-check.yaml`: Profiles for concurrent check execution on Leonardo.
  - `lumi-local.yaml` & `lumi-remote.yaml`: Profiles for execution on the LUMI supercomputer.
- `scripts/`: Centralized environment configurations and SSH remote submission wrappers:
  - `cluster_config.sh.example`: Template centralizing working directories, virtual environments, and network hosts.
  - `cluster_config.sh.leonardo` / `cluster_config.sh.lumi`: Pre-configured environment setups for specific clusters.
  - `remote_submit.sh`, `remote_status.sh`, `remote_cancel.sh`: SSH-based wrapper scripts for remote Slurm orchestration.
- `cavity/`: The OpenFOAM case directory:
  - `0/`, `constant/`, `system/`: Case mesh, boundary, and solver definitions.
  - `pre`, `dec`, `run`, `clean`: Shell scripts for `blockMesh`, `decomposePar`, `icoFoam`, and cleanup.
  - `run_with_concurrent_check`: Wrapper executing `icoFoam` and `checker.py` concurrently using Slurm step resource sharing (`srun --overlap`).
  - `checker.py`: Python daemon executing the 3-step pipeline (read log -> persist NumPy tensor on disk -> inspect & terminate).
- `.env`: Environment variables and cluster modules (e.g., `module load openfoam+/2106`).
- `.gitattributes`: Enforces Unix `LF` line endings across all shell scripts, Snakefiles, and config files.
- `makefile`: Provides convenient commands for running, inspecting DAGs, and cleaning the workflow.
- `requirements.txt`: Python dependencies required for workflow orchestration.

```text
.
├── .env
├── .gitattributes
├── requirements.txt
├── makefile
├── README.md
├── cavity/
│   ├── 0/
│   ├── constant/
│   ├── system/
│   ├── pre
│   ├── dec
│   ├── run
│   ├── run_with_concurrent_check
│   ├── checker.py
│   └── clean
├── profiles/
│   ├── my-local.yaml
│   ├── my-remote.yaml
│   ├── leonardo-local.yaml
│   ├── leonardo-local-concurrent-check.yaml
│   ├── leonardo-remote.yaml
│   ├── leonardo-remote-concurrent-check.yaml
│   ├── lumi-local.yaml
│   └── lumi-remote.yaml
├── scripts/
│   ├── cluster_config.sh.example
│   ├── cluster_config.sh.leonardo
│   ├── cluster_config.sh.lumi
│   ├── cluster_config.sh
│   ├── remote_cancel.sh
│   ├── remote_status.sh
│   └── remote_submit.sh
└── workflow/
    ├── cavity_workflow.smk
    └── cavity_workflow_concurrent_check.smk
```

## Getting Started

### Prerequisites
- `make` and a `python` distribution (3.10+) with virtual environment support.
- Access to an HPC cluster (e.g. Leonardo or LUMI) with the Slurm scheduler.
- OpenFOAM installed and accessible via environment modules on the cluster.
- A Linux-based machine or a Windows machine with WSL enabled.
- **Passwordless SSH**: If orchestrating remotely, configure an SSH host alias in your `~/.ssh/config` on your local machine so that `ssh <remote_host>` connects without password prompts:

  ```sshconfig
  Host leonardo
      HostName login.leonardo.cineca.it
      User <your-hpc-username>

  Host lumi
      HostName lumi.csc.fi
      User <your-hpc-username>
      IdentityFile ~/.ssh/id_rsa
  ```

  Verify your connection (example for Leonardo) by running:
  ```bash
  ssh leonardo
  ```

  Warning:

  > **CINECA Step CA Authentication**: If accessing Leonardo via CINECA OIDC SSO, activate your SSH agent session before running Snakemake:
  > ```bash
  > ssh-keygen -f '~/.ssh/known_hosts' -R 'login.leonardo.cineca.it'
  > eval "$(ssh-agent -s)"
  > step ssh login 'your.email@cineca.it' --provisioner cineca-hpc
  > ```
  > 
  > **Paramiko SSH Certificate Patch**: When using Snakemake's SFTP plugin with SSH certificates (like those generated by `step ssh login`), you might encounter an `AttributeError: public_blob` crash. Patch `paramiko` inside your virtual environment:
  > ```bash
  > python <<PY
  > import paramiko.agent
  > file_path = paramiko.agent.__file__
  > code = open(file_path).read()
  > code = code.replace('def __getattr__(self, name):', \
  >     'def __getattr__(self, name):\n        if name == \'public_blob\': return None')
  > open(file_path, 'w').write(code)
  > print('Patched paramiko successfully')
  > PY
  > ```

### Setup

Repeat the following steps for both the local machine and the HPC cluster:

1. **Clone the repository**:
   ```bash
   git clone https://gitlab.hpc.cineca.it/agentil1/workflow-driver.git
   cd workflow-driver
   ```
2. **Create the virtual environment and install dependencies**:
   ```bash
   python3 -m venv venv
   source venv/bin/activate
   pip install -r requirements.txt
   ```
3. **Configure cluster environment variables**:
   Create your `scripts/cluster_config.sh` by copying the template or cluster preset:
   ```bash
   # For Leonardo
   cp scripts/cluster_config.sh.leonardo scripts/cluster_config.sh

   # Or customize from template
   cp scripts/cluster_config.sh.example scripts/cluster_config.sh
   ```
   Update the exported paths (`LOCAL_WORKDIR`, `REMOTE_WORKDIR`, `REMOTE_HOST`, etc.) to match your setup and run it inside the virtual environment:
   ```bash
   source scripts/cluster_config.sh
   ```
4. **Review and configure the cluster module environment (`.env`)**:
   The `.env` file is automatically sourced by Snakemake on the HPC compute nodes before every rule executes (via `shell.prefix(...)` in the workflow). It ensures that all required compilers, MPI libraries, and CFD solvers are available in the job's execution shell.

   **Current Content of `.env`:**
   ```bash
   # Load engineering environment domain profile (on Leonardo)
   module load profile/eng 

   # Load OpenFOAM module
   module load openfoam+/2106
   ```

5. **Review and customize execution profiles (`profiles/*.yaml`)**:
   Snakemake profiles define default Slurm hardware resources, execution backends, and scheduler parameters, eliminating the need to type long command-line flags. 
   
   **Which Profile to Edit:**
   - **Local execution on Leonardo**: Edit `profiles/leonardo-local.yaml` (or `profiles/leonardo-local-concurrent-check.yaml`).
   - **Remote orchestration to Leonardo**: Edit `profiles/leonardo-remote.yaml` (or `profiles/leonardo-remote-concurrent-check.yaml`).
   - **Other clusters (e.g. LUMI, MeluXina, local cluster)**: Copy and adapt the template files `profiles/my-local.yaml` and `profiles/my-remote.yaml`.

   **Key Parameters to Customize:**

   - **Target Workflow (`snakefile`)**:
     ```yaml
     snakefile: workflow/cavity_workflow.smk
     # Or for in-flight concurrent monitoring:
     # snakefile: workflow/cavity_workflow_concurrent_check.smk
     ```
   - **Slurm Account & Queue (`default-resources`)**:
     ```yaml
     default-resources:
       slurm_account: "phd_gentili_0"       # MUST change to your active HPC project / account budget
       slurm_partition: "dcgp_usr_prod"    # Slurm partition (e.g. "dcgp_usr_prod" on Leonardo, "standard" on LUMI)
       runtime: 1440                       # Maximum walltime in minutes (1440 = 24 hours)
     ```
   - **Hardware & CPU Allocation**:
     ```yaml
       nodes: 1                            # Number of compute nodes per job
       tasks: 8                            # Total MPI tasks (MUST match numberOfSubdomains in decomposeParDict)
       ntasks_per_node: 8                  # MPI tasks per node
       cpus_per_task: 1                    # CPU threads per task (increase for hybrid MPI+OpenMP)
       mem: "16G"                          # Memory requested per node (e.g. "16G", "32G", "64G")
       mpi: "srun"                         # Slurm MPI launcher
       # gpu: 1                            # Uncomment and specify count if running on GPU partitions (e.g. Leonardo Booster)
     ```

     > Ensure that `tasks` matches the domain decomposition parameter `numberOfSubdomains` in your OpenFOAM case (`system/decomposeParDict`). For the concurrent check workflow, `tasks` is set to `9` (8 simulation cores + 1 monitoring core to allow the checker run on it).

   - **Remote Orchestration Parameters (`profiles/*-remote.yaml` only)**:
     ```yaml
     default-storage-prefix: "sftp://login.leonardo.cineca.it:22/leonardo_work/PHD_gentili/workflow-driver/"
     storage-sftp-username: "<your-hpc-username>"  # e.g. "agentil1", "zanellit"
     # storage-sftp-key-file: "/home/<user>/.ssh/id_rsa"  # Optional: path to private key if not in ssh-agent
     ```
     - `default-storage-prefix`: Format `sftp://<REMOTE_STORAGE_HOST>:<PORT>/<REMOTE_WORKDIR>/`. Points to the remote repository on the cluster filesystem where files are synced.
     - `storage-sftp-username`: Your remote cluster username.

---

## Architecture and Execution

The workflow can be executed either remotely (orchestrator on your machine) or locally (orchestrator directly on the cluster).

### 1. Remote Orchestration

In remote orchestration mode, a **Split-Brain** architecture is used:
- **Local Machine**: Runs `snakemake`, evaluates the DAG, handles dynamic checkpoint logic, and tracks workflow state.
- **Compute Backend (HPC)**: Executes the compute steps (`blockMesh`, `decomposePar`, `icoFoam`) via Slurm jobs.

**Mechanisms**:
- **SFTP Storage Sync**: `snakemake-storage-plugin-sftp` pushes inputs and downloads results between local and remote filesystems.
- **SSH Job Submission**: The `cluster-generic` executor delegates job submission to `scripts/remote_submit.sh`, which virtualizes paths and submits via SSH `sbatch`.
- **Status & Log Retrieval**: `scripts/remote_status.sh` checks Slurm status via SSH and syncs `cavity/logs/` back to the local machine.
- **Dynamic Checkpoints**: The checkpoint Python function evaluates logs remotely over SSH and runs `foamDictionary` to steer simulation parameters.

**Running Standard Workflow Remotely**:
```bash
snakemake --profile profiles/leonardo-remote.yaml --rerun-incomplete
```

**Running Concurrent Check Workflow Remotely**:
```bash
snakemake --profile profiles/leonardo-remote-concurrent-check.yaml --rerun-incomplete
```

---

### 2. Local Execution

When running directly on the cluster login node (or inside an interactive Slurm session), both the orchestrator and the compute backend share the exact same environment and filesystem:

**Mechanisms**:
- **Native Slurm Executor**: Jobs are submitted directly to the Slurm queue using `snakemake-executor-plugin-slurm`.
- **Zero Transfer Overhead**: No SFTP transfers or path virtualization are required.
- **Direct Log Evaluation**: Checkpoints inspect log files and run `foamDictionary` natively on the cluster filesystem.

**Running Standard Workflow on Leonardo**:
```bash
snakemake --profile profiles/leonardo-local.yaml --rerun-incomplete
```

**Running Concurrent Check Workflow on Leonardo**:
```bash
snakemake --profile profiles/leonardo-local-concurrent-check.yaml --rerun-incomplete
```

---

## Concurrent Simulation Monitoring & Checkpointing

The concurrent check workflow (`cavity_workflow_concurrent_check.smk`) demonstrates **concurrent monitoring and steering** of the ongoing CFD simulation. The idea is to run the CFD simulation in parallel with a checker script that monitors the simulation progress and steers it (e.g., by terminating it when a certain condition is met). This is particularly useful for long-running simulations or when you want to perform complex termination or restart conditions.

1. **Slurm Step Overlap (`srun --overlap`)**:
   In `cavity/run_with_concurrent_check`, both `icoFoam` (8 MPI tasks) and `checker.py` (1 task) run concurrently within a 9-core Slurm allocation. Passing `--overlap` prevents Slurm from exclusively locking memory/GRES to the first job step.

2. **3-Step Tensor Monitoring Pipeline (`cavity/checker.py`)**:
   - **Step 1 (Ingest):** Scans `log.icoFoam` for progress timestamps (`Time = ...`).
   - **Step 2 (Persist):** Converts timestamps into a 1D NumPy tensor and writes it to disk as `cavity/timesteps.npy` via `np.save()`.
   - **Step 3 (Inspect & Terminate):** Loads `timesteps.npy` via `np.load()`, verifies the latest timestep against `target_time`, and gracefully shuts down `icoFoam` using `os.kill(sim_pid, signal.SIGTERM)`.

3. **Dynamic Feedback Loop**:
   Snakemake's `check_simulation` function evaluates checkpoint outputs dynamically:
   - If target time is satisfied, it completes the loop and triggers `finalize_simulation`.
   - If not yet satisfied, it updates `controlDict` (`endTime`) using `foamDictionary` and launches the next iteration step ($i = 1, 2, 3 \dots$).

---

## Useful Commands

The provided `makefile` streamlines everyday tasks:

```bash
# View available make commands
make help

# Create or update virtual environment with dependencies
make setup

# Render the workflow DAG as an SVG image
make dag

# Dry-run the workflow to preview scheduled tasks
make dry-run

# Run Snakemake directly using the configured profile
make run

# Clean generated outputs, logs, processor directories, and numpy tensors
make clean
```

---

## Customizing for Your Own Simulations

To adapt this framework to your own CFD simulation or solver:
- **Replace Case Data**: Swap the contents of `cavity/` with your OpenFOAM case (or another solver).
- **Update Workflow Rules**: Modify `workflow/cavity_workflow.smk` or `workflow/cavity_workflow_concurrent_check.smk` to adjust preprocessing, solver commands, or checkpoint criteria.
- **Adjust Resource Allocations**: Edit `default-resources` in the profile YAML files (`nodes`, `tasks`, `cpus_per_task`, `mem`, `runtime`, `gpu`).
- **Update Folder Paths**: If renaming `cavity/`, update corresponding folder references in `scripts/remote_submit.sh`, `scripts/remote_status.sh`, and the `makefile`.
