########################
### LOAD ENVIRONMENT ###
########################

# Load the .env for all rules automatically
shell.prefix("mkdir -p cavity/logs && [ -s .env ] && source .env >> cavity/logs/env_setup.log 2>&1 || true; ")

##################
### RULE NODES ###
##################

rule all:
    input:
        "cavity/simulation_done.txt"

rule prepare_mesh:
    output:
        "cavity/log.blockMesh"
    log:
        "cavity/logs/prepare_mesh.log"
    shell:
        """
        # Run the pre script
        bash cavity/pre > {log} 2>&1
        cat cavity/log.blockMesh >> {log}
        """

rule decompose_mesh:
    input:
        "cavity/log.blockMesh"
    output:
        "cavity/log.decomposePar"
    log:
        "cavity/logs/decompose_mesh.log"
    shell:
        """
        # Decompose the mesh
        bash cavity/dec > {log} 2>&1
        cat cavity/log.decomposePar >> {log}
        """

########################
### CHECKPOINT NODES ###
########################

checkpoint run_simulation_with_concurrent_check:
    input:
        "cavity/log.decomposePar"
    output:
        "cavity/logs/simulation_run_{i}.log"
    shell:
        """
        bash cavity/run_with_concurrent_check
        cp cavity/log.icoFoam {output} || touch {output}
        """

########################
### HELPER FUNCTIONS ###
########################

TARGET_SIMULATION_TIME = 0.01

# Be aware that this runs only where the snakemake workflow manager is running
# It automatically detects whether the workflow manager is running locally or on the
# remote HPC cluster and uses the appropriate method to read the simulation logs
def check_simulation(wildcards):
    import re
    import subprocess

    i = 1
    while True:
        # get() will trigger the checkpoint to run if it hasn't already
        # We don't use .output[0] because the file isn't downloaded locally
        checkpoints.run_simulation_with_concurrent_check.get(i=i)

        # Smart check: If the file exists natively, we are evaluating on the cluster.
        # If not, we are orchestrating from WSL and must use SSH.
        remote_log = f"{config['remote_workdir']}/cavity/logs/simulation_run_{i}.log"
        remote_host = config.get('remote_host', 'leonardo')
        try:
            import os
            if os.path.exists(remote_log):
                with open(remote_log, 'r') as f:
                    content = f.read()
            else:
                content = subprocess.check_output(
                    ["ssh", "-o", "BatchMode=yes", remote_host, f"cat {remote_log}"],
                    text=True
                )
        except subprocess.CalledProcessError:
            raise ValueError(f"Failed to read simulation log on cluster: {remote_log}")

        # Check if the simulation timestep is reached
        times = re.findall(r'^Time = ([\d\.]+)', content, re.MULTILINE)
        if times:
            latest_time = float(times[-1])
            if latest_time >= TARGET_SIMULATION_TIME or i >= 5:
                # Target time reached or
                # Return the relative path so Snakemake wraps it in the SFTP storage plugin
                return f"cavity/logs/simulation_run_{i}.log"
            else:
                # Target not reached, increase endTime by 0.001 for the next run
                new_end_time = round(latest_time + 0.001, 4)
                if new_end_time > TARGET_SIMULATION_TIME:
                    new_end_time = TARGET_SIMULATION_TIME

                # Update controlDict directly ON THE CLUSTER
                update_cmd = (
                    f"cd {config['remote_workdir']} && "
                    "source .env && "
                    f"foamDictionary cavity/system/controlDict -entry endTime -set {new_end_time}"
                )

                if os.path.exists(remote_log):
                    subprocess.run(update_cmd, shell=True, executable='/bin/bash', check=True)
                else:
                    result = subprocess.run(
                        ["ssh", "-o", "BatchMode=yes", remote_host, update_cmd],
                        capture_output=True, text=True,
                    )

            # Prepare to run next iteration
            i += 1
        else:
            # If no time was outputted at all, the simulation failed immediately.
            raise ValueError(f"Simulation failed to output any time in {remote_log}")

######################
### FINALIZER RULE ###
######################

rule finalize_simulation:
    input:
        check_simulation
    output:
        "cavity/simulation_done.txt"
    shell:
        """
        mkdir -p $(dirname {output})
        touch {output}
        """