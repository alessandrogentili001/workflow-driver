# Workflow Driver

> *This project is carried out as part of the [SciFi-Turbo](https://scifiturbo.eu/) European project on behalf of CINECA as the HPC partner.*

## Scope of the Project
The scope of this project is to develop a customizable workflow driver to manage complex Computational Fluid Dynamics (CFD) simulations automatically. It demonstrates how to robustly orchestrate these CFD tasks using Snakemake. The workflow is designed with a single dynamic Snakefile (acting as the driver) that seamlessly supports two execution modes:
1. **Local Orchestration**: The workflow manager runs on your local machine (WSL) and orchestrates jobs on a remote HPC cluster.
2. **Native Execution**: The workflow manager runs directly on the HPC cluster's frontend node (or inside a dedicated slurm job).

## Repository Structure

This repository is carefully organized to cleanly separate the workflow orchestration logic, configuration profiles, helper scripts, and the actual simulation case data.

- `workflow/`: Contains the single Snakemake logic (`cavity_workflow.smk`) that adapts to your environment automatically.
- `profiles/`: Configuration profiles for different environments (`generic.yaml` for local WSL, and `leonardo.yaml` for native execution directly on Leonardo machine frontend node).
- `scripts/`: Helper bash scripts for cluster submission and status checking (required only for local orchestration), along with centralized configurations (`cluster_config.sh`) to virtualize paths between WSL and HPC.
- `cavity/`: The actual OpenFOAM case directory containing `0`, `constant`, and `system` configurations.
- `makefile`: Provides convenient commands for running and cleaning the workflow.
- `requirements.txt`:Txt specification containing all required dependencies.

```text
.
├── .env
├── requirements.txt
├── makefile
├── README.md
├── cavity/
│   ├── 0/
│   ├── constant/
│   └── system/
├── profiles/
│   ├── generic.yaml
│   └── leonardo.yaml
├── scripts/
│   ├── cluster_config.sh
│   ├── cluster_generic_cancel.sh
│   ├── cluster_generic_status.sh
│   └── cluster_generic_submit.sh
└── workflow/
    └── cavity_workflow.smk
```

## Getting Started

### Prerequisites
- You only need `make` and standard `python3` with `venv` module. All dependencies will be installed locally in a virtual environment.
- Access to the HPC cluster (e.g. Leonardo) having Slurm installed.
- OpenFOAM modules available on the cluster.
- WSL or a linux-based enviroment installed on the local machine.
- **Passwordless SSH**: If orchestrating locally, configure an SSH alias (e.g., `leonardo`) using an SSH key in your `~/.ssh/config`.

### Setup

Repeat the following steps both for the local and HPC environments:

1. Clone the repository
   ```bash
   git clone https://gitlab.hpc.cineca.it/agentil1/workflow-driver.git
   cd workflow-driver
   ```
2. Create the virtual environment and install dependencies:
   ```bash
   python3 -m venv venv 
   source venv/bin/activate
   pip install -r requirements.txt
   ```
3. Update paths in `scripts/cluster_config.sh` to match your local paths and remote HPC directories.
4. Review the `.env` file to ensure the correct OpenFOAM modules are loaded on the cluster.

## Architecture and Usage

The workflow can be executed in two primary ways depending on where you run the orchestrator.

### 1. Local Orchestration

When orchestrating from your local WSL machine, we employ a "Split-Brain" architecture:
- **The Orchestrator (WSL)** runs `snakemake`, builds the DAG, and manages job dependencies.
- **The Compute Backend (Leonardo)** receives jobs, executes the simulations, and stores data on the remote filesystem.

**How it works**:
- **Storage Syncing**: `snakemake-storage-plugin-sftp` automatically pushes inputs and pulls outputs between the local machine and the remote HPC cluster filesystem.
- **Job Submission**: The `cluster-generic` executor passes a generated jobscript to `scripts/cluster_generic_submit.sh`, which virtualizes paths and submits to Slurm via an SSH `sbatch` command.
- **Log Synchronization**: Whenever a job finishes (successfully or failed), the `cluster_generic_status.sh` script automatically uses `scp` to pull the latest `cavity/logs/` directory back to your local machine.
- **Dynamic Checkpoints**: The workflow loops based on simulation times. When evaluating from WSL, the Python checkpoint function dynamically uses `ssh` to read the log remotely and execute `foamDictionary` directly on the cluster.

**To Run**:
```bash
snakemake --profile profiles/generic.yaml --rerun-incomplete
```

### 2. Native Execution

When running directly on the login node (or on a dedicated slurm job), the architecture is much simpler since both the orchestrator and the compute backend share the exact same environment and filesystem.

**How it works**:
- **No Path Virtualization**: The orchestrator and compute nodes share the same filesystem, bypassing the need for path mapping.
- **Native Slurm Executor**: We use a native Slurm plugin rather than wrapping jobs in SSH commands.
- **Dynamic Checkpoints**: The same checkpoint function automatically detects it is running locally on the shared filesystem and uses standard Python `open()` to read logs, bypassing SSH.

**To Run**:
```bash
snakemake --profile profiles/leonardo.yaml --rerun-incomplete
```

## Useful Commands

For common tasks, use the provided `makefile`:
```bash
# View available commands
make help

# Visualize the dag as png image
make dag 

# Run dry-run to preview the workflow steps (useful before submitting)
make dry-run

# Clean workflow generated files and logs (removes local logs and cavity output)
make clean
```

## Troubleshooting: Paramiko SSH Certificate Bug

When using Snakemake's SFTP plugin with SSH certificates (like those generated by CINECA's `step ssh login`), you might encounter an `AttributeError: public_blob` crash. This is a bug in the `paramiko` library when handling certificate keys in the SSH agent.

To fix this, patch the `paramiko` library directly inside your virtual environment:
```bash
python3 -c <<PY
import paramiko.agent
file_path = paramiko.agent.__file__
code = open(file_path).read()
code = code.replace('def __getattr__(self, name):', \\
    'def __getattr__(self, name):\\n        if name == \\'public_blob\\': return None')
open(file_path, 'w').write(code)
print('Patched paramiko successfully')
PY
```

## Understanding Snakemake and DAGs
This project relies heavily on Snakemake to manage task dependencies via Directed Acyclic Graphs (DAGs). Snakemake determines what needs to be run by building a graph of inputs and outputs. 

To understand how we create DAGs, define rules, and run workflows, please refer to the [official Snakemake repository](https://github.com/snakemake/snakemake) and its [official documentation](https://snakemake.readthedocs.io/). In particular, we suggest starting with the provided [tutorial](https://snakemake.readthedocs.io/en/stable/tutorial/basics.html).

## The Reference Example (Cavity)

The provided `workflow/cavity_workflow.smk` uses the classic OpenFOAM **cavity** simulation as a demonstration of how to structure a Snakemake pipeline. It is intended to be a **reference example**, rather than the rigid focus of the project.

The example workflow demonstrates the following logic:
1. **Mesh Preparation (`mesh_preparation`)**: Runs the `blockMesh` utility (via the `pre` script) to generate the mesh geometry.
2. **Domain Decomposition (`decompose_mesh`)**: Runs `decomposePar` (via the `dec` script) to split the mesh into subdomains for parallel execution.
3. **Simulation Loop (`run_simulation` & `check_simulation`)**: Executes the OpenFOAM solver (`icoFoam` via the `run` script) using a Snakemake **checkpoint**. The `check_simulation` Python function evaluates the simulation output (time step progress) and iteratively modifies the OpenFOAM dictionaries (`controlDict`) using `foamDictionary` to restart and advance the simulation until a target end time is reached.
4. **Finalization (`finalize_simulation`)**: Creates a dummy output file (`simulation_done.txt`) to formally close the DAG and notify Snakemake that the overall workflow is complete.

### Modifying the Workflow for Your Own Simulations

Because the cavity simulation is just a placeholder, you are fully empowered to modify the workflow logic, profiles, and configs to fit your specific CFD tasks and HPC cluster setup:
- **Swap the case directory**: Replace the `cavity/` folder with your own target simulation.
- **Update the Snakefile**: Edit `workflow/cavity_workflow.smk` to rename paths, change bash commands, or adjust the looping conditions in the checkpoint function.
- **Adjust Resources**: Modify the Snakemake rules to request different hardware (nodes, CPUs, GPUs, etc.) and update `profiles/generic.yaml` or `profiles/leonardo.yaml` as needed.
- **Update Synchronization Paths**: If your case folder is named differently (e.g., `motorBike/`), ensure you update the hardcoded folder references in the bash helper scripts (`scripts/cluster_generic_submit.sh` and `scripts/cluster_generic_status.sh`), specifically regarding the `logs/` directory synchronization.